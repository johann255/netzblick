import Foundation
import Observation
import WidgetKit
import NetzblickKit

/// Central app state. Views read from it and call its actions; all logic lives in NetzblickKit.
@MainActor
@Observable
final class AppModel {
    enum Mode: Equatable {
        case onboarding
        case demo
        case live(host: String)
    }

    private(set) var mode: Mode = .onboarding
    private(set) var snapshot: HouseholdSnapshot?
    private(set) var findings: [Finding] = []
    private(set) var newDeviceIDs: Set<String> = []
    private(set) var isLoading = false
    /// Plain-German error for the last failed reading, shown as a banner.
    var errorMessage: String?
    private(set) var lastSpeed: SpeedResult?

    private let keychain = KeychainStore()
    private let defaults = UserDefaults.standard
    private let engine = DiagnosisEngine()
    private let detector = NewDeviceDetector()

    private enum Key {
        static let demoMode = "demoMode"
        static let knownDeviceIDs = "knownDeviceIDs"
        static let lastSpeed = "lastSpeed"
        static let bookedDownloadMbps = "bookedDownloadMbps"
        static let accentBlue = "accentBlue"
    }

    init() {
        if let data = defaults.data(forKey: Key.lastSpeed) {
            lastSpeed = try? JSONDecoder().decode(SpeedResult.self, from: data)
        }
        if let saved = keychain.load() {
            mode = .live(host: saved.host)
        } else if defaults.bool(forKey: Key.demoMode) {
            mode = .demo
        }
    }

    // MARK: Derived values

    var isDemo: Bool { mode == .demo }

    var boxName: String? {
        isDemo ? nil : snapshot?.box.modelName
    }

    /// Tariff entered in the settings, nil if empty.
    var bookedDownloadMbps: Double? {
        let text = defaults.string(forKey: Key.bookedDownloadMbps) ?? ""
        return Double(text.replacingOccurrences(of: ",", with: "."))
    }

    var lastSpeedRating: SpeedRating? {
        lastSpeed.map { SpeedRating.rate(downloadMbps: $0.downloadMbps, bookedMbps: bookedDownloadMbps) }
    }

    func device(id: String) -> Device? {
        snapshot?.devices.first { $0.id == id }
    }

    // MARK: Actions

    func startDemo() {
        defaults.set(true, forKey: Key.demoMode)
        mode = .demo
        Task { await refresh() }
    }

    /// Checks the login against the box, saves it in the keychain and loads the first snapshot.
    func connect(host: String, username: String, password: String) async throws {
        let saved = KeychainStore.Saved(host: host, username: username, password: password)
        let snapshot = try await reader(for: saved).readSnapshot()
        try keychain.save(saved)
        defaults.set(false, forKey: Key.demoMode)
        // Everything on the first reading counts as known, so nothing is flagged as new.
        defaults.set(snapshot.devices.map(\.id), forKey: Key.knownDeviceIDs)
        mode = .live(host: host)
        apply(snapshot, newIDs: [])
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        switch mode {
        case .onboarding:
            return
        case .demo:
            apply(DemoHousehold.snapshot(), newIDs: DemoHousehold.newDeviceIDs)
        case .live:
            guard let saved = keychain.load() else {
                mode = .onboarding
                return
            }
            do {
                let snapshot = try await reader(for: saved).readSnapshot()
                let known = Set(defaults.stringArray(forKey: Key.knownDeviceIDs) ?? [])
                apply(snapshot, newIDs: detector.newDeviceIDs(in: snapshot, known: known))
                errorMessage = nil
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// "Kenne ich": the device is no longer reported as new.
    func acknowledge(deviceID: String) {
        var known = Set(defaults.stringArray(forKey: Key.knownDeviceIDs) ?? [])
        known.insert(deviceID)
        defaults.set(Array(known), forKey: Key.knownDeviceIDs)
        newDeviceIDs.remove(deviceID)
        writeWidgetSummary()
    }

    func liveThroughput() async -> LiveThroughput? {
        switch mode {
        case .demo:
            return LiveThroughput(downstreamMbps: Double.random(in: 4...18), upstreamMbps: Double.random(in: 0.5...3))
        case .live:
            guard let saved = keychain.load() else { return nil }
            return try? await reader(for: saved).readLiveThroughput()
        case .onboarding:
            return nil
        }
    }

    func runSpeedTest(onSample: @escaping @Sendable (SpeedSample) -> Void) async throws -> SpeedResult {
        let result = try await SpeedTester().run(onSample: onSample)
        lastSpeed = result
        defaults.set(try? JSONEncoder().encode(result), forKey: Key.lastSpeed)
        if let snapshot {
            findings = engine.findings(for: snapshot, phoneSpeedMbps: result.downloadMbps)
        }
        writeWidgetSummary()
        return result
    }

    func disconnect() {
        keychain.delete()
        defaults.set(false, forKey: Key.demoMode)
        snapshot = nil
        findings = []
        newDeviceIDs = []
        mode = .onboarding
        writeWidgetSummary()
    }

    /// Removes everything Netzblick stored on this iPhone.
    func deleteAll() {
        disconnect()
        for key in [Key.knownDeviceIDs, Key.lastSpeed, Key.bookedDownloadMbps, Key.accentBlue, "appearance"] {
            defaults.removeObject(forKey: key)
        }
        lastSpeed = nil
        if let url = SharedContainer.summaryURL() {
            try? FileManager.default.removeItem(at: url)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Copies the accent choice into the App Group so the widgets use the same blue.
    func mirrorAccent(_ raw: String) {
        UserDefaults(suiteName: SharedContainer.appGroupID)?.set(raw, forKey: Key.accentBlue)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Private

    private func reader(for saved: KeychainStore.Saved) -> FritzBoxReader {
        let base = URL(string: "http://\(saved.host):49000") ?? TR064Client.defaultBaseURL
        let transport = URLSessionTransport(credentials: saved.credentials)
        return FritzBoxReader(client: TR064Client(baseURL: base, transport: transport))
    }

    private func apply(_ snapshot: HouseholdSnapshot, newIDs: Set<String>) {
        self.snapshot = snapshot
        newDeviceIDs = newIDs
        findings = engine.findings(for: snapshot, phoneSpeedMbps: lastSpeed?.downloadMbps)
        writeWidgetSummary()
    }

    private func writeWidgetSummary() {
        let store = SharedContainer.summaryStore()
        guard let snapshot else {
            if let url = SharedContainer.summaryURL() { try? FileManager.default.removeItem(at: url) }
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        let summary = WidgetSummary(
            updatedAt: snapshot.takenAt,
            boxName: snapshot.box.modelName,
            devicesOnline: snapshot.activeDevices.count,
            newDevices: newDeviceIDs.count,
            findingCount: findings.count,
            topFinding: findings.first?.title,
            lastSpeedMbps: lastSpeed?.downloadMbps,
            lastSpeedLevel: lastSpeedRating?.level,
            lastSpeedAt: lastSpeed?.measuredAt,
            trackingShare: nil,
            isDemo: isDemo
        )
        try? store.save(summary)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
