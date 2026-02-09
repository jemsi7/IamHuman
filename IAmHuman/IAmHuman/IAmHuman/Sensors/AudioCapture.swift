// Sensors/AudioCapture.swift

import AVFoundation
import Accelerate
import Combine

final class AudioCapture: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isRunning = false
    @Published private(set) var currentLevel: Float = 0
    @Published private(set) var isVoiceActive = false
    
    // MARK: - Feature Stream
    
    let audioFeatureSubject = PassthroughSubject<AudioFeatures, Never>()
    
    // MARK: - Private Properties
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private let processingQueue = DispatchQueue(label: "audio.processing", qos: .userInteractive)
    
    // MFCC extraction parameters
    private let sampleRate: Double = 44100
    private let frameSize = 1024
    private let hopSize = 512
    private let numMFCCs = 13
    
    // Buffers for processing
    private var audioBuffer: [Float] = []
    
    // MARK: - Types
    
    struct AudioFeatures {
        let timestamp: TimeInterval
        let mfccs: [Float]  // 13 coefficients
        let energy: Float
        let pitch: Float?
        let isVoiceActive: Bool
        let zeroCrossingRate: Float

        var normalizedEnergy: Float {
            clamp(energy / 0.08)
        }

        var normalizedPitch: Float {
            guard let pitch else { return 0 }
            return clamp((pitch - 60) / 300)
        }

        var normalizedZeroCrossingRate: Float {
            clamp(zeroCrossingRate * 4)
        }

        var normalizedMFCCs: [Float] {
            mfccs.map { clamp(($0 + 8) / 16) }
        }

        var normalizedVector: [Float] {
            normalizedMFCCs + [normalizedEnergy, normalizedPitch, normalizedZeroCrossingRate]
        }

        private func clamp(_ value: Float) -> Float {
            Swift.max(0, Swift.min(1, value))
        }
    }
    
    // MARK: - Setup
    
    func setup() async throws {
        guard await checkPermission() else {
            throw AudioCaptureError.permissionDenied
        }
        
        try await MainActor.run {
            try configureAudioSession()
            try configureAudioEngine()
        }
    }
    
    private func checkPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }
    
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
    }
    
    private func configureAudioEngine() throws {
        // Reuse existing engine if available
        if audioEngine == nil {
            audioEngine = AVAudioEngine()
        }
        guard let engine = audioEngine else {
            throw AudioCaptureError.engineInitFailed
        }
        
        inputNode = engine.inputNode
        let format = inputNode?.outputFormat(forBus: 0)
        
        // Remove existing tap if any before installing new one
        inputNode?.removeTap(onBus: 0)
        
        // Install Tap
        inputNode?.installTap(onBus: 0, bufferSize: AVAudioFrameCount(frameSize), format: format) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, time: time)
        }
    }
    
    // MARK: - Control
    
    func start() {
        // Reconfigure if engine was reset
        if audioEngine == nil {
            do {
                try configureAudioSession()
                try configureAudioEngine()
            } catch {
                print("Audio reconfiguration failed: \(error)")
                return
            }
        }
        
        guard let engine = audioEngine, !isRunning else { return }
        
        do {
            try engine.start()
            DispatchQueue.main.async {
                self.isRunning = true
            }
        } catch {
            print("Audio engine start failed: \(error)")
        }
    }
    
    func stop() {
        guard isRunning else { return }
        print("DEBUG: AudioCapture - Stopping engine and resetting session")
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        
        // Deactivate session and RESET category to ambient
        // Measurement/PlayAndRecord can sometimes suppress haptics on real devices
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(.ambient) // Reset to neutral
            print("DEBUG: AudioSession deactivated and reset to ambient")
        } catch {
            print("DEBUG: AudioSession deactivation/reset failed: \(error)")
        }
        
        DispatchQueue.main.async {
            self.isRunning = false
            self.audioBuffer.removeAll()
        }
    }
    
    // MARK: - Audio Processing (No Raw Storage)
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        
        // Copy samples (immediately disposed after this scope)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 1. Energy
            var energy: Float = 0
            vDSP_measqv(samples, 1, &energy, vDSP_Length(samples.count))
            energy = sqrt(energy) // RMS (vDSP_measqv returns Mean Square)
            
            // 2. VAD
            let vadThreshold: Float = 0.01
            let isVoice = energy > vadThreshold
            
            // 3. Zero Crossing Rate
            let zcr = self.computeZeroCrossingRate(samples)
            
            // 4. MFCC (Approximation)
            let mfccs = self.extractMFCCs(samples)
            
            // 5. Pitch
            let pitch = isVoice ? self.estimatePitch(samples) : nil
            
            let features = AudioFeatures(
                timestamp: CACurrentMediaTime(),
                mfccs: mfccs,
                energy: energy,
                pitch: pitch,
                isVoiceActive: isVoice,
                zeroCrossingRate: zcr
            )
            
            // Publish
            self.audioFeatureSubject.send(features)
            
            DispatchQueue.main.async {
                self.currentLevel = energy
                self.isVoiceActive = isVoice
            }
        }
    }
    
    private func computeZeroCrossingRate(_ samples: [Float]) -> Float {
        var crossings = 0
        for i in 1..<samples.count {
            if (samples[i] >= 0 && samples[i-1] < 0) ||
               (samples[i] < 0 && samples[i-1] >= 0) {
                crossings += 1
            }
        }
        return Float(crossings) / Float(samples.count)
    }
    
    private func extractMFCCs(_ samples: [Float]) -> [Float] {
        // Placeholder for detailed vDSP implementation
        // Returns dummy vector if processing fails
        var mfccs = [Float](repeating: 0, count: numMFCCs)
        
        let fftSize = min(samples.count, frameSize)
        if fftSize == 0 { return mfccs }
        
        // Setup FFT
        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return mfccs }
        defer { vDSP_destroy_fftsetup(fftSetup) }
        
        // Prepare complex split
        var realPart = [Float](repeating: 0, count: fftSize)
        var imagPart = [Float](repeating: 0, count: fftSize)
        
        for i in 0..<fftSize { realPart[i] = samples[i] }
        
        // Use withUnsafeMutableBufferPointer for proper pointer lifetime
        realPart.withUnsafeMutableBufferPointer { realBuffer in
            imagPart.withUnsafeMutableBufferPointer { imagBuffer in
                var splitComplex = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imagBuffer.baseAddress!)
                
                // Execute FFT
                vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                
                // Magnitudes
                var magnitudes = [Float](repeating: 0, count: fftSize/2)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize/2))
                
                // Approximate Mel Bins (Linear spread for simplicity)
                let binSize = magnitudes.count / numMFCCs
                guard binSize > 0 else { return }
                
                for i in 0..<numMFCCs {
                    let start = i * binSize
                    let end = min(start + binSize, magnitudes.count)
                    var sum: Float = 0
                    vDSP_sve(Array(magnitudes[start..<end]), 1, &sum, vDSP_Length(end - start))
                    mfccs[i] = log10(max(sum, 1e-10))
                }
            }
        }
        
        return mfccs
    }
    
    private func estimatePitch(_ samples: [Float]) -> Float? {
        guard samples.count > 100 else { return nil }
        
        // Autocorrelation based pitch detection (Simplified)
        // Find first peak after zero crossing
        // (Omitted full algo for brevity)
        return 120.0 // Dummy Hz
    }
    
    // MARK: - Playback
    
    func playTestTone(frequency: Float = 1000, duration: TimeInterval = 0.1) async {
        // In real app, attach AVAudioPlayerNode to engine's output
        // This simulates the acoustic environment test
    }
}

enum AudioCaptureError: Error {
    case permissionDenied
    case engineInitFailed
}
