// Models/APIModels.swift

import Foundation

// MARK: - API / Data Transfer Objects

struct Nonce: Codable {
    let value: String
    let timestamp: Date
    let ttl: TimeInterval
}

struct RegistrationPackage: Codable {
    let sessionId: String
    let nonce: String
    let atoms: [EvidenceAtom]
    let graphSummary: EvidenceGraphSummary
    let signature: Data
}

struct EvidenceAtom: Codable {
    let module: String // "A", "B", "C"
    let commit: Data   // SHA256 of features
    let score: Float
    let meta: TimelineMeta
}

struct TimelineMeta: Codable {
    let durationMs: Int
    let sampleCount: Int
    let flags: [String: Bool]
    let dataHash: String // simplified
}

struct EvidenceGraphSummary: Codable {
    let edges: [GraphEdge]
    let trustGrade: String // "A", "B", "C", "D"
    let trustScore: Float
    let moduleScores: [String: Float]? // Optional detail scores
}

struct GraphEdge: Codable {
    let from: String
    let to: String
    let score: Float
    let passed: Bool
}

struct VerifiableCredential: Codable, Identifiable {
    var id: String { vcId }
    
    let vcId: String
    let issuer: String
    let holderDid: String
    let issuanceDate: Date
    let expirationDate: Date
    let trustLevel: String
    let signature: Data
    
    // Encrypted content would be separate
}
