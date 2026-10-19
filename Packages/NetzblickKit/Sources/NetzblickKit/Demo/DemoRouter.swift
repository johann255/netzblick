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
}
