// Sensors/SensorCaptureManager.swift

import Foundation
import Combine

final class SensorCaptureManager: ObservableObject {
    
    static let shared = SensorCaptureManager()
    
    // Child Managers
    let camera: CameraCapture
    let audio: AudioCapture
    let motion: MotionCapture
    let haptic: HapticEngine
    
    @Published var lastError: Error?
    
    private init() {
        self.camera = CameraCapture()
        self.audio = AudioCapture()
        self.motion = MotionCapture()
        self.haptic = HapticEngine()
    }
    
    func requestPermissions() async -> Bool {
        print("DEBUG: SensorCaptureManager.requestPermissions called")
        lastError = nil
        do {
            print("DEBUG: Setting up Camera...")
            try await camera.setup()
            print("DEBUG: Camera setup complete")
            
            print("DEBUG: Setting up Audio...")
            try await audio.setup()
            print("DEBUG: Audio setup complete")
            
            print("DEBUG: Setting up Motion...")
            try motion.setup()
            print("DEBUG: Motion setup complete")
            
            print("DEBUG: Setting up Haptic...")
            try await haptic.setup()
            print("DEBUG: Haptic setup complete")
            
            return true
        } catch {
            print("DEBUG: Sensor setup failed: \(error)")
            lastError = error
            return false
        }
    }
    
    func stopAll() {
        camera.stop()
        audio.stop()
        motion.stop()
        haptic.stop()
    }
}
