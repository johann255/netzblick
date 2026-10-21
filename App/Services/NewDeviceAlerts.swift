import Foundation
import BackgroundTasks
import UserNotifications
import NetzblickKit

/// Fing's "new device" alarm without a server: a background refresh asks the FRITZ!Box,
/// and a local notification names devices nobody has acknowledged yet.
/// iOS decides how often the refresh runs, so this is a watchdog, not a real-time alarm.
enum NewDeviceAlerts {
    static let taskIdentifier = "com.johann255.netzblick.refresh"
    static let enabledKey = "notifyNewDevices"
    private static let announcedKey = "announcedDeviceIDs"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Asks for permission; returns false if the person declines.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Asks iOS to wake the app in about half an hour. Harmless to call repeatedly.
    static func schedule() {
        guard isEnabled else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Posts one notification for devices that are new and were not announced before.
    static func announce(_ devices: [Device]) async {
        guard isEnabled else { return }
        let defaults = UserDefaults.standard
        var announced = Set(defaults.stringArray(forKey: announcedKey) ?? [])
        let fresh = devices.filter { !announced.contains($0.id) }
        guard !fresh.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = fresh.count == 1 ? "Neues Gerät im Heimnetz" : "\(fresh.count) neue Geräte im Heimnetz"
        content.body = fresh.prefix(3).map(\.name).joined(separator: ", ")
            + (fresh.count > 3 ? " und weitere" : "")
            + ". Kennst du \(fresh.count == 1 ? "es" : "sie")?"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "new-devices-\(UUID().uuidString)", content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            announced.formUnion(fresh.map(\.id))
            defaults.set(Array(announced), forKey: announcedKey)
        } catch {
            // Not delivered: try again on the next refresh.
        }
    }

    /// Forgets which devices were announced, e.g. after "Alles löschen".
    static func reset() {
        UserDefaults.standard.removeObject(forKey: announcedKey)
        UserDefaults.standard.removeObject(forKey: enabledKey)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }
}
