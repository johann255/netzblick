import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One live reading during a speed test.
public struct SpeedSample: Hashable, Sendable {
    /// Seconds since the test started.
    public var elapsed: TimeInterval
    /// Throughput over the last window in Mbit/s.
    public var currentMbps: Double
    /// Share of the planned test duration that has passed (0–1).
    public var progress: Double
}

/// Final result of a speed test.
public struct SpeedResult: Hashable, Codable, Sendable {
    public var downloadMbps: Double
    public var measuredAt: Date
    public var bytes: Int64
    public var duration: TimeInterval

    public init(downloadMbps: Double, measuredAt: Date, bytes: Int64, duration: TimeInterval) {
        self.downloadMbps = downloadMbps
        self.measuredAt = measuredAt
        self.bytes = bytes
        self.duration = duration
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
/// Downloads test data for a few seconds over several parallel connections and reports live throughput.
///
/// Privacy: the test server sees this iPhone's public IP address, like any website.
/// Netzblick sends nothing else and stores the result only on the device.
public final class SpeedTester: @unchecked Sendable {
    /// Endpoint that streams random data; one request per connection, restarted when it ends early.
    /// Cloudflare answers 403 from 100 MB per request, so a single request caps the result near 100 Mbit/s.
    /// DECIDE before release: run on an own endpoint or confirm terms of use of a public one.
    public var endpoint: URL
    public var duration: TimeInterval
    public var maxBytes: Int64
    /// Parallel connections; one TCP stream rarely fills a fast line.
    public var connections: Int

    public init(
        endpoint: URL = URL(string: "https://speed.cloudflare.com/__down?bytes=50000000")!,
        duration: TimeInterval = 8,
        maxBytes: Int64 = 1_000_000_000,
        connections: Int = 4
    ) {
        self.endpoint = endpoint
        self.duration = duration
        self.maxBytes = maxBytes
        self.connections = connections
    }

    /// Runs the test. Calls `onSample` about every 0.25 s on an arbitrary thread.
    public func run(onSample: @escaping @Sendable (SpeedSample) -> Void) async throws -> SpeedResult {
        // Chunks arrive through a delegate: iterating AsyncBytes byte by byte is too slow above ~100 Mbit/s.
        let (events, continuation) = AsyncThrowingStream<ChunkCounter.Event, Error>.makeStream()
        let delegate = ChunkCounter(continuation: continuation)
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 10
        config.httpMaximumConnectionsPerHost = connections
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        for _ in 0..<max(connections, 1) {
            session.dataTask(with: endpoint).resume()
        }

        var meter = ThroughputMeter()
        let start = Date()
        var total: Int64 = 0
        var lastReport: TimeInterval = 0

        for try await event in events {
            let t = Date().timeIntervalSince(start)
            switch event {
            case .bytes(let count):
                total += Int64(count)
            case .requestFinished:
                // A connection ran out of data before the time was up: start the next request.
                if t < duration { session.dataTask(with: endpoint).resume() }
            }
            if t - lastReport >= 0.25 {
                let current = meter.record(t: t, totalBytes: total)
                onSample(SpeedSample(elapsed: t, currentMbps: current, progress: min(t / duration, 1)))
                lastReport = t
            }
            if t >= duration || total >= maxBytes || Task.isCancelled { break }
        }
        try Task.checkCancellation()
        let elapsed = Date().timeIntervalSince(start)
        _ = meter.record(t: elapsed, totalBytes: total)
        guard total > 0 else { throw URLError(.badServerResponse) }
        return SpeedResult(downloadMbps: meter.resultMbps, measuredAt: Date(), bytes: total, duration: elapsed)
    }
}

private final class ChunkCounter: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Event: Sendable {
        case bytes(Int)
        case requestFinished
    }

    let continuation: AsyncThrowingStream<Event, Error>.Continuation

    init(continuation: AsyncThrowingStream<Event, Error>.Continuation) {
        self.continuation = continuation
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if (response as? HTTPURLResponse)?.statusCode == 200 {
            completionHandler(.allow)
        } else {
            continuation.finish(throwing: URLError(.badServerResponse))
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        continuation.yield(.bytes(data.count))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            if (error as? URLError)?.code != .cancelled { continuation.finish(throwing: error) }
        } else {
            continuation.yield(.requestFinished)
        }
    }
}
#endif
