import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Low-level TR-064 client: reads the service description and calls SOAP actions.
public struct TR064Client: Sendable {
    /// e.g. http://fritz.box:49000 or http://192.168.178.1:49000
    public let baseURL: URL
    private let transport: HTTPTransport

    public static let defaultBaseURL = URL(string: "http://fritz.box:49000")!

    public init(baseURL: URL = TR064Client.defaultBaseURL, transport: HTTPTransport) {
        self.baseURL = baseURL
        self.transport = transport
    }

    /// Loads `tr64desc.xml`. Does not need a login.
    public func loadCatalog() async throws -> ServiceCatalog {
        let response = try await perform(HTTPRequest(url: baseURL.appendingPathComponent("tr64desc.xml")))
        switch response.statusCode {
        case 200: return try ServiceCatalog.parse(response.body)
        // VERIFY: a box with "Zugriff für Anwendungen" switched off does not answer on 49000 at all
        // (connection refused → .unreachable) or answers 404 depending on FRITZ!OS version.
        case 404: throw TR064Error.accessDisabled
        default: throw TR064Error.httpStatus(response.statusCode)
        }
    }

    /// Calls a SOAP action and returns its output arguments.
    public func call(_ service: TR064Service, action: String, arguments: [(String, String)] = []) async throws -> [String: String] {
        let url = resolve(service.controlURL)
        let request = HTTPRequest(
            method: "POST",
            url: url,
            headers: [
                "Content-Type": "text/xml; charset=\"utf-8\"",
                "SOAPACTION": SOAPEnvelope.soapActionHeader(serviceType: service.serviceType, action: action)
            ],
            body: SOAPEnvelope.body(serviceType: service.serviceType, action: action, arguments: arguments)
        )
        let response = try await perform(request)
        switch response.statusCode {
        case 200:
            return try SOAPResponseParser.parse(response.body, action: action)
        case 401:
            throw TR064Error.unauthorized
        case 500:
            // SOAP faults arrive as HTTP 500 with a UPnPError body.
            do {
                _ = try SOAPResponseParser.parse(response.body, action: action)
                throw TR064Error.httpStatus(500)
            } catch let TR064Error.soapFault(code, description) {
                // 606 = Action Not Authorized: the user lacks the needed right.
                if code == 606 { throw TR064Error.unauthorized }
                throw TR064Error.soapFault(code: code, description: description)
            }
        default:
            throw TR064Error.httpStatus(response.statusCode)
        }
    }

    /// Calls an action on a service looked up by short name, throwing `.serviceMissing` if absent.
    public func call(_ catalog: ServiceCatalog, _ shortName: String, instance: Int = 1, action: String,
                     arguments: [(String, String)] = []) async throws -> [String: String] {
        guard let service = catalog.service(shortName, instance: instance) else {
            throw TR064Error.serviceMissing("\(shortName):\(instance)")
        }
        return try await call(service, action: action, arguments: arguments)
    }

    /// Downloads a list the box handed out by path (host list, WLAN device list).
    public func fetchList(path: String) async throws -> [[String: String]] {
        let response = try await perform(HTTPRequest(url: resolve(path)))
        guard response.statusCode == 200 else { throw TR064Error.httpStatus(response.statusCode) }
        return try ItemListParser.parse(response.body)
    }

    /// Turns a path or absolute URL from the box into a URL on `baseURL`.
    func resolve(_ pathOrURL: String) -> URL {
        if let absolute = URL(string: pathOrURL), absolute.scheme != nil {
            return absolute
        }
        let path = pathOrURL.hasPrefix("/") ? pathOrURL : "/" + pathOrURL
        return URL(string: path, relativeTo: baseURL)?.absoluteURL ?? baseURL
    }

    private func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        do {
            return try await transport.send(request)
        } catch let error as TR064Error {
            throw error
        } catch is URLError {
            throw TR064Error.unreachable
        }
    }
}
