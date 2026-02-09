// Sensors/HapticEngine.swift

import CoreHaptics
import Combine
import QuartzCore
import UIKit

final class HapticEngine: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isAvailable = false
    @Published private(set) var lastHapticTime: TimeInterval?
    
    // MARK: - Event Stream
    
    let hapticEventSubject = PassthroughSubject<HapticEvent, Never>()
    
    // MARK: - Private Properties
    
    private var engine: CHHapticEngine?
    
    // MARK: - Types
    
    struct HapticEvent {
        let timestamp: TimeInterval
        let type: HapticType
        let intensity: Float
        let duration: TimeInterval
    }
    
    enum HapticType {
        case tap
        case continuous
        case custom
    }
    
    // MARK: - Setup
    
    func setup() async throws {
        print("DEBUG: HapticEngine setup starting...")
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            print("DEBUG: HapticEngine - Hardware haptics not supported")
            throw HapticError.notSupported
        }
        
        do {
            engine = try CHHapticEngine()
            engine?.playsHapticsOnly = true
            engine?.isAutoShutdownEnabled = false // Keep it alive
            
            engine?.resetHandler = { [weak self] in
                print("DEBUG: HapticEngine - Resetting engine")
                Task {
                    try? await self?.engine?.start()
                }
            }
            
            engine?.stoppedHandler = { reason in
                print("DEBUG: HapticEngine - Engine stopped: \(reason.rawValue)")
            }
            
            try await engine?.start()
            print("DEBUG: HapticEngine - Engine started successfully")
            
            await MainActor.run {
                self.isAvailable = true
            }
        } catch {
            print("DEBUG: HapticEngine - Failed to initialize: \(error)")
            throw HapticError.engineNotReady
        }
    }
    
    // MARK: - Play Haptic
    
    func playTapHaptic(intensity: Float = 1.0) async throws -> TimeInterval {
        print("DEBUG: HapticEngine - playTapHaptic requested (intensity: \(intensity))")
        
        // Standard Fallback: UIImpactFeedbackGenerator
        // This is much more reliable for simple taps and works even if CHHapticEngine is silent
        await MainActor.run {
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred(intensity: CGFloat(intensity))
            print("DEBUG: HapticEngine - UIImpactFeedbackGenerator triggered")
        }
        
        guard let engine = engine else {
            print("DEBUG: HapticEngine - Engine is nil!")
            throw HapticError.engineNotReady
        }
        
        do {
            try await engine.start()
        } catch {
            print("DEBUG: HapticEngine - Failed to start engine on playback: \(error)")
        }
        
        let timestamp = CACurrentMediaTime()
        
        do {
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
            
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [sharpness, intensityParam],
                relativeTime: 0
            )
            
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            
            try player.start(atTime: CHHapticTimeImmediate)
            print("DEBUG: HapticEngine - Tap pattern started successfully at \(timestamp)")
        } catch {
            print("DEBUG: HapticEngine - Playback error: \(error)")
            throw error
        }
        let hapticEvent = HapticEvent(
            timestamp: timestamp,
            type: .tap,
            intensity: intensity,
            duration: 0.05
        )
        hapticEventSubject.send(hapticEvent)
        
        await MainActor.run {
            self.lastHapticTime = timestamp
        }
        
        return timestamp
    }
    
    func playContinuousHaptic(duration: TimeInterval, intensity: Float = 0.5) async throws -> TimeInterval {
        guard let engine = engine else {
            throw HapticError.engineNotReady
        }
        
        let timestamp = CACurrentMediaTime()
        
        let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
        
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [intensityParam, sharpness],
            relativeTime: 0,
            duration: duration
        )
        
        let pattern = try CHHapticPattern(events: [event], parameters: [])
        let player = try engine.makePlayer(with: pattern)
        
        try player.start(atTime: CHHapticTimeImmediate)
        
        let hapticEvent = HapticEvent(
            timestamp: timestamp,
            type: .continuous,
            intensity: intensity,
            duration: duration
        )
        hapticEventSubject.send(hapticEvent)
        
        await MainActor.run {
            self.lastHapticTime = timestamp
        }
        
        return timestamp
    }
    
    // MARK: - Cleanup
    
    func stop() {
        engine?.stop()
    }
}

enum HapticError: Error {
    case notSupported
    case engineNotReady
}
