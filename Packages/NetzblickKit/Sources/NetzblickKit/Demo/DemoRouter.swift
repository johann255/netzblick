import Foundation

/// Router adapter for the demo mode. Serves `DemoHousehold` and never touches the network.
public struct DemoRouter: RouterAdapter {
    public let kind = RouterKind.demo
    public let capabilities = RouterCapabilities.all

    public init() {}

    public func readSnapshot(now: Date) async throws -> HouseholdSnapshot {
        DemoHousehold.snapshot(now: now)
    }

    public func readLiveThroughput() async throws -> LiveThroughput {
        LiveThroughput(downstreamMbps: Double.random(in: 4...18), upstreamMbps: Double.random(in: 0.5...3))
    }

    public func wakeUp(macAddress: String) async throws {
        try await Task.sleep(for: .milliseconds(400))
    }

    /// Wanders around a mid-strength signal so the walk screen has something to show.
    public func readWiFiLink(ip: String) async throws -> WiFiLink? {
        WiFiLink(band: .ghz5, signalPercent: Int.random(in: 35...85), rateMbps: Int.random(in: 200...860))
    }
}
