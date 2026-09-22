import Foundation
import Security
import Supabase

/// A minimal generic-password Keychain wrapper.
///
/// Replaces the React Native app's `AsyncStorage` session storage
/// (`src/services/supabase.ts` passes `storage: AsyncStorage`). The RN app keeps
/// the auth session in unencrypted key-value storage; on macOS the session is a
/// bearer credential, so it belongs in the Keychain
/// (MACOS_ARCHITECTURE.md §2 "Security").
struct KeychainStore: Sendable {
    /// Distinguishes this app's items from other apps' items in a shared Keychain.
    let service: String

    /// The Keychain's own error, wrapped so callers can distinguish "absent"
    /// from "failed". Absent is `nil`, never an error — the auth layer treats it
    /// as "signed out", exactly like `AsyncStorage.getItem` returning null.
    struct Failure: LocalizedError, Equatable {
        let status: OSStatus

        var errorDescription: String? {
            let message = SecCopyErrorMessageString(status, nil) as String?
            return "Keychain error \(status)" + (message.map { ": \($0)" } ?? "")
        }
    }

    func data(for key: String) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw Failure(status: status)
        }
    }

    func set(_ data: Data, for key: String) throws {
        let query = baseQuery(for: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // The app may need the session on launch and while refreshing in the
            // background, but not before the user has unlocked the Mac once.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insertion = query
            insertion.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(insertion as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw Failure(status: addStatus) }
            return
        }
        guard updateStatus == errSecSuccess else { throw Failure(status: updateStatus) }
    }

    func remove(_ key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        // Deleting a key that was never written is the desired end state.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure(status: status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}

/// Bridges the Keychain to supabase-swift, so the SDK persists and refreshes the
/// session without the app hand-rolling token storage.
struct KeychainAuthStorage: AuthLocalStorage {
    /// The RN app's `storageKey` is the SDK default (`sb-<ref>-auth-token`);
    /// passing no override keeps the same layout on disk.
    static let defaultService = "com.jayanth.jmoney.auth"

    private let keychain: KeychainStore

    init(service: String = defaultService) {
        self.keychain = KeychainStore(service: service)
    }

    func store(key: String, value: Data) throws {
        try keychain.set(value, for: key)
    }

    func retrieve(key: String) throws -> Data? {
        try keychain.data(for: key)
    }

    func remove(key: String) throws {
        try keychain.remove(key)
    }
}
