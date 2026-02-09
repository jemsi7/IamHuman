// Core/Crypto/KeyStore.swift

import Foundation
import CryptoKit
import Security

// MARK: - Key Store Protocol

protocol KeyStoreProtocol {
    func generateKeyPair() async throws -> KeyPairInfo
    func sign(data: Data, keyId: String) async throws -> Data
    func getPublicKey(keyId: String) async throws -> Data
    func deleteKey(keyId: String) async throws
    var isSecureEnclaveAvailable: Bool { get }
}

// MARK: - Key Pair Info

struct KeyPairInfo: Codable {
    let keyId: String
    let publicKey: Data
    let createdAt: Date
    let keyType: KeyType
    let attestation: Data?
    
    enum KeyType: String, Codable {
        case secureEnclave
        case keychain
    }
}

// MARK: - Key Store Implementation

final class KeyStore: KeyStoreProtocol {
    
    static let shared = KeyStore()
    
    // Identifier tagging
    private let keychainService = "com.iamhuman.keystore"
    private let keyTag = "com.iamhuman.signing-key"
    
    var isSecureEnclaveAvailable: Bool {
        if #available(iOS 16.0, *) {
            return SecureEnclave.isAvailable
        } else {
            return checkSecureEnclaveAvailability()
        }
    }
    
    // MARK: - Generate Key Pair
    
    func generateKeyPair() async throws -> KeyPairInfo {
        let keyId = UUID().uuidString
        
        if isSecureEnclaveAvailable {
            return try await generateSecureEnclaveKey(keyId: keyId)
        } else {
            return try await generateKeychainKey(keyId: keyId)
        }
    }
    
    private func generateSecureEnclaveKey(keyId: String) async throws -> KeyPairInfo {
        var error: Unmanaged<CFError>?
        
        // Define access control
        // Note: .privateKeyUsage is required for SEP keys
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage], 
            &error
        ) else {
            throw KeyStoreError.accessControlCreationFailed
        }
        
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: getApplicationTag(for: keyId),
                kSecAttrAccessControl as String: accessControl
            ]
        ]
        
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw KeyStoreError.keyGenerationFailed(error?.takeRetainedValue())
        }
        
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw KeyStoreError.publicKeyExtractionFailed
        }
        
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw KeyStoreError.publicKeyExportFailed
        }
        
        // App Attest placeholder (requires DCAppAttestService)
        let attestation: Data? = nil
        
        return KeyPairInfo(
            keyId: keyId,
            publicKey: publicKeyData,
            createdAt: Date(),
            keyType: .secureEnclave,
            attestation: attestation
        )
    }
    
    private func generateKeychainKey(keyId: String) async throws -> KeyPairInfo {
        let privateKey = P256.Signing.PrivateKey()
        let publicKeyData = privateKey.publicKey.rawRepresentation
        
        // Store in Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keyId,
            kSecValueData as String: privateKey.rawRepresentation,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Remove existing if any (just in case UUID collision or re-use)
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyStoreError.keychainStoreFailed(status)
        }
        
        return KeyPairInfo(
            keyId: keyId,
            publicKey: publicKeyData,
            createdAt: Date(),
            keyType: .keychain,
            attestation: nil
        )
    }
    
    // MARK: - Sign
    
    func sign(data: Data, keyId: String) async throws -> Data {
        // Try Secure Enclave first
        do {
            return try await signWithSecureEnclave(data: data, keyId: keyId)
        } catch {
            // If failed (e.g. key not found), try keychain
            return try await signWithKeychainKey(data: data, keyId: keyId)
        }
    }
    
    private func signWithSecureEnclave(data: Data, keyId: String) async throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: getApplicationTag(for: keyId),
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess, let privateKey = item else {
            throw KeyStoreError.keyNotFound
        }
        
        let key = privateKey as! SecKey
        var error: Unmanaged<CFError>?
        
        // Algorithm: ECDSA with SHA256
        guard let signature = SecKeyCreateSignature(
            key,
            .ecdsaSignatureMessageX962SHA256,
            data as CFData,
            &error
        ) as Data? else {
            throw KeyStoreError.signatureFailed(error?.takeRetainedValue())
        }
        
        return signature
    }
    
    private func signWithKeychainKey(data: Data, keyId: String) async throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keyId,
            kSecReturnData as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess, let privateKeyData = item as? Data else {
            throw KeyStoreError.keyNotFound
        }
        
        let privateKey = try P256.Signing.PrivateKey(rawRepresentation: privateKeyData)
        let signature = try privateKey.signature(for: data)
        return signature.rawRepresentation
    }
    
    // MARK: - Get Public Key
    
    func getPublicKey(keyId: String) async throws -> Data {
        do {
            return try await getSecureEnclavePublicKey(keyId: keyId)
        } catch {
            return try await getKeychainPublicKey(keyId: keyId)
        }
    }
    
    private func getSecureEnclavePublicKey(keyId: String) async throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: getApplicationTag(for: keyId),
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess, let privateKey = item else {
            throw KeyStoreError.keyNotFound
        }
        
        let key = privateKey as! SecKey
        guard let publicKey = SecKeyCopyPublicKey(key) else {
            throw KeyStoreError.publicKeyExtractionFailed
        }
        
        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw KeyStoreError.publicKeyExportFailed
        }
        
        return publicKeyData
    }
    
    private func getKeychainPublicKey(keyId: String) async throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keyId,
            kSecReturnData as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess, let privateKeyData = item as? Data else {
            throw KeyStoreError.keyNotFound
        }
        
        let privateKey = try P256.Signing.PrivateKey(rawRepresentation: privateKeyData)
        return privateKey.publicKey.rawRepresentation
    }
    
    // MARK: - Delete Key
    
    func deleteKey(keyId: String) async throws {
        // Delete from SE
        let seQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: getApplicationTag(for: keyId)
        ]
        SecItemDelete(seQuery as CFDictionary)
        
        // Delete from Keychain
        let kcQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keyId
        ]
        SecItemDelete(kcQuery as CFDictionary)
    }
    
    // MARK: - Helpers
    
    private func getApplicationTag(for keyId: String) -> Data {
        return "\(keyTag).\(keyId)".data(using: .utf8)!
    }
    
    private func checkSecureEnclaveAvailability() -> Bool {
        var error: Unmanaged<CFError>?
        let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage],
            &error
        )
        
        guard access != nil, error == nil else { return false }
        return true
    }
}

// MARK: - Errors

enum KeyStoreError: Error {
    case accessControlCreationFailed
    case keyGenerationFailed(CFError?)
    case publicKeyExtractionFailed
    case publicKeyExportFailed
    case keychainStoreFailed(OSStatus)
    case keyNotFound
    case signatureFailed(CFError?)
}
