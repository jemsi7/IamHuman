// Sensors/MotionCapture.swift

import CoreMotion
import Combine

final class MotionCapture: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isRunning = false
    @Published private(set) var currentAttitude: CMAttitude?
    @Published private(set) var currentAcceleration: CMAcceleration?
    
    // MARK: - Feature Stream
    
    let motionFeatureSubject = PassthroughSubject<MotionFeatures, Never>()
    
    // MARK: - Private Properties
    
    private let motionManager = CMMotionManager()
    private let operationQueue = OperationQueue()
    private let updateInterval: TimeInterval = 1.0 / 100.0  // 100Hz
    
    // MARK: - Types
    
    struct MotionFeatures {
        let timestamp: TimeInterval
        let attitude: AttitudeSummary
        let userAcceleration: Vector3
        let rotationRate: Vector3
        let gravity: Vector3
        let motionMagnitude: Float
    }
    
    struct AttitudeSummary {
        let roll: Float
        let pitch: Float
        let yaw: Float
        let quaternion: Quaternion
    }
    
    struct Quaternion {
        let x: Float, y: Float, z: Float, w: Float
    }
    
    struct Vector3 {
        let x: Float, y: Float, z: Float
        
        var magnitude: Float {
            sqrt(x*x + y*y + z*z)
        }
    }
    
    // MARK: - Setup
    
    func setup() throws {
        guard motionManager.isDeviceMotionAvailable else {
            throw MotionCaptureError.notAvailable
        }
        
        operationQueue.name = "motion.capture"
        operationQueue.maxConcurrentOperationCount = 1
    }
    
    // MARK: - Control
    
    func start() {
        guard !isRunning else { return }
        
        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: operationQueue
        ) { [weak self] motion, error in
            guard let motion = motion, error == nil else { return }
            self?.processMotion(motion)
        }
        
        DispatchQueue.main.async {
            self.isRunning = true
        }
    }
    
    func stop() {
        guard isRunning else { return }
        motionManager.stopDeviceMotionUpdates()
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }
    
    // MARK: - Motion Processing
    
    private func processMotion(_ motion: CMDeviceMotion) {
        let attitude = motion.attitude
        let userAccel = motion.userAcceleration
        let rotationRate = motion.rotationRate
        let gravity = motion.gravity
        
        let attitudeSummary = AttitudeSummary(
            roll: Float(attitude.roll),
            pitch: Float(attitude.pitch),
            yaw: Float(attitude.yaw),
            quaternion: Quaternion(
                x: Float(attitude.quaternion.x),
                y: Float(attitude.quaternion.y),
                z: Float(attitude.quaternion.z),
                w: Float(attitude.quaternion.w)
            )
        )
        
        let userAccelVec = Vector3(
            x: Float(userAccel.x),
            y: Float(userAccel.y),
            z: Float(userAccel.z)
        )
        
        let rotationVec = Vector3(
            x: Float(rotationRate.x),
            y: Float(rotationRate.y),
            z: Float(rotationRate.z)
        )
        
        let gravityVec = Vector3(
            x: Float(gravity.x),
            y: Float(gravity.y),
            z: Float(gravity.z)
        )
        
        // Magnitude combining linear and rotational energy
        let motionMagnitude = userAccelVec.magnitude + rotationVec.magnitude * 0.5
        
        let features = MotionFeatures(
            timestamp: motion.timestamp,
            attitude: attitudeSummary,
            userAcceleration: userAccelVec,
            rotationRate: rotationVec,
            gravity: gravityVec,
            motionMagnitude: motionMagnitude
        )
        
        motionFeatureSubject.send(features)
        
        // Optional UI updates
        DispatchQueue.main.async {
            self.currentAttitude = attitude
            self.currentAcceleration = userAccel
        }
    }
}

enum MotionCaptureError: Error {
    case notAvailable
}
