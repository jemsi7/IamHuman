// Features/Registration/Modules/ModuleCProcessor.swift

import Foundation
import Combine
import CryptoKit
import UIKit
import AVFoundation

final class ModuleCProcessor: @unchecked Sendable {
    
    let progressPublisher = PassthroughSubject<RegistrationViewModel.ModuleProgress, Never>()
    private let sensorManager: SensorCaptureManager
    private let hapticEngine: HapticEngine
    
    // Thread-safe state using actor isolation
    private let stateActor = TouchStateActor()
    
    // Touch detection publisher
    private var touchSubject = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()
    
    init(sensorManager: SensorCaptureManager) {
        self.sensorManager = sensorManager
        self.hapticEngine = sensorManager.haptic
    }
    
    // Call this when user taps
    func registerTouch() {
        Task {
            await stateActor.addTouch(Date())
        }
    }
    
    func run(nonce: String, sessionId: String) async throws -> EvidenceAtom {
        // Reset state
        await stateActor.reset()
        
        let start = Date()
        
        // 1. Start Sensors
        await MainActor.run {
            print("🎵 AudioSession 상태 (Module C 시작 시):")
            let session = AVAudioSession.sharedInstance()
            print("  Category: \(session.category.rawValue)")
            print("  Mode: \(session.mode.rawValue)")
            
            // Audio 완전 정지 및 세션 리셋 재시도 (B에서 끝냈어야 하지만 한 번 더 보장)
            self.sensorManager.audio.stop()
            self.sensorManager.motion.start()
        }
        
        // 잠시 대기 (세션 전환 시간 부여)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Define when haptic vibrations occur (relative seconds)
        let hapticSchedule = [3, 7, 11]
        
        // 2. Interactive Tasks
        let totalSeconds = 15
        var correctTouches = 0
        
        for i in 0..<totalSeconds {
            let elapsed = Date().timeIntervalSince(start)
            let remaining = max(0, Double(totalSeconds) - elapsed)
            
            // Check if haptic should trigger
            if hapticSchedule.contains(i) {
                // Play haptic
                print("DEBUG: ModuleCProcessor - Triggering haptic at second \(i)")
                do {
                    _ = try await hapticEngine.playTapHaptic()
                } catch {
                    print("DEBUG: ModuleCProcessor - Haptic playback failed: \(error)")
                }
                
                // Record haptic time for validation
                await stateActor.addHaptic(Date())
            }
            
            // Get current state
            let recentHaptics = await stateActor.getHaptics()
            let touches = await stateActor.getTouches()
            
            var statusMsg = "진동이 느껴지면 탭하세요"
            var warningMsg: String? = nil
            var isPaused = false
            
            // Check the LATEST haptic for immediate feedback
            if let lastHaptic = recentHaptics.last {
                let timeSinceHaptic = Date().timeIntervalSince(lastHaptic)
                
                if timeSinceHaptic < 2.0 {
                    // Inside window
                    statusMsg = "지금 탭하세요!"
                    
                    // Check if user has ALREADY tapped for this haptic
                    let hasValidTap = touches.contains { touchTime in
                        let diff = touchTime.timeIntervalSince(lastHaptic)
                        return diff >= 0 && diff < 2.0
                    }
                    
                    if !hasValidTap && timeSinceHaptic > 1.0 {
                        // Warning if 1s passed without tap
                        isPaused = true
                        warningMsg = "탭해주세요!"
                    }
                } else if timeSinceHaptic >= 2.0 && timeSinceHaptic < 3.0 {
                    // Window just closed, check result for this specific haptic
                    let hasValidTap = touches.contains { touchTime in
                        let diff = touchTime.timeIntervalSince(lastHaptic)
                        return diff >= 0 && diff < 2.0
                    }
                    
                    if !hasValidTap {
                        warningMsg = "진동을 놓쳤습니다!"
                    }
                }
            }
            
            let qualityIndicators = RegistrationViewModel.QualityIndicators(
                faceDetected: true,
                gazeDetected: true,
                audioLevel: 0,
                motionOk: true,
                lightingOk: true,
                isPaused: isPaused,
                warningMessage: warningMsg
            )
            
            let progress = RegistrationViewModel.ModuleProgress(
                timeRemaining: remaining,
                statusMessage: statusMsg,
                qualityIndicators: qualityIndicators
            )
            progressPublisher.send(progress)
            
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        
        // 3. Stop
        await MainActor.run {
            self.sensorManager.motion.stop()
        }
        
        // 4. Final Validation
        let finalHaptics = await stateActor.getHaptics()
        let finalTouches = await stateActor.getTouches()
        
        correctTouches = 0
        var missedHaptics = 0
        
        for hapticTime in finalHaptics {
            // Find ANY touch within 2.0s after this haptic
            let validTouch = finalTouches.first { touchTime in
                let diff = touchTime.timeIntervalSince(hapticTime)
                return diff >= 0 && diff <= 2.5 // Slightly lenient (2.5s) for legacy lag
            }
            
            if validTouch != nil {
                correctTouches += 1
            } else {
                missedHaptics += 1
            }
        }
        
        let totalHaptics = hapticSchedule.count
        let successRate = Float(correctTouches) / Float(max(totalHaptics, 1))
        
        #if targetEnvironment(simulator)
        let score: Float = 89.0
        #else
        // Require at least 2 correct touches
        guard correctTouches >= 2 else {
            throw ModuleError.touchNotDetected
        }
        let score: Float = 70 + successRate * 30
        #endif
        
        // 5. Result
        let commitData = SHA256.hash(data: Data("\(sessionId)-\(nonce)-C".utf8)).withUnsafeBytes { Data($0) }
        
        let touchCount = await stateActor.getTouches().count
        
        return EvidenceAtom(
            module: "C",
            commit: commitData,
            score: score,
            meta: TimelineMeta(
                durationMs: 15000,
                sampleCount: touchCount,
                flags: [
                    "correct": correctTouches >= 2,
                    "all_correct": correctTouches == totalHaptics
                ],
                dataHash: "touch_\(correctTouches)"
            )
        )
    }
}

// Actor for thread-safe state management
private actor TouchStateActor {
    private var touchTimestamps: [Date] = []
    private var hapticTimestamps: [Date] = []
    
    func reset() {
        touchTimestamps = []
        hapticTimestamps = []
    }
    
    func addTouch(_ date: Date) {
        touchTimestamps.append(date)
    }
    
    func addHaptic(_ date: Date) {
        hapticTimestamps.append(date)
    }
    
    func getTouches() -> [Date] {
        return touchTimestamps
    }
    
    func getHaptics() -> [Date] {
        return hapticTimestamps
    }
}

