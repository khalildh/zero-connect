import CryptoKit
import Foundation

/// Manages the device's cryptographic identity.
/// Generates a P-256 keypair on first launch and persists it in the Keychain.
public actor IdentityManager {
    private static let keychainService = "com.zeroconnect.identity"
    private static let keychainAccount = "device-signing-key"

    private var cachedKey: P256.KeyAgreement.PrivateKey?

    public init() {}

    /// Returns the device's private key, creating one if it doesn't exist.
    public func privateKey() throws -> P256.KeyAgreement.PrivateKey {
        if let cached = cachedKey {
            return cached
        }

        if let existing = try loadFromKeychain() {
            cachedKey = existing
            return existing
        }

        let newKey = P256.KeyAgreement.PrivateKey()
        try saveToKeychain(newKey)
        cachedKey = newKey
        return newKey
    }

    /// Returns the device's public key as raw bytes (x963 uncompressed format).
    public func publicKeyData() throws -> Data {
        let key = try privateKey()
        return key.publicKey.x963Representation
    }

    /// Returns the public key as a hex string for display / QR codes.
    public func publicKeyHex() throws -> String {
        let data = try publicKeyData()
        return data.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Keychain

    private func loadFromKeychain() throws -> P256.KeyAgreement.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound {
                return nil
            }
            throw IdentityError.keychainError(status)
        }

        return try P256.KeyAgreement.PrivateKey(rawRepresentation: data)
    }

    private func saveToKeychain(_ key: P256.KeyAgreement.PrivateKey) throws {
        let data = key.rawRepresentation

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        var status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // Key already exists — update it
            let searchQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Self.keychainService,
                kSecAttrAccount as String: Self.keychainAccount,
            ]
            let updateAttributes: [String: Any] = [
                kSecValueData as String: data,
            ]
            status = SecItemUpdate(searchQuery as CFDictionary, updateAttributes as CFDictionary)
        }

        guard status == errSecSuccess else {
            throw IdentityError.keychainError(status)
        }
    }

    /// Deletes the identity key (for testing / reset).
    public func deleteIdentity() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw IdentityError.keychainError(status)
        }
        cachedKey = nil
    }
}

public enum IdentityError: Error, Sendable {
    case keychainError(OSStatus)
}
