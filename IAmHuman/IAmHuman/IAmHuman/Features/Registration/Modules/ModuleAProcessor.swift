// Features/Registration/Modules/ModuleAProcessor.swift

import Foundation
import Combine
import CryptoKit

enum ModuleError: Error {
    case gazeNotDetected
    case audioNotDetected
    case touchNotDetected
    case faceNotDetected
    case livenessNotDetected
}

final class ModuleAProcessor: ObservableObject {

    // MARK: - Publishers
    let progressPublisher = PassthroughSubject<RegistrationViewModel.ModuleProgress, Never>()

    // MARK: - Dependencies
    private let sensorManager: SensorCaptureManager
    private let faceLivenessEngine: FaceLivenessEngine

    // MARK: - State
    private var cancellables = Set<AnyCancellable>()
    private let stateQueue = DispatchQueue(label: "moduleA.state")

    private var accumulatedFeatures: [CameraCapture.FrameFeatures] = []
    private var gazeDetectedCount: Int = 0
    private var faceDetectedCount: Int = 0
    private var livenessSamples: [Float] = []
    private var modelFallbackUsed = false

    private struct Snapshot {
        let sampleCount: Int
        let gazeCount: Int
        let faceCount: Int
        let recentFeatures: [CameraCapture.FrameFeatures]
        let livenessMean: Float
        let fallbackUsed: Bool
    }

    init(
        sensorManager: SensorCaptureManager,
        faceLivenessEngine: FaceLivenessEngine = AdaptiveFaceLivenessEngine.defaultEngine()
    ) {
        self.sensorManager = sensorManager
        self.faceLivenessEngine = faceLivenessEngine
    }

    func run(nonce: String, sessionId: String) async throws -> EvidenceAtom {
        resetState()

        // 1. Prepare Sensors
        await MainActor.run { [weak self] in
            guard let self = self else { return }

            self.sensorManager.camera.frameFeatureSubject
                .sink { [weak self] feature in
                    self?.appendFrameFeature(feature)
                }
                .store(in: &self.cancellables)

            self.sensorManager.camera.pixelBufferSubject
                .sink { [weak self] frame in
                    guard let self = self else { return }
                    let result = self.faceLivenessEngine.infer(
                        pixelBuffer: frame.pixelBuffer,
                        faceObservation: frame.faceObservation
                    )
                    self.appendLivenessResult(result)
                }
                .store(in: &self.cancellables)

            self.sensorManager.camera.start()
            self.sensorManager.motion.start()
        }

        let totalSeconds = 5

        // 2. Execute Scenario
        for i in 0..<totalSeconds {
            let snapshot = makeSnapshot(recentCount: 6)

            var faceOk = snapshot.recentFeatures.contains {
                $0.faceRect != nil || $0.faceConfidence > 0.3
            }

            var gazeOk = snapshot.recentFeatures.contains { feature in
                let hasFace = feature.faceRect != nil || feature.faceConfidence > 0.3
                let gazeOffset = sqrt(feature.gazeX * feature.gazeX + feature.gazeY * feature.gazeY)
                return hasFace && gazeOffset < 2.0
            }

            var livenessOk = snapshot.livenessMean >= 0.7

            #if targetEnvironment(simulator)
            faceOk = true
            gazeOk = true
            livenessOk = true
            #endif

            let statusMessage: String
            var warningMessage: String?

            if !faceOk {
                statusMessage = "얼굴을 화면 중앙에 맞춰주세요"
                warningMessage = "얼굴이 충분히 감지되지 않습니다"
            } else if !livenessOk {
                statusMessage = "얼굴 라이브니스를 확인 중입니다"
                warningMessage = "정면을 유지하고 천천히 움직여주세요"
            } else if !gazeOk {
                statusMessage = "시선을 화면 중앙으로 유지해주세요"
                warningMessage = "시선이 자주 벗어나고 있습니다"
            } else {
                statusMessage = "얼굴 라이브니스 확인 중..."
            }

            let qualityIndicators = RegistrationViewModel.QualityIndicators(
                faceDetected: faceOk,
                gazeDetected: gazeOk,
                audioLevel: 0,
                motionOk: true,
                lightingOk: true,
                isPaused: !livenessOk && i > 1,
                warningMessage: warningMessage
            )

            let progress = RegistrationViewModel.ModuleProgress(
                timeRemaining: TimeInterval(totalSeconds - i),
                statusMessage: statusMessage,
                qualityIndicators: qualityIndicators
            )
            progressPublisher.send(progress)

            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        // 3. Stop Sensors
        await MainActor.run { [weak self] in
            self?.sensorManager.camera.stop()
            self?.sensorManager.motion.stop()
            self?.cancellables.removeAll()
        }

        // 4. Validate
        let snapshot = makeSnapshot(recentCount: 6)
        let totalSamples = max(snapshot.sampleCount, 1)
        let gazeRatio = Float(snapshot.gazeCount) / Float(totalSamples)
        let faceRatio = Float(snapshot.faceCount) / Float(totalSamples)
        let livenessMean = snapshot.livenessMean

        #if targetEnvironment(simulator)
        let score: Float = min(96, max(72, 45 + livenessMean * 35 + gazeRatio * 20))
        #else
        guard faceRatio >= 0.6 else {
            throw ModuleError.faceNotDetected
        }
        guard livenessMean >= 0.7 else {
            throw ModuleError.livenessNotDetected
        }
        guard gazeRatio >= 0.3 else {
            throw ModuleError.gazeNotDetected
        }
        let score: Float = min(98, 40 + livenessMean * 40 + gazeRatio * 20)
        #endif

        // 5. Result
        let commitData = SHA256.hash(data: Data("\(sessionId)-\(nonce)-A".utf8)).withUnsafeBytes { Data($0) }

        let meta = TimelineMeta(
            durationMs: 5000,
            sampleCount: snapshot.sampleCount,
            flags: [
                "face_detected": faceRatio >= 0.6,
                "gaze_detected": gazeRatio >= 0.3,
                "liveness_passed": livenessMean >= 0.7,
                "model_fallback_used": snapshot.fallbackUsed
            ],
            dataHash: "live_\(Int(livenessMean * 100))_gaze_\(snapshot.gazeCount)"
        )

        return EvidenceAtom(
            module: "A",
            commit: commitData,
            score: score,
            meta: meta
        )
    }

    private func resetState() {
        stateQueue.sync {
            accumulatedFeatures = []
            gazeDetectedCount = 0
            faceDetectedCount = 0
            livenessSamples = []
            modelFallbackUsed = false
        }
    }

    private func appendFrameFeature(_ feature: CameraCapture.FrameFeatures) {
        stateQueue.sync {
            accumulatedFeatures.append(feature)

            if feature.faceRect != nil || feature.faceConfidence > 0.3 {
                faceDetectedCount += 1

                let gazeOffset = sqrt(feature.gazeX * feature.gazeX + feature.gazeY * feature.gazeY)
                if gazeOffset < 2.0 {
                    gazeDetectedCount += 1
                }
            }
        }
    }

    private func appendLivenessResult(_ result: FaceLivenessResult) {
        stateQueue.sync {
            livenessSamples.append(result.liveProbability)
            if result.usedFallback {
                modelFallbackUsed = true
            }
        }
    }

    private func makeSnapshot(recentCount: Int) -> Snapshot {
        stateQueue.sync {
            let recent = Array(accumulatedFeatures.suffix(recentCount))
            let livenessMean: Float
            if livenessSamples.isEmpty {
                livenessMean = 0
            } else {
                livenessMean = livenessSamples.reduce(0, +) / Float(livenessSamples.count)
            }

            return Snapshot(
                sampleCount: accumulatedFeatures.count,
                gazeCount: gazeDetectedCount,
                faceCount: faceDetectedCount,
                recentFeatures: recent,
                livenessMean: livenessMean,
                fallbackUsed: modelFallbackUsed
            )
        }
    }
}
