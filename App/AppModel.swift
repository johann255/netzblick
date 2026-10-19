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
    /// Who was online when; only devices of the home network, kept 30 days on this iPhone.
    private(set) var presenceLog = PresenceLog()

    /// Last finished listening session; only counts, never packets.
    private(set) var listenReport: ListenReport?
    private(set) var isListening = false
    /// Questions heard so far in the running session.
    private(set) var listenHeard = 0
    private(set) var listenEndsAt: Date?
    /// Plain-German reason the last session failed.
    var listenError: String?
    private var listenTask: Task<Void, Never>?
    private var listenTimer: Task<Void, Never>?

    private let keychain = KeychainStore()
    private let defaults = UserDefaults.standard
    private let engine = DiagnosisEngine()
    private let detector = NewDeviceDetector()
    private let presenceStore = PresenceStore()

    private enum Key {
        static let demoMode = "demoMode"
        static let knownDeviceIDs = "knownDeviceIDs"
        static let lastSpeed = "lastSpeed"
        static let listenReport = "listenReport"
        static let bookedDownloadMbps = "bookedDownloadMbps"
        static let accentBlue = "accentBlue"
    }

    init() {
        if let data = defaults.data(forKey: Key.lastSpeed) {
            lastSpeed = try? JSONDecoder().decode(SpeedResult.self, from: data)
        }
        if let data = defaults.data(forKey: Key.listenReport) {
            listenReport = try? JSONDecoder().decode(ListenReport.self, from: data)
        }
        if let saved = keychain.load() {
            mode = .live(host: saved.host)
            presenceLog = presenceStore.load()
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

    /// Name for a device id from a listening report, also for devices the box does not list.
    func deviceName(id: String) -> String {
        if let device = device(id: id) { return device.name }
        if id.hasPrefix("ip:") { return "Unbekanntes Gerät (\(id.dropFirst(3)))" }
        return "Unbekanntes Gerät"
    }

    /// Security checklist for the current reading; empty while nothing is loaded.
    var securityChecks: [SecurityCheckItem] {
        guard let snapshot, snapshot.security != nil else { return [] }
        return SecurityCheck.items(for: snapshot, newDeviceCount: newDeviceIDs.count)
    }

    var securityFindings: [Finding] { findings.filter(\.kind.isSecurity) }

    /// Findings about slow Wi-Fi, for the diagnosis tab.
    var speedFindings: [Finding] { findings.filter { !$0.kind.isSecurity } }

    var canCheckSecurity: Bool {
        currentRouter()?.capabilities.contains(.securityCheck) ?? false
    }

    var canListen: Bool {
        currentRouter()?.capabilities.contains(.dnsListening) ?? false
    }

    // MARK: Listening

    /// Listens for `duration` seconds or until `stopListening()`. Runs only while the app is open.
    func startListening(duration: TimeInterval = 300) {
        guard !isListening, let listener = currentListener() else { return }
        let start = Date()
        isListening = true
        listenHeard = 0
        listenError = nil
        listenEndsAt = start.addingTimeInterval(duration)

        listenTask = Task { [weak self] in
            // Without a device list every question would show up as "Unbekanntes Gerät".
            if self?.snapshot == nil { await self?.refresh() }
            let devices = self?.snapshot?.devices ?? []
            var recorder = ListenRecorder(devices: devices, startedAt: start)
            var failure: Error?
            do {
                for try await query in listener.queries() {
                    if recorder.record(query) { self?.listenHeard = recorder.heardCount }
                }
            } catch {
                failure = error
            }
            self?.finishListening(recorder, error: failure)
        }
        listenTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.stopListening()
        }
    }

    func stopListening() {
        listenTimer?.cancel()
        listenTask?.cancel()
    }

    private func finishListening(_ recorder: ListenRecorder, error: Error?) {
        listenTimer?.cancel()
        listenTask = nil
        listenTimer = nil
        isListening = false
        listenEndsAt = nil
        if let error {
            listenError = (error as? LocalizedError)?.errorDescription ?? "Das Lauschen ist abgebrochen."
        }
        guard recorder.heardCount > 0 else {
            if error == nil { listenError = "In dieser Zeit hat kein Gerät etwas angefragt." }
            return
        }
        let report = recorder.report()
        listenReport = report
        defaults.set(try? JSONEncoder().encode(report), forKey: Key.listenReport)
        writeWidgetSummary()
    }

    // MARK: Actions

    func startDemo() {
        defaults.set(true, forKey: Key.demoMode)
        mode = .demo
        Task { await refresh() }
    }

    /// Checks the login against the box, saves it in the keychain and loads the first snapshot.
    /// An empty `username` means the person never set one; the box's automatic name is looked up.
    func connect(host: String, username: String, password: String) async throws {
        var username = username.trimmingCharacters(in: .whitespaces)
        if username.isEmpty {
            username = try await automaticUsername(host: host)
        }
        let saved = KeychainStore.Saved(host: host, username: username, password: password)
        let snapshot = try await router(for: saved).readSnapshot()
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
            guard let snapshot = try? await DemoRouter().readSnapshot() else { return }
            apply(snapshot, newIDs: DemoHousehold.newDeviceIDs)
        case .live:
            guard let saved = keychain.load() else {
                mode = .onboarding
                return
            }
            do {
                let snapshot = try await router(for: saved).readSnapshot()
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

    /// Runs when iOS wakes the app in the background: read the box, announce new devices, plan the next run.
    func backgroundRefresh() async {
        defer { NewDeviceAlerts.schedule() }
        guard case .live = mode else { return }
        await refresh()
        let fresh = newDeviceIDs.compactMap { device(id: $0) }
        await NewDeviceAlerts.announce(fresh)
    }

    func liveThroughput() async -> LiveThroughput? {
        guard let router = currentRouter(), router.capabilities.contains(.liveThroughput) else { return nil }
        return try? await router.readLiveThroughput()
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
        stopListening()
        keychain.delete()
        defaults.set(false, forKey: Key.demoMode)
        snapshot = nil
        findings = []
        newDeviceIDs = []
        // A report and a history belong to the network they were taken in.
        presenceLog = PresenceLog()
        presenceStore.delete()
        listenReport = nil
        defaults.removeObject(forKey: Key.listenReport)
        mode = .onboarding
        writeWidgetSummary()
    }

    /// Removes everything Netzblick stored on this iPhone.
    func deleteAll() {
        disconnect()
        for key in [Key.knownDeviceIDs, Key.lastSpeed, Key.listenReport, Key.bookedDownloadMbps, Key.accentBlue, "appearance"] {
            defaults.removeObject(forKey: key)
        }
        lastSpeed = nil
        listenReport = nil
        NewDeviceAlerts.reset()
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

    /// The router behind the current mode, nil during onboarding.
    private func currentRouter() -> (any RouterAdapter)? {
        switch mode {
        case .onboarding:
            return nil
        case .demo:
            return DemoRouter()
        case .live:
            return keychain.load().map(router(for:))
        }
    }

    /// Where DNS questions come from in the current mode.
    private func currentListener() -> (any DNSListener)? {
        switch mode {
        case .onboarding:
            return nil
        case .demo:
            return DemoDNSListener()
        case .live:
            guard let saved = keychain.load() else { return nil }
            return FritzDNSListener(host: saved.host, credentials: saved.credentials)
        }
    }

    /// The name FRITZ!OS created when nobody set one (e.g. "fritz2690"); readable without login.
    private func automaticUsername(host: String) async throws -> String {
        let client = TR064Client(baseURL: baseURL(host: host), transport: URLSessionTransport(credentials: nil))
        guard let name = try await client.loadUsers(try await client.loadCatalog()).suggested else {
            throw ConnectError.noUsername
        }
        return name
    }

    private func baseURL(host: String) -> URL {
        URL(string: "http://\(host):49000") ?? TR064Client.defaultBaseURL
    }

    private func router(for saved: KeychainStore.Saved) -> any RouterAdapter {
        let base = baseURL(host: saved.host)
        let transport = URLSessionTransport(credentials: saved.credentials)
        return FritzBoxReader(client: TR064Client(baseURL: base, transport: transport))
    }

    private func apply(_ snapshot: HouseholdSnapshot, newIDs: Set<String>) {
        self.snapshot = snapshot
        newDeviceIDs = newIDs
        findings = engine.findings(for: snapshot, phoneSpeedMbps: lastSpeed?.downloadMbps)
        if isDemo {
            presenceLog = DemoHousehold.presenceLog(now: snapshot.takenAt)
        } else {
            presenceLog.record(snapshot)
            presenceStore.save(presenceLog)
        }
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
            trackingShare: listenReport.flatMap { $0.total > 0 ? $0.share(.tracking) : nil },
            isDemo: isDemo
        )
        try? store.save(summary)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

private enum ConnectError: LocalizedError {
    case noUsername

    var errorDescription: String? {
        "Die Box hat keinen Benutzernamen genannt. Trag ihn bitte von Hand ein (FRITZ!Box → System → FRITZ!Box-Benutzer)."
    }
}
