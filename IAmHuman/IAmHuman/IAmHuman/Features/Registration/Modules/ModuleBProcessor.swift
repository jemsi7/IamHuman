// Features/Registration/Modules/ModuleBProcessor.swift

import Foundation
import Combine
import CryptoKit

final class ModuleBProcessor {

    let progressPublisher = PassthroughSubject<RegistrationViewModel.ModuleProgress, Never>()

    private let sensorManager: SensorCaptureManager
    private let voiceChallengeEngine: VoiceChallengeEngine

    private var cancellables = Set<AnyCancellable>()
    private let stateQueue = DispatchQueue(label: "moduleB.state")

    private var audioSamples: [Float] = []
    private var inferenceSamples: [VoiceChallengeResult] = []
    private var modelFallbackUsed = false

    // Tuned for better pass rate on noisy environments / fallback model path.
    private let labelConfidenceThreshold: Float = 0.35
    private let requiredVoiceWindows = 3
    private let requiredSilenceRatio: Float = 0.55

    private struct Snapshot {
        let sampleCount: Int
        let avgAudioLevel: Float
        let dominantLabel: VoiceChallengeLabel
        let dominantConfidence: Float
        let fallbackUsed: Bool
    }

    init(
        sensorManager: SensorCaptureManager,
        voiceChallengeEngine: VoiceChallengeEngine = AdaptiveVoiceChallengeEngine.defaultEngine()
    ) {
        self.sensorManager = sensorManager
        self.voiceChallengeEngine = voiceChallengeEngine
    }

    func run(nonce: String, sessionId: String) async throws -> EvidenceAtom {
        resetState()

        // 1. Start Audio/Camera
        await MainActor.run { [weak self] in
            guard let self = self else { return }

            self.sensorManager.audio.audioFeatureSubject
                .sink { [weak self] features in
                    guard let self = self else { return }
                    let inference = self.voiceChallengeEngine.infer(audioFeatures: features)
                    self.appendAudioSample(energy: features.energy, inference: inference)
                }
                .store(in: &self.cancellables)

            self.sensorManager.audio.start()
            self.sensorManager.camera.start()
        }

        let totalSeconds = 15
        let phase1End = 5
        let phase2End = 10

        var phase1ValidWindows = 0
        var phase2SilenceWindows = 0
        var phase2TotalWindows = 0
        var phase3ValidWindows = 0

        // 2. Voice challenge: Ah -> Silence -> Oh
        for i in 0..<totalSeconds {
            let snapshot = makeSnapshot(recentCount: 12)

            let phase: Int
            let message: String
            if i < phase1End {
                phase = 1
                message = "음성 챌린지 1/3: '아아아' 발음을 유지하세요"
            } else if i < phase2End {
                phase = 2
                message = "음성 챌린지 2/3: 지금은 조용히 유지하세요"
            } else {
                phase = 3
                message = "음성 챌린지 3/3: '오오오' 발음을 유지하세요"
            }

            let isAh = snapshot.dominantLabel == .ah && snapshot.dominantConfidence >= labelConfidenceThreshold
            let isSilence = snapshot.dominantLabel == .silence && snapshot.dominantConfidence >= labelConfidenceThreshold
            let isOh = snapshot.dominantLabel == .oh && snapshot.dominantConfidence >= labelConfidenceThreshold
            let isFallbackVoiced =
                snapshot.fallbackUsed &&
                (snapshot.dominantLabel == .ah || snapshot.dominantLabel == .oh) &&
                snapshot.dominantConfidence >= labelConfidenceThreshold

            let meetingRequirement: Bool
            var warningMessage: String?

            switch phase {
            case 1:
                meetingRequirement = isAh
                if meetingRequirement {
                    phase1ValidWindows += 1
                } else if i >= 2 {
                    warningMessage = "'아' 발음을 또렷하게 유지해주세요"
                }

            case 2:
                phase2TotalWindows += 1
                meetingRequirement = isSilence
                if meetingRequirement {
                    phase2SilenceWindows += 1
                } else {
                    warningMessage = "지금은 무음 구간입니다"
                }

            default:
                // Fallback voice engine can be unstable between ah/oh;
                // accept stable voiced output in phase 3 to reduce false negatives.
                meetingRequirement = isOh || isFallbackVoiced
                if meetingRequirement {
                    phase3ValidWindows += 1
                } else if i >= 12 {
                    warningMessage = "'오' 발음을 또렷하게 유지해주세요"
                }
            }

            let qualityIndicators = RegistrationViewModel.QualityIndicators(
                faceDetected: true,
                gazeDetected: true,
                audioLevel: snapshot.avgAudioLevel,
                motionOk: true,
                lightingOk: true,
                isPaused: !meetingRequirement && i > 2,
                warningMessage: warningMessage
            )

            let progress = RegistrationViewModel.ModuleProgress(
                timeRemaining: TimeInterval(totalSeconds - i),
                statusMessage: message,
                qualityIndicators: qualityIndicators
            )
            progressPublisher.send(progress)

            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        // 3. Stop
        await MainActor.run { [weak self] in
            self?.sensorManager.audio.stop()
            self?.sensorManager.camera.stop()
            self?.cancellables.removeAll()
        }

        let snapshot = makeSnapshot(recentCount: 20)
        let phase2SilenceRatio = Float(phase2SilenceWindows) / Float(max(phase2TotalWindows, 1))

        #if targetEnvironment(simulator)
        let score: Float = 90.0
        #else
        guard phase1ValidWindows >= requiredVoiceWindows else {
            throw ModuleError.audioNotDetected
        }
        guard phase2SilenceRatio >= requiredSilenceRatio else {
            throw ModuleError.audioNotDetected
        }
        guard phase3ValidWindows >= requiredVoiceWindows else {
            throw ModuleError.audioNotDetected
        }

        let articulationScore = Float(phase1ValidWindows + phase3ValidWindows) / 10.0
        let score: Float = min(98, 60 + articulationScore * 25 + phase2SilenceRatio * 15)
        #endif

        // 4. Result
        let commitData = SHA256.hash(data: Data("\(sessionId)-\(nonce)-B".utf8)).withUnsafeBytes { Data($0) }

        let challengePassed =
            phase1ValidWindows >= requiredVoiceWindows &&
            phase2SilenceRatio >= requiredSilenceRatio &&
            phase3ValidWindows >= requiredVoiceWindows

        return EvidenceAtom(
            module: "B",
            commit: commitData,
            score: score,
            meta: TimelineMeta(
                durationMs: 15000,
                sampleCount: snapshot.sampleCount,
                flags: [
                    "ah_detected": phase1ValidWindows >= requiredVoiceWindows,
                    "silence_ok": phase2SilenceRatio >= requiredSilenceRatio,
                    "oh_detected": phase3ValidWindows >= requiredVoiceWindows,
                    "voice_challenge_passed": challengePassed,
                    "model_fallback_used": snapshot.fallbackUsed
                ],
                dataHash: "vc_\(phase1ValidWindows)-\(Int(phase2SilenceRatio * 100))-\(phase3ValidWindows)"
            )
        )
    }

    private func resetState() {
        stateQueue.sync {
            audioSamples = []
            inferenceSamples = []
            modelFallbackUsed = false
        }
    }

    private func appendAudioSample(energy: Float, inference: VoiceChallengeResult) {
        stateQueue.sync {
            audioSamples.append(energy)
            inferenceSamples.append(inference)

            if inferenceSamples.count > 120 {
                inferenceSamples.removeFirst(inferenceSamples.count - 120)
            }

            if inference.usedFallback {
                modelFallbackUsed = true
            }
        }
    }

    private func makeSnapshot(recentCount: Int) -> Snapshot {
        stateQueue.sync {
            let recentAudio = Array(audioSamples.suffix(recentCount))
            let avgAudio = recentAudio.isEmpty ? 0 : recentAudio.reduce(0, +) / Float(recentAudio.count)
            let recentInference = Array(inferenceSamples.suffix(recentCount))

            let (label, confidence) = dominantPrediction(from: recentInference)

            return Snapshot(
                sampleCount: audioSamples.count,
                avgAudioLevel: avgAudio,
                dominantLabel: label,
                dominantConfidence: confidence,
                fallbackUsed: modelFallbackUsed
            )
        }
    }

    private func dominantPrediction(from samples: [VoiceChallengeResult]) -> (VoiceChallengeLabel, Float) {
        guard !samples.isEmpty else {
            return (.unknown, 0)
        }

        var grouped: [VoiceChallengeLabel: [Float]] = [:]
        for sample in samples {
            grouped[sample.label, default: []].append(sample.confidence)
        }

        let winner = grouped.max { lhs, rhs in
            lhs.value.count < rhs.value.count
        }

        guard let winner else {
            return (.unknown, 0)
        }

        let meanConfidence = winner.value.reduce(0, +) / Float(max(winner.value.count, 1))
        return (winner.key, meanConfidence)
    }

}
