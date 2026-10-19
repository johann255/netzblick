import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The M-Lab server a speed test ran against, shown to the user.
public struct SpeedServer: Hashable, Codable, Sendable {
    public var city: String
    /// ISO country code, e.g. "DE".
    public var country: String
    public var machine: String

    public init(city: String, country: String, machine: String) {
        self.city = city
        self.country = country
        self.machine = machine
    }

    /// "Berlin, DE"
    public var label: String { "\(city), \(country)" }
}

/// One live reading during a speed test.
public struct SpeedSample: Hashable, Sendable {
    /// Seconds since the test started.
    public var elapsed: TimeInterval
    /// Throughput over the last window in Mbit/s.
    public var currentMbps: Double
    /// Share of the planned test duration that has passed (0–1).
    public var progress: Double
    /// The server being measured against.
    public var server: SpeedServer?
}

/// Final result of a speed test.
public struct SpeedResult: Hashable, Codable, Sendable {
    public var downloadMbps: Double
    public var measuredAt: Date
    public var bytes: Int64
    public var duration: TimeInterval
    /// Nil for results stored before the switch to M-Lab.
    public var server: SpeedServer?

    public init(downloadMbps: Double, measuredAt: Date, bytes: Int64, duration: TimeInterval, server: SpeedServer? = nil) {
        self.downloadMbps = downloadMbps
        self.measuredAt = measuredAt
        self.bytes = bytes
        self.duration = duration
        self.server = server
    }
}

/// M-Lab's Locate API: which nearby ndt7 servers to measure against.
///
/// The request carries no client name, version or device data; M-Lab sees only the IP address.
public enum MLabLocate {
    public static let url = URL(string: "https://locate.measurementlab.net/v2/nearest/ndt/ndt7")!

    public struct Target: Hashable, Sendable {
        public var server: SpeedServer
        /// Signed `wss://` URL for the download test; valid for a short time only.
        public var downloadURL: URL
    }

    /// Parses the Locate response, nearest server first. Entries without a secure download URL are skipped.
    public static func targets(from data: Data) throws -> [Target] {
        struct Response: Decodable {
            struct Result: Decodable {
                struct Location: Decodable {
                    var city: String?
                    var country: String?
                }
                var machine: String
                var location: Location?
                var urls: [String: String]
            }
            var results: [Result]?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return (response.results ?? []).compactMap { result in
            guard let raw = result.urls["wss:///ndt/v7/download"], let url = URL(string: raw) else { return nil }
            let server = SpeedServer(
                city: result.location?.city ?? "unbekannt",
                country: result.location?.country ?? "–",
                machine: result.machine
            )
            return Target(server: server, downloadURL: url)
        }
    }
}

/// Pure arithmetic of a download speed test, separated from networking so it is testable.
public struct ThroughputMeter: Sendable {
    /// Readings during the first part are ignored for the result (TCP slow start).
    public var warmUp: TimeInterval
    public var window: TimeInterval
    private(set) var points: [(t: TimeInterval, bytes: Int64)] = []

    public init(warmUp: TimeInterval = 1.5, window: TimeInterval = 0.5) {
        self.warmUp = warmUp
        self.window = window
    }

    /// Records the cumulative byte count at time `t` and returns the current rate in Mbit/s.
    public mutating func record(t: TimeInterval, totalBytes: Int64) -> Double {
        points.append((t, totalBytes))
        guard let start = points.last(where: { $0.t <= t - window }) ?? points.first, t > start.t else { return 0 }
        return Self.mbps(bytes: totalBytes - start.bytes, seconds: t - start.t)
    }

    /// Average rate after the warm-up phase, in Mbit/s.
    public var resultMbps: Double {
        guard let last = points.last else { return 0 }
        let base = points.first(where: { $0.t >= warmUp }) ?? points.first!
        guard last.t > base.t else {
            return Self.mbps(bytes: last.bytes, seconds: max(last.t, 0.001))
        }
        return Self.mbps(bytes: last.bytes - base.bytes, seconds: last.t - base.t)
    }

    public static func mbps(bytes: Int64, seconds: TimeInterval) -> Double {
        guard seconds > 0 else { return 0 }
        return Double(bytes) * 8 / seconds / 1_000_000
    }
}

#if canImport(Darwin)
/// ndt7 download test against M-Lab (https://www.measurementlab.net), reporting live throughput.
///
/// Privacy: M-Lab publishes every measurement, including this iPhone's public IP address, as open data.
/// Netzblick sends nothing else: no client name, no app version, a neutral User-Agent.
/// The result is stored only on the device.
public final class SpeedTester: @unchecked Sendable {
    /// ndt7 servers end the download after about 10 s; the client gives up at 15 s.
    public var duration: TimeInterval
    public var timeout: TimeInterval

    static let subprotocol = "net.measurementlab.ndt.v7"
    /// ndt7 messages can be up to 16 MiB; URLSession's default limit is 1 MiB.
    static let maxMessageSize = 1 << 24

    public init(duration: TimeInterval = 10, timeout: TimeInterval = 15) {
        self.duration = duration
        self.timeout = timeout
    }

    /// Runs the test. Calls `onSample` about every 0.25 s on an arbitrary thread.
    public func run(onSample: @escaping @Sendable (SpeedSample) -> Void) async throws -> SpeedResult {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 10
        config.httpCookieAcceptPolicy = .never
        config.httpAdditionalHeaders = ["User-Agent": "ndt7"]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(from: MLabLocate.url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let targets = try MLabLocate.targets(from: data)

        // Try the nearest server first; fall back to the next one only if nothing arrived.
        var lastError: Error = URLError(.cannotFindHost)
        for target in targets.prefix(3) {
            do {
                return try await download(from: target, session: session, onSample: onSample)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func download(
        from target: MLabLocate.Target,
        session: URLSession,
        onSample: @escaping @Sendable (SpeedSample) -> Void
    ) async throws -> SpeedResult {
        var request = URLRequest(url: target.downloadURL)
        request.setValue(Self.subprotocol, forHTTPHeaderField: "Sec-WebSocket-Protocol")
        request.setValue("ndt7", forHTTPHeaderField: "User-Agent")
        let socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = Self.maxMessageSize
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        var meter = ThroughputMeter()
        let start = Date()
        var total: Int64 = 0
        var lastReport: TimeInterval = 0

        while true {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await socket.receive()
            } catch {
                // The server closes the connection when its time is up; that is the normal end.
                if total > 0 { break }
                throw error
            }
            switch message {
            case .data(let data): total += Int64(data.count)
            case .string(let text): total += Int64(text.utf8.count)
            @unknown default: break
            }
            let t = Date().timeIntervalSince(start)
            if t - lastReport >= 0.25 {
                let current = meter.record(t: t, totalBytes: total)
                onSample(SpeedSample(elapsed: t, currentMbps: current, progress: min(t / duration, 1), server: target.server))
                lastReport = t
            }
            if t >= timeout || Task.isCancelled { break }
        }
        try Task.checkCancellation()
        let elapsed = Date().timeIntervalSince(start)
        _ = meter.record(t: elapsed, totalBytes: total)
        return SpeedResult(
            downloadMbps: meter.resultMbps,
            measuredAt: Date(),
            bytes: total,
            duration: elapsed,
            server: target.server
        )
    }
}
#endif
