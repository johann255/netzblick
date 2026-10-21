import Foundation
import NetzblickKit

/// Keeps the presence history in Application Support. Never leaves the iPhone and is not backed up.
struct PresenceStore {
    private var fileURL: URL? {
        guard var dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true) else { return nil }
        dir.appendPathComponent("presence-log.json")
        return dir
    }

    func load() -> PresenceLog {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let log = try? JSONDecoder().decode(PresenceLog.self, from: data) else { return PresenceLog() }
        return log
    }

    func save(_ log: PresenceLog) {
        guard var url = fileURL, let data = try? JSONEncoder().encode(log) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    func delete() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
