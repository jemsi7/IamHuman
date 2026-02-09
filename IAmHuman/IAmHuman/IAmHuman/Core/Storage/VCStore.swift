// Core/Storage/VCStore.swift

import Foundation
import CryptoKit

protocol VCStoreProtocol {
    func save(_ vc: VerifiableCredential) throws
    func loadAll() throws -> [VerifiableCredential]
    func delete(_ id: String) throws
}

final class VCStore: VCStoreProtocol {
    
    static let shared = VCStore()
    
    private let fileManager = FileManager.default
    private var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var storeURL: URL {
        documentsURL.appendingPathComponent("vcs")
    }
    
    init() {
        if !fileManager.fileExists(atPath: storeURL.path) {
            try? fileManager.createDirectory(at: storeURL, withIntermediateDirectories: true)
        }
    }
    
    func save(_ vc: VerifiableCredential) throws {
        let data = try JSONEncoder().encode(vc)
        // In real app: Encrypt with KeyStore key before writing
        // For scaffold: Write JSON
        let fileURL = storeURL.appendingPathComponent(vc.id).appendingPathExtension("json")
        try data.write(to: fileURL)
    }
    
    func loadAll() throws -> [VerifiableCredential] {
        let fileURLs = try fileManager.contentsOfDirectory(at: storeURL, includingPropertiesForKeys: nil)
        return try fileURLs.compactMap { url in
            let data = try Data(contentsOf: url)
            return try? JSONDecoder().decode(VerifiableCredential.self, from: data)
        }
    }
    
    func delete(_ id: String) throws {
        let fileURL = storeURL.appendingPathComponent(id).appendingPathExtension("json")
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }
}
