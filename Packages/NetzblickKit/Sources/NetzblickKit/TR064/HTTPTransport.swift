import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal HTTP request, independent of URLSession so the client can be tested with fixtures.
public struct HTTPRequest: Hashable, Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: String = "GET", url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Hashable, Sendable {
    public var statusCode: Int
    public var body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

/// Sends HTTP requests. Implementations handle authentication (HTTP Digest for TR-064).
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// Credentials of a FRITZ!Box user. Kept only in the iOS keychain by the app.
public struct BoxCredentials: Hashable, Sendable {
    public var username: String
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

#if canImport(Darwin)
/// URLSession-based transport. URLSession answers the FRITZ!Box's HTTP Digest challenge
/// with the given credentials, so no digest code of our own is needed.
public final class URLSessionTransport: NSObject, HTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private let credentials: BoxCredentials?
    private let timeout: TimeInterval
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.waitsForConnectivity = false
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    public init(credentials: BoxCredentials?, timeout: TimeInterval = 8) {
        self.credentials = credentials
        self.timeout = timeout
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return HTTPResponse(statusCode: status, body: data)
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let method = challenge.protectionSpace.authenticationMethod
        guard method == NSURLAuthenticationMethodHTTPDigest || method == NSURLAuthenticationMethodHTTPBasic,
              let credentials, challenge.previousFailureCount == 0 else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let credential = URLCredential(user: credentials.username, password: credentials.password, persistence: .forSession)
        completionHandler(.useCredential, credential)
    }
}
#endif
