import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Result of pinging one device a few times.
public struct PingResult: Hashable, Sendable {
    public var sent: Int
    public var received: Int
    /// Average round trip in milliseconds over the answered pings.
    public var averageMs: Double?

    public init(sent: Int, received: Int, averageMs: Double?) {
        self.sent = sent
        self.received = received
        self.averageMs = averageMs
    }

    public var isReachable: Bool { received > 0 }

    /// Plain German, e.g. "antwortet in 4 ms" or "antwortet nicht".
    public var summary: String {
        guard let averageMs, received > 0 else { return "antwortet nicht" }
        let ms = averageMs < 1 ? "unter 1" : String(Int(averageMs.rounded()))
        let loss = received < sent ? " (\(sent - received) von \(sent) verloren)" : ""
        return "antwortet in \(ms) ms" + loss
    }
}

/// Ping over a datagram ICMP socket, which Apple platforms allow without special rights.
/// Only for devices in the home network; the address comes from the router's host list.
public struct Pinger: Sendable {
    public var timeout: TimeInterval
    public var count: Int

    public init(timeout: TimeInterval = 1, count: Int = 3) {
        self.timeout = timeout
        self.count = count
    }

    public func ping(_ ipv4: String) async -> PingResult {
        let timeout = self.timeout
        let count = self.count
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var times: [Double] = []
                let identifier = UInt16.random(in: 1...UInt16.max)
                for sequence in 0..<count {
                    if let ms = Self.echo(ipv4, identifier: identifier, sequence: UInt16(sequence), timeout: timeout) {
                        times.append(ms)
                    }
                }
                let average = times.isEmpty ? nil : times.reduce(0, +) / Double(times.count)
                continuation.resume(returning: PingResult(sent: count, received: times.count, averageMs: average))
            }
        }
    }

    /// One echo round trip in milliseconds, nil on timeout or error. Blocking.
    static func echo(_ ipv4: String, identifier: UInt16, sequence: UInt16, timeout: TimeInterval) -> Double? {
        #if canImport(Darwin)
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, ipv4, &address.sin_addr) == 1 else { return nil }

        let packet = ICMPEcho.request(identifier: identifier, sequence: sequence)
        let start = Date()
        let sent = packet.withUnsafeBytes { buffer in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, buffer.baseAddress, buffer.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == packet.count else { return nil }

        var buffer = [UInt8](repeating: 0, count: 1500)
        while true {
            let remaining = timeout - Date().timeIntervalSince(start)
            guard remaining > 0 else { return nil }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, Int32(remaining * 1000)) > 0 else { return nil }
            let length = recv(fd, &buffer, buffer.count, 0)
            guard length > 0 else { return nil }
            // Other pings on the same host may land here too; only our sequence counts.
            if ICMPEcho.replySequence(Array(buffer[0..<length])) == sequence {
                return Date().timeIntervalSince(start) * 1000
            }
        }
        #else
        return nil
        #endif
    }
}
