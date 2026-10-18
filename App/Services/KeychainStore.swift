import Foundation
import Security
import NetzblickKit

/// Stores the FRITZ!Box login in the iOS keychain (this device only, never synced).
struct KeychainStore {
    private let service = "com.johann255.netzblick.box"

    struct Saved: Codable, Equatable {
        var host: String
        var username: String
        var password: String

        var credentials: BoxCredentials { BoxCredentials(username: username, password: password) }
    }

    func save(_ saved: Saved) throws {
        let data = try JSONEncoder().encode(saved)
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "default",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func load() -> Saved? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "default",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: data)
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "default"
        ]
        SecItemDelete(query as CFDictionary)
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Die Zugangsdaten konnten nicht sicher gespeichert werden (\(status))." }
    }
}
