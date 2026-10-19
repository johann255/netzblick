import Foundation
#if canImport(CommonCrypto)
import CommonCrypto
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Why a listening session could not start or ended early. Messages are shown as they are.
public enum ListenError: Error, Equatable, LocalizedError {
    case loginFailed(blockSeconds: Int)
    case missingRight
    case captureRefused
    case unsupportedFormat
    case notSupported

    public var errorDescription: String? {
        switch self {
        case .loginFailed(let seconds) where seconds > 0:
            return "Die Box hat die Anmeldung abgelehnt und sperrt neue Versuche für \(seconds) Sekunden."
        case .loginFailed:
            return "Die Box hat die Anmeldung abgelehnt. Stimmt das Kennwort noch?"
        case .missingRight:
            return "Deinem FRITZ!Box-Benutzer fehlt das Recht „FRITZ!Box Einstellungen“. Du findest es unter System → FRITZ!Box-Benutzer."
        case .captureRefused:
            return "Die Box hat den Mitschnitt verweigert. Läuft gerade schon ein anderer Mitschnitt?"
        case .unsupportedFormat:
            return "Die Box liefert den Mitschnitt in einem Format, das Netzblick noch nicht lesen kann."
        case .notSupported:
            return "Dieser Router kann nicht mitlauschen."
        }
    }
}

/// Login to the FRITZ!Box web interface (`login_sid.lua`), needed for the packet capture.
///
/// TR-064 does not offer the capture, so this is the one place Netzblick uses the web login.
public struct FritzWebSession: Sendable {
    /// e.g. http://192.168.178.1
    public let baseURL: URL
    private let transport: HTTPTransport

    public init(baseURL: URL, transport: HTTPTransport) {
        self.baseURL = baseURL
        self.transport = transport
    }

    /// Session id and whether the user may change box settings (needed for the capture).
    public struct Login: Hashable, Sendable {
        public var sid: String
        public var mayCapture: Bool
    }

    public func login(username: String, password: String) async throws -> Login {
        let info = try await sessionInfo(body: nil)
        guard let challenge = info.challenge else { throw ListenError.loginFailed(blockSeconds: 0) }
        let answer = try Self.response(challenge: challenge, password: password)
        let form = "username=\(Self.formEncode(username))&response=\(Self.formEncode(answer))"
        let result = try await sessionInfo(body: form)
        guard let sid = result.sid, sid != Self.invalidSID else {
            throw ListenError.loginFailed(blockSeconds: result.blockTime)
        }
        // VERIFY: the capture needs "BoxAdmin" with write access (2).
        return Login(sid: sid, mayCapture: result.rights["BoxAdmin"] == 2)
    }

    public func logout(sid: String) async {
        _ = try? await sessionInfo(body: "logout=1&sid=\(sid)")
    }

    static let invalidSID = "0000000000000000"

    // MARK: Challenge-response

    /// Answer to a `login_sid.lua` challenge: PBKDF2 ("2$…", FRITZ!OS 7.24+) or the older MD5 form.
    public static func response(challenge: String, password: String) throws -> String {
        if challenge.hasPrefix("2$") {
            let parts = challenge.split(separator: "$").map(String.init)
            guard parts.count == 5, let iter1 = UInt32(parts[1]), let iter2 = UInt32(parts[3]),
                  let salt1 = Data(hex: parts[2]), let salt2 = Data(hex: parts[4]) else {
                throw ListenError.loginFailed(blockSeconds: 0)
            }
            let hash1 = try pbkdf2(Data(password.utf8), salt: salt1, rounds: iter1)
            let hash2 = try pbkdf2(hash1, salt: salt2, rounds: iter2)
            return "\(parts[4])$\(hash2.hexString)"
        }
        #if canImport(CryptoKit)
        // Legacy: MD5 over UTF-16LE of "challenge-password".
        let text = "\(challenge)-\(password)"
        var bytes = Data()
        for unit in text.utf16 { bytes.append(contentsOf: [UInt8(unit & 0xFF), UInt8(unit >> 8)]) }
        return "\(challenge)-\(Insecure.MD5.hash(data: bytes).map { String(format: "%02x", $0) }.joined())"
        #else
        throw ListenError.notSupported
        #endif
    }

    static func pbkdf2(_ password: Data, salt: Data, rounds: UInt32) throws -> Data {
        #if canImport(CommonCrypto)
        var out = Data(count: 32)
        let status = out.withUnsafeMutableBytes { outBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self), password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                        outBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), 32
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw ListenError.loginFailed(blockSeconds: 0) }
        return out
        #else
        throw ListenError.notSupported
        #endif
    }

    // MARK: SessionInfo

    struct SessionInfo {
        var sid: String?
        var challenge: String?
        var blockTime: Int
        var rights: [String: Int]
    }

    private func sessionInfo(body: String?) async throws -> SessionInfo {
        var url = baseURL.appendingPathComponent("login_sid.lua")
        url = URL(string: url.absoluteString + "?version=2") ?? url
        let request = HTTPRequest(
            method: body == nil ? "GET" : "POST",
            url: url,
            headers: body == nil ? [:] : ["Content-Type": "application/x-www-form-urlencoded"],
            body: body.map { Data($0.utf8) }
        )
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            throw TR064Error.unreachable
        }
        guard response.statusCode == 200 else { throw TR064Error.httpStatus(response.statusCode) }
        return Self.parseSessionInfo(String(decoding: response.body, as: UTF8.self))
    }

    static func parseSessionInfo(_ xml: String) -> SessionInfo {
        func value(_ tag: String, in text: Substring) -> String? {
            guard let open = text.range(of: "<\(tag)>"), let close = text.range(of: "</\(tag)>", range: open.upperBound..<text.endIndex) else { return nil }
            return String(text[open.upperBound..<close.lowerBound])
        }
        let all = Substring(xml)
        var rights: [String: Int] = [:]
        if let block = value("Rights", in: all) {
            // <Rights><Name>Dial</Name><Access>2</Access><Name>BoxAdmin</Name><Access>2</Access>…</Rights>
            var rest = Substring(block)
            while let name = value("Name", in: rest), let nameEnd = rest.range(of: "</Name>") {
                rest = rest[nameEnd.upperBound...]
                if let access = value("Access", in: rest), let accessEnd = rest.range(of: "</Access>") {
                    rights[name] = Int(access) ?? 0
                    rest = rest[accessEnd.upperBound...]
                }
            }
        }
        return SessionInfo(
            sid: value("SID", in: all),
            challenge: value("Challenge", in: all),
            blockTime: value("BlockTime", in: all).flatMap(Int.init) ?? 0,
            rights: rights
        )
    }

    static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~$")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

extension Data {
    init?(hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }

    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
