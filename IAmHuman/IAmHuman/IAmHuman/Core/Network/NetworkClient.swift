// Core/Network/NetworkClient.swift

import Foundation

protocol NetworkClientProtocol {
    func requestNonce() async throws -> Nonce
    func register(package: RegistrationPackage, expirationDate: Date) async throws -> VerifiableCredential
}

final class NetworkClient: NetworkClientProtocol {
    
    static let shared = NetworkClient()
    
    func requestNonce() async throws -> Nonce {
        // Mock delay
        try await Task.sleep(nanoseconds: 500_000_000)
        return Nonce(
            value: UUID().uuidString,
            timestamp: Date(),
            ttl: 300
        )
    }
    
    func register(package: RegistrationPackage, expirationDate: Date) async throws -> VerifiableCredential {
        // Mock delay
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Return a mock VC
        return VerifiableCredential(
            vcId: UUID().uuidString,
            issuer: "did:web:iamhuman.io",
            holderDid: "did:key:z6Mk...",
            issuanceDate: Date(),
            expirationDate: expirationDate,
            trustLevel: package.graphSummary.trustGrade,
            signature: Data()
        )
    }
}
