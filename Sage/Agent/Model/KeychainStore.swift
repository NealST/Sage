//
//  KeychainStore.swift
//  Sage
//

import Foundation
import Security

/// Generic-password helpers for the file-based macOS keychain.
///
/// Sage is not App Sandboxed (`ENABLE_APP_SANDBOX = NO`). The data-protection
/// keychain (`kSecUseDataProtectionKeychain`) is unavailable in that configuration
/// and returns `errSecNotAvailable`, so we use the traditional keychain instead.
enum KeychainStore {
    private static let service = "mozheng.Sage"

    static func set(_ value: String, account: String) throws {
        let data = Data(value.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            // Drop any leftover data-protection copy from earlier builds.
            deleteDataProtectionItem(account: account)
            return
        case errSecItemNotFound:
            break
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
        deleteDataProtectionItem(account: account)
    }

    static func get(account: String) -> String? {
        if let value = copyMatching(account: account, dataProtection: false) {
            return value
        }
        // Older builds may still have a data-protection item; migrate on read.
        guard let value = copyMatching(account: account, dataProtection: true) else {
            return nil
        }
        try? set(value, account: account)
        return value
    }

    static func delete(account: String) {
        let legacy: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(legacy as CFDictionary)
        deleteDataProtectionItem(account: account)
    }

    // MARK: - Private

    private static func deleteDataProtectionItem(account: String) {
        let modern: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(modern as CFDictionary)
    }

    private static func copyMatching(account: String, dataProtection: Bool) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return value
    }

    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let message = SecCopyErrorMessageString(status, nil) as String?
                    ?? "status \(status)"
                return "Keychain error: \(message)"
            }
        }
    }
}
