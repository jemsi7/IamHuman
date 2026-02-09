// Sensors/CameraCapture.swift

import AVFoundation
import Vision
import Combine
import UIKit

// MARK: - Camera Capture Manager

final class CameraCapture: NSObject, ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isRunning = false
    @Published private(set) var currentFaceObservation: VNFaceObservation?
    @Published private(set) var error: CameraCaptureError?
    
    // MARK: - Feature Stream
    
    let frameFeatureSubject = PassthroughSubject<FrameFeatures, Never>()
    let pixelBufferSubject = PassthroughSubject<PixelFrame, Never>()
    
    // MARK: - Private Properties
    
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "camera.processing", qos: .userInteractive)
    private var faceDetectionRequest: VNDetectFaceLandmarksRequest?
    
    // Sliding window for immediate disposal
    private var frameBuffer: [FrameFeatures] = []
    private let maxBufferSize = 5
    
    // MARK: - Types
    
    struct FrameFeatures {
        let timestamp: TimeInterval
        let gazeX: Float
        let gazeY: Float
        let blinkScore: Float
        let faceConfidence: Float
        let lipOpenness: Float
        let lipWidth: Float
        let faceRect: CGRect?
    }

    struct PixelFrame {
        let timestamp: TimeInterval
        let pixelBuffer: CVPixelBuffer
        let faceObservation: VNFaceObservation?
    }
    
    // MARK: - Setup
    
    func setup() async throws {
        guard await checkPermission() else {
            throw CameraCaptureError.permissionDenied
        }
        
        // Setup MUST be done on a background queue or checked properly to avoid blocking Main Thread,
        // but session configuration is often done on a serial queue.
        // We us MainActor for state updates, processingQueue for AV config.
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
             processingQueue.async { [self] in
                 print("DEBUG: CameraCapture configureSession starting...")
                 do {
                     try self.configureSession()
                     print("DEBUG: CameraCapture configureSession complete")
                     continuation.resume()
                 } catch {
                     print("DEBUG: CameraCapture configureSession failed: \(error)")
                     continuation.resume(throwing: error)
                 }
             }
         }
    }
    
    private func checkPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
    
    private func configureSession() throws {
        // Skip if already configured
        guard captureSession.inputs.isEmpty else { return }
        
        #if targetEnvironment(simulator)
        print("Warning: Camera capture not supported on simulator. Skipping configuration.")
        return
        #endif
        
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        
        captureSession.sessionPreset = .high
        
        // Front camera
        guard let frontCamera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .front
        ) else {
            throw CameraCaptureError.cameraNotAvailable
        }
        
        let input = try AVCaptureDeviceInput(device: frontCamera)
        guard captureSession.canAddInput(input) else {
            throw CameraCaptureError.inputConfigurationFailed
        }
        captureSession.addInput(input)
        
        // Video output
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        guard captureSession.canAddOutput(videoOutput) else {
            throw CameraCaptureError.outputConfigurationFailed
        }
        captureSession.addOutput(videoOutput)
        
        // Configure face detection
        faceDetectionRequest = VNDetectFaceLandmarksRequest { [weak self] request, error in
            self?.handleFaceDetection(request: request, error: error)
        }
    }
    
    // MARK: - Control
    
    func start() {
        guard !isRunning else { return }
        processingQueue.async { [weak self] in
            self?.captureSession.startRunning()
            DispatchQueue.main.async {
                self?.isRunning = true
            }
        }
    }
    
    func stop() {
        guard isRunning else { return }
        processingQueue.async { [weak self] in
            self?.captureSession.stopRunning()
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.frameBuffer.removeAll()
            }
        }
    }
    
    // MARK: - Face Detection Handler
    
    private func handleFaceDetection(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNFaceObservation],
              let face = results.first else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            // Updating UI state (e.g. for drawing bounding box)
            self?.currentFaceObservation = face
        }
    }
    
    // MARK: - Feature Extraction (Discards Raw Data)
    
    private func extractFeatures(from sampleBuffer: CMSampleBuffer, face: VNFaceObservation?) -> FrameFeatures {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        
        var gazeX: Float = 0
        var gazeY: Float = 0
        var blinkScore: Float = 1
        var faceConfidence: Float = 0
        var lipOpenness: Float = 0
        var lipWidth: Float = 0
        var faceRect: CGRect? = nil
        
        if let face = face {
            faceConfidence = Float(face.confidence)
            faceRect = face.boundingBox
            
            // Gaze estimation (Simplified for this example)
            // Real implementation would use VNFaceLandmarkRegion2D logic
            if let landmarks = face.landmarks {
                
                // --- Gaze Proxy: Pupil vs Eye Center ---
                if let leftEye = landmarks.leftEye,
                   let leftPupil = landmarks.leftPupil {
                    
                    let eyePoints = leftEye.normalizedPoints
                    let pupilPoints = leftPupil.normalizedPoints
                    
                    if !eyePoints.isEmpty, let pupilP = pupilPoints.first {
                        let eyeCenter = eyePoints.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
                        let avgEyeCenter = CGPoint(x: eyeCenter.x / CGFloat(eyePoints.count), y: eyeCenter.y / CGFloat(eyePoints.count))
                        
                        gazeX = Float(pupilP.x - avgEyeCenter.x) * 10.0 // Scale up for sensitivity
                        gazeY = Float(pupilP.y - avgEyeCenter.y) * 10.0
                    }
                }
                
                // --- Blink Proxy: Vertical Eye Openness ---
                if let leftEye = landmarks.leftEye, leftEye.pointCount >= 6 {
                    let points = leftEye.normalizedPoints
                    let ear = computeEyeAspectRatio(points: Array(points))
                    // EAR < 0.2 usually means blink
                    blinkScore = ear < 0.2 ? 0 : 1
                }
                
                // --- Lip Metrics ---
                if let outerLips = landmarks.outerLips {
                    let points = outerLips.normalizedPoints
                    let (openness, width) = computeLipMetrics(points: Array(points))
                    lipOpenness = Float(openness)
                    lipWidth = Float(width)
                }
            }
        }
        
        return FrameFeatures(
            timestamp: timestamp,
            gazeX: gazeX,
            gazeY: gazeY,
            blinkScore: blinkScore,
            faceConfidence: faceConfidence,
            lipOpenness: lipOpenness,
            lipWidth: lipWidth,
            faceRect: faceRect
        )
    }
    
    private func computeEyeAspectRatio(points: [CGPoint]) -> Float {
        guard points.count >= 6 else { return 1.0 }
        
        // Points layout for VNFaceLandmarkRegion2D.leftEye:
        // 0: Left corner, 3: Right corner, 1,2: Top lid, 4,5: Bottom lid (approx)
        // Actual structure depends on Revision, but essentially top/bottom distance vs width
        
        // Simplified Logic:
        let vertical1 = distance(points[1], points[5])
        let vertical2 = distance(points[2], points[4])
        let horizontal = distance(points[0], points[3])
        
        guard horizontal > 0 else { return 1.0 }
        return Float((vertical1 + vertical2) / (2.0 * horizontal))
    }
    
    private func computeLipMetrics(points: [CGPoint]) -> (openness: CGFloat, width: CGFloat) {
        guard points.count >= 12 else { return (0, 0) }
        
        // Basic approximation for Outer Lips
        // Try not to rely on specific indices without verifying Revision.
        // Assuming standard 68-point dlib style mapping often used:
        // Top center ~ point index varies.
        // Let's use bounding box of the points for simplicity & robustness
        
        let maxY = points.map { $0.y }.max() ?? 0
        let minY = points.map { $0.y }.min() ?? 0
        let maxX = points.map { $0.x }.max() ?? 0
        let minX = points.map { $0.x }.min() ?? 0
        
        let openness = maxY - minY
        let width = maxX - minX
        
        return (openness, width)
    }
    
    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        sqrt(pow(p2.x - p1.x, 2) + pow(p2.y - p1.y, 2))
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // 1. Run Vision Face Detection
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored, options: [:])
        // .leftMirrored is common for front camera in portrait
        
        var detectedFace: VNFaceObservation? = nil
        
        if let request = faceDetectionRequest {
            try? handler.perform([request])
            // Get the result directly from the request
            if let results = request.results as? [VNFaceObservation], let face = results.first {
                detectedFace = face
            }
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let pixelFrame = PixelFrame(
            timestamp: timestamp,
            pixelBuffer: pixelBuffer,
            faceObservation: detectedFace
        )
        pixelBufferSubject.send(pixelFrame)
        
        // 2. Extract Features using the detected face
        let features = extractFeatures(from: sampleBuffer, face: detectedFace)
        
        // 3. Update UI state with face observation
        if detectedFace != nil {
            DispatchQueue.main.async { [weak self] in
                self?.currentFaceObservation = detectedFace
            }
        }
        
        // 4. Publish
        frameFeatureSubject.send(features)
        
        // 5. Buffer
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.frameBuffer.append(features)
            if self.frameBuffer.count > self.maxBufferSize {
                self.frameBuffer.removeFirst()
            }
        }
    }
}

// MARK: - Error

enum CameraCaptureError: Error {
    case permissionDenied
    case cameraNotAvailable
    case inputConfigurationFailed
    case outputConfigurationFailed
}
