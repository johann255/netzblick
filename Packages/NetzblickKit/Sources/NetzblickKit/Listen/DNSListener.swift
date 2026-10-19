import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Source of DNS questions from the home network while a listening session runs.
public protocol DNSListener: Sendable {
    /// Starts listening; ends when the consumer stops iterating (cancel the task) or on error.
    func queries() -> AsyncThrowingStream<DNSQuery, Error>
}

#if canImport(Darwin)
/// Listens through the FRITZ!Box packet capture (`/cgi-bin/capture_notimeout`).
///
/// Only DNS questions are taken from the stream; frames are parsed in memory and dropped at once.
public final class FritzDNSListener: NSObject, DNSListener, URLSessionDataDelegate, @unchecked Sendable {
    public let baseURL: URL
    public let credentials: BoxCredentials
    /// VERIFY: "1-lan" is the LAN bridge on current boxes and also carries Wi-Fi traffic.
    public let interface: String
    /// Bytes kept per frame; a DNS question fits easily, contents of other traffic are cut off.
    public let snapLength: Int

    private let lock = NSLock()
    private var reader = PcapReader()
    private var continuation: AsyncThrowingStream<DNSQuery, Error>.Continuation?

    public init(host: String, credentials: BoxCredentials, interface: String = "1-lan", snapLength: Int = 400) {
        self.baseURL = URL(string: "http://\(host)") ?? URL(string: "http://fritz.box")!
        self.credentials = credentials
        self.interface = interface
        self.snapLength = snapLength
    }

    public func queries() -> AsyncThrowingStream<DNSQuery, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { await self.run(continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ continuation: AsyncThrowingStream<DNSQuery, Error>.Continuation) async {
        let web = FritzWebSession(baseURL: baseURL, transport: URLSessionTransport(credentials: nil))
        let login: FritzWebSession.Login
        do {
            login = try await web.login(username: credentials.username, password: credentials.password)
        } catch {
            continuation.finish(throwing: error)
            return
        }
        guard login.mayCapture else {
            await web.logout(sid: login.sid)
            continuation.finish(throwing: ListenError.missingRight)
            return
        }

        lock.withLock {
            reader = PcapReader()
            self.continuation = continuation
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 24 * 3600
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: captureURL(sid: login.sid, action: "Start"))
        task.resume()

        // Wait until the consumer stops listening or the stream ends.
        while !Task.isCancelled, task.state == .running {
            try? await Task.sleep(for: .milliseconds(300))
        }
        task.cancel()
        session.invalidateAndCancel()
        // VERIFY: closing the connection may already stop the capture; the explicit stop is harmless.
        _ = try? await URLSession.shared.data(from: captureURL(sid: login.sid, action: "Stop"))
        await web.logout(sid: login.sid)
        lock.withLock { self.continuation = nil }
        continuation.finish()
    }

    func captureURL(sid: String, action: String) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("cgi-bin/capture_notimeout"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "ifaceorminor", value: interface),
            URLQueryItem(name: "snaplen", value: String(snapLength)),
            URLQueryItem(name: "capture", value: action),
            URLQueryItem(name: "sid", value: sid)
        ]
        return components.url!
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if (response as? HTTPURLResponse)?.statusCode == 200 {
            completionHandler(.allow)
        } else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            lock.withLock { continuation }?.finish(throwing: ListenError.captureRefused(detail: "HTTP \(status)"))
            completionHandler(.cancel)
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let frames: [CapturedFrame]
        do {
            frames = try reader.feed(data)
        } catch {
            let continuation = self.continuation
            lock.unlock()
            // An HTML page instead of pcap means the box refused (e.g. the session expired).
            continuation?.finish(throwing: error as? PcapReader.ReadError == .pcapNGUnsupported
                                 ? ListenError.unsupportedFormat : ListenError.captureRefused(detail: Self.excerpt(data)))
            dataTask.cancel()
            return
        }
        let continuation = self.continuation
        lock.unlock()
        for frame in frames {
            if let query = DNSQuery.parse(frame) { continuation?.yield(query) }
        }
    }

    /// First words of a text answer, without markup, for the error message.
    static func excerpt(_ data: Data) -> String {
        let text = String(decoding: data.prefix(400), as: UTF8.self)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(text.prefix(140))
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, (error as? URLError)?.code != .cancelled {
            lock.withLock { continuation }?.finish(throwing: error)
        }
    }
}
#endif

/// Plays a believable listening session for the demo household. Never touches the network.
public struct DemoDNSListener: DNSListener {
    /// Questions per second.
    public var rate: Double

    public init(rate: Double = 6) {
        self.rate = rate
    }

    /// What the demo devices ask for: (device index, names). Index matches `DemoHousehold`.
    static let script: [(Int, [String])] = [
        (1, ["a1.tuyaeu.com", "m1.tuyaeu.com", "time.espressif.com"]),
        (2, ["api.sonos.com", "msmetrics.ws.sonos.com", "spotify.com"]),
        (3, ["api.sonos.com", "msmetrics.ws.sonos.com"]),
        (5, ["log-config.samsungacr.com", "samsungacr.com", "samsungads.com", "samsungcloudsolution.com", "netflix.com", "nflxvideo.net"]),
        (7, ["device-metrics-us.amazon.com", "aax-eu.amazon-adsystem.com", "api.amazonalexa.com", "prime-video.amazon.dev"]),
        (9, ["gateway.icloud.com", "mail.posteo.de", "app-measurement.com", "graph.facebook.com", "spiegel.de", "googletagmanager.com"]),
        (10, ["gateway.icloud.com", "googleads.g.doubleclick.net", "youtube.com", "i.ytimg.com"]),
        (11, ["gateway.icloud.com", "instagram.com", "graph.facebook.com", "adjust.com", "whatsapp.net"]),
        (12, ["samsungcloud.com", "googleapis.com", "app-measurement.com", "pagead2.googlesyndication.com", "tiktokv.com"]),
        (15, ["gateway.icloud.com", "github.com", "posteo.de", "sentry.io"]),
        (16, ["teams.microsoft.com", "outlook.office.com", "clarity.ms", "windowsupdate.com"]),
        (18, ["quickconnect.to", "synology.com"]),
        (24, ["a1.tuyaeu.com", "m1.tuyaeu.com"]),
        (25, ["a1.tuyaeu.com"]),
        (27, ["siedle.com"]),
        (28, ["p2p.reolink.com", "reolink.com"]),
        (29, ["hpeprint.com", "hpsmart.com"])
    ]

    public func queries() -> AsyncThrowingStream<DNSQuery, Error> {
        let rate = rate
        return AsyncThrowingStream { continuation in
            let task = Task {
                var generator = SystemRandomNumberGenerator()
                while !Task.isCancelled {
                    let (index, names) = Self.script.randomElement(using: &generator)!
                    let hex = String(index, radix: 16, uppercase: true)
                    let mac = "02:4E:42:00:00:" + (hex.count < 2 ? "0" + hex : hex)
                    continuation.yield(DNSQuery(
                        sourceMAC: mac,
                        sourceIP: "192.168.178.\(19 + index)",
                        name: names.randomElement(using: &generator)!,
                        type: 1,
                        timestamp: Date()
                    ))
                    try? await Task.sleep(for: .seconds(1 / rate))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
