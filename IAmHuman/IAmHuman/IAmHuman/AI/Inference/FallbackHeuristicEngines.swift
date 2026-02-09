import Foundation
import CoreVideo
import Vision

final class HeuristicFaceLivenessEngine: FaceLivenessEngine {
    let modelVersion: String = "heuristic-face-v1"
    let isModelBacked: Bool = false

    func infer(pixelBuffer: CVPixelBuffer, faceObservation: VNFaceObservation?) -> FaceLivenessResult {
        _ = pixelBuffer
        guard let face = faceObservation else {
            return FaceLivenessResult(
                label: .spoof,
                liveProbability: 0.05,
                spoofProbability: 0.95,
                confidence: 0.95,
                usedFallback: true
            )
        }

        let confidence = Float(face.confidence)
        let area = Float(face.boundingBox.width * face.boundingBox.height)
        let centerOffsetX = abs(Float(face.boundingBox.midX) - 0.5)
        let centerOffsetY = abs(Float(face.boundingBox.midY) - 0.5)
        let centeredScore = max(0, 1 - (centerOffsetX + centerOffsetY))

        let areaContribution = min(area * 3.0, 1.0) * 0.2
        let live = clamp(0.35 + confidence * 0.35 + centeredScore * 0.1 + areaContribution, min: 0.05, max: 0.95)
        let spoof = clamp(1 - live, min: 0.05, max: 0.95)

        return FaceLivenessResult(
            label: live >= spoof ? .live : .spoof,
            liveProbability: live,
            spoofProbability: spoof,
            confidence: max(live, spoof),
            usedFallback: true
        )
    }

    private func clamp(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
        Swift.max(minValue, Swift.min(maxValue, value))
    }
}

final class HeuristicVoiceChallengeEngine: VoiceChallengeEngine {
    let modelVersion: String = "heuristic-voice-v1"
    let isModelBacked: Bool = false

    func infer(audioFeatures: AudioCapture.AudioFeatures) -> VoiceChallengeResult {
        let energy = audioFeatures.normalizedEnergy
        let pitch = audioFeatures.pitch ?? 0

        if energy < 0.2 {
            return VoiceChallengeResult(
                label: .silence,
                confidence: 0.9,
                probabilities: [.silence: 0.9, .ah: 0.05, .oh: 0.05],
                usedFallback: true
            )
        }

        if pitch > 0 {
            if pitch < 170 {
                return VoiceChallengeResult(
                    label: .ah,
                    confidence: 0.72,
                    probabilities: [.ah: 0.72, .oh: 0.2, .silence: 0.08],
                    usedFallback: true
                )
            }

            return VoiceChallengeResult(
                label: .oh,
                confidence: 0.72,
                probabilities: [.oh: 0.72, .ah: 0.2, .silence: 0.08],
                usedFallback: true
            )
        }

        // Pitch 추정이 불안정할 때는 MFCC 평균값으로 완만하게 분리
        let mfccMean = audioFeatures.normalizedMFCCs.reduce(0, +) / Float(max(audioFeatures.normalizedMFCCs.count, 1))
        if mfccMean > 0.52 {
            return VoiceChallengeResult(
                label: .oh,
                confidence: 0.6,
                probabilities: [.oh: 0.6, .ah: 0.3, .silence: 0.1],
                usedFallback: true
            )
        }

        return VoiceChallengeResult(
            label: .ah,
            confidence: 0.6,
            probabilities: [.ah: 0.6, .oh: 0.3, .silence: 0.1],
            usedFallback: true
        )
    }
}

final class AdaptiveFaceLivenessEngine: FaceLivenessEngine {
    private let primary: FaceLivenessEngine
    private let fallback: FaceLivenessEngine

    var modelVersion: String {
        primary.isModelBacked ? primary.modelVersion : fallback.modelVersion
    }

    var isModelBacked: Bool {
        primary.isModelBacked
    }

    init(primary: FaceLivenessEngine, fallback: FaceLivenessEngine) {
        self.primary = primary
        self.fallback = fallback
    }

    func infer(pixelBuffer: CVPixelBuffer, faceObservation: VNFaceObservation?) -> FaceLivenessResult {
        if primary.isModelBacked {
            let primaryResult = primary.infer(pixelBuffer: pixelBuffer, faceObservation: faceObservation)
            if primaryResult.label != .unknown, primaryResult.confidence >= 0.35 {
                return primaryResult
            }
        }

        var fallbackResult = fallback.infer(pixelBuffer: pixelBuffer, faceObservation: faceObservation)
        fallbackResult.usedFallback = true
        return fallbackResult
    }

    static func defaultEngine(bundle: Bundle = .main) -> FaceLivenessEngine {
        AdaptiveFaceLivenessEngine(
            primary: CoreMLFaceLivenessEngine(bundle: bundle),
            fallback: HeuristicFaceLivenessEngine()
        )
    }
}

final class AdaptiveVoiceChallengeEngine: VoiceChallengeEngine {
    private let primary: VoiceChallengeEngine
    private let fallback: VoiceChallengeEngine

    var modelVersion: String {
        primary.isModelBacked ? primary.modelVersion : fallback.modelVersion
    }

    var isModelBacked: Bool {
        primary.isModelBacked
    }

    init(primary: VoiceChallengeEngine, fallback: VoiceChallengeEngine) {
        self.primary = primary
        self.fallback = fallback
    }

    func infer(audioFeatures: AudioCapture.AudioFeatures) -> VoiceChallengeResult {
        if primary.isModelBacked {
            let primaryResult = primary.infer(audioFeatures: audioFeatures)
            if primaryResult.label != .unknown, primaryResult.confidence >= 0.35 {
                return primaryResult
            }
        }

        var fallbackResult = fallback.infer(audioFeatures: audioFeatures)
        fallbackResult.usedFallback = true
        return fallbackResult
    }

    static func defaultEngine(bundle: Bundle = .main) -> VoiceChallengeEngine {
        AdaptiveVoiceChallengeEngine(
            primary: CoreMLVoiceChallengeEngine(bundle: bundle),
            fallback: HeuristicVoiceChallengeEngine()
        )
    }
}
