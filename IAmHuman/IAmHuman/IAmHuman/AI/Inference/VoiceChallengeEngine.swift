import Foundation

enum VoiceChallengeLabel: String {
    case ah
    case oh
    case silence
    case unknown
}

struct VoiceChallengeResult {
    var label: VoiceChallengeLabel
    var confidence: Float
    var probabilities: [VoiceChallengeLabel: Float]
    var usedFallback: Bool

    static func unknown(usedFallback: Bool) -> VoiceChallengeResult {
        VoiceChallengeResult(
            label: .unknown,
            confidence: 0,
            probabilities: [:],
            usedFallback: usedFallback
        )
    }
}

protocol VoiceChallengeEngine: AnyObject {
    var modelVersion: String { get }
    var isModelBacked: Bool { get }

    func infer(audioFeatures: AudioCapture.AudioFeatures) -> VoiceChallengeResult
}
