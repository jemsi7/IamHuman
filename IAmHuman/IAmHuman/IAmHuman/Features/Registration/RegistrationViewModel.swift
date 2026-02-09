// Features/Registration/RegistrationViewModel.swift

import Foundation
import Combine
import SwiftUI

@MainActor
@Observable
final class RegistrationViewModel {
    
    // MARK: - State
    
    enum RegistrationState: Equatable {
        case idle
        case requestingNonce
        case moduleA(ModuleProgress)
        case moduleB(ModuleProgress)
        case moduleC(ModuleProgress)
        case computingGraph
        case submitting
        case success(VerifiableCredential)
        case failure(RegistrationError)
        
        static func == (lhs: RegistrationState, rhs: RegistrationState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.requestingNonce, .requestingNonce): return true
            case (.moduleA, .moduleA): return true
            case (.moduleB, .moduleB): return true
            case (.moduleC, .moduleC): return true
            case (.computingGraph, .computingGraph): return true
            case (.submitting, .submitting): return true
            case (.success, .success): return true
            case (.failure, .failure): return true
            default: return false
            }
        }
    }
    
    struct ModuleProgress {
        var timeRemaining: TimeInterval = 20
        var statusMessage: String = ""
        var qualityIndicators: QualityIndicators = .init()
    }
    
    struct QualityIndicators {
        var faceDetected: Bool = false
        var gazeDetected: Bool = false
        var audioLevel: Float = 0
        var motionOk: Bool = true
        var lightingOk: Bool = true
        var isPaused: Bool = false
        var warningMessage: String? = nil
    }
    
    struct RegistrationError: Error {
        let reason: String
        let canRetry: Bool
    }
    
    var state: RegistrationState = .idle
    var errorMessage: String?
    var overallProgress: Float = 0.0
    /// ID 유효기간 설정 (기본값: 1년)
    var expirationDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    var skipsCount: Int = 0  // Number of modules skipped (affects grade)
    
    // MARK: - Internal Results
    private var nonce: Nonce?
    private var sessionId: String?
    private var moduleAResult: EvidenceAtom?
    private var moduleBResult: EvidenceAtom?
    private var moduleCResult: EvidenceAtom?
    private var skipModuleB = false
    private var skipModuleC = false
    
    // MARK: - Dependencies
    private let networkClient: NetworkClientProtocol
    private let sensorManager: SensorCaptureManager
    private let graphScorer: EvidenceGraphScorer
    private let faceLivenessEngine: FaceLivenessEngine
    private let voiceChallengeEngine: VoiceChallengeEngine
    
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()
    
    // Wrapper instances for Module Processors
    @ObservationIgnored private var moduleAProcessor: ModuleAProcessor
    @ObservationIgnored private var moduleBProcessor: ModuleBProcessor
    @ObservationIgnored private var moduleCProcessor: ModuleCProcessor
    
    init(
        networkClient: NetworkClientProtocol = NetworkClient.shared,
        sensorManager: SensorCaptureManager = SensorCaptureManager.shared,
        graphScorer: EvidenceGraphScorer = EvidenceGraphScorer(),
        faceLivenessEngine: FaceLivenessEngine = AdaptiveFaceLivenessEngine.defaultEngine(),
        voiceChallengeEngine: VoiceChallengeEngine = AdaptiveVoiceChallengeEngine.defaultEngine()
    ) {
        self.networkClient = networkClient
        self.sensorManager = sensorManager
        self.graphScorer = graphScorer
        self.faceLivenessEngine = faceLivenessEngine
        self.voiceChallengeEngine = voiceChallengeEngine

        self.moduleAProcessor = ModuleAProcessor(
            sensorManager: sensorManager,
            faceLivenessEngine: faceLivenessEngine
        )
        self.moduleBProcessor = ModuleBProcessor(
            sensorManager: sensorManager,
            voiceChallengeEngine: voiceChallengeEngine
        )
        self.moduleCProcessor = ModuleCProcessor(sensorManager: sensorManager)

        print("DEBUG: Face liveness engine = \(faceLivenessEngine.modelVersion), modelBacked = \(faceLivenessEngine.isModelBacked)")
        print("DEBUG: Voice challenge engine = \(voiceChallengeEngine.modelVersion), modelBacked = \(voiceChallengeEngine.isModelBacked)")
    }
    
    // MARK: - Actions
    
    func startRegistration() {
        print("DEBUG: startRegistration() called")
        Task {
            await runRegistrationFlow()
        }
    }
    
    func registerTouch() {
        moduleCProcessor.registerTouch()
    }
    
    func skipCurrentModule() {
        switch state {
        case .moduleB:
            skipModuleB = true
            skipsCount += 1
        case .moduleC:
            skipModuleC = true
            skipsCount += 1
        default:
            break
        }
    }
    
    private func runRegistrationFlow() async {
        print("DEBUG: runRegistrationFlow started")
        
        // 1. Update UI immediately to show loading state
        state = .requestingNonce
        overallProgress = 0.0
        sessionId = UUID().uuidString
        
        // 2. Permission Check
        print("DEBUG: Requesting sensor permissions...")
        let permissionsGranted = await sensorManager.requestPermissions()
        print("DEBUG: Permissions granted: \(permissionsGranted)")
        
        guard permissionsGranted else {
            let errorMsg = sensorManager.lastError?.localizedDescription ?? "Sensor permissions denied (Unknown reason)"
            print("DEBUG: Permission denied error: \(errorMsg)")
            state = .failure(.init(reason: errorMsg, canRetry: true))
            return
        }
        
        do {
            // 3. Get Nonce
            print("DEBUG: Requesting nonce...")
            nonce = try await networkClient.requestNonce()
            print("DEBUG: Nonce received: \(nonce?.value ?? "nil")")
            
            let currentNonce = nonce!.value
            let currentSession = sessionId!
            
            // Reset skip flags
            skipModuleB = false
            skipModuleC = false
            skipsCount = 0
            
            
            // 2. Module A (Required - face verification)
            state = .moduleA(.init())
            bindProgress(processor: moduleAProcessor.progressPublisher, baseProgress: 0.0)
            moduleAResult = try await moduleAProcessor.run(nonce: currentNonce, sessionId: currentSession)
            
            // 3. Module B (Can be skipped)
            state = .moduleB(.init())
            bindProgress(processor: moduleBProcessor.progressPublisher, baseProgress: 0.33)
            
            // Run with skip check
            do {
                moduleBResult = try await withSkipCheck(for: .moduleB) {
                    try await self.moduleBProcessor.run(nonce: currentNonce, sessionId: currentSession)
                }
            } catch ModuleSkipError.skipped {
                moduleBResult = createSkippedAtom(module: "B", nonce: currentNonce, sessionId: currentSession)
            }
            
            // 4. Module C (Can be skipped)
            state = .moduleC(.init())
            bindProgress(processor: moduleCProcessor.progressPublisher, baseProgress: 0.66)
            
            do {
                moduleCResult = try await withSkipCheck(for: .moduleC) {
                    try await self.moduleCProcessor.run(nonce: currentNonce, sessionId: currentSession)
                }
            } catch ModuleSkipError.skipped {
                moduleCResult = createSkippedAtom(module: "C", nonce: currentNonce, sessionId: currentSession)
            }
            
            // 5. Compute Graph
            state = .computingGraph
            overallProgress = 1.0
            
            guard let a = moduleAResult, let b = moduleBResult, let c = moduleCResult else {
                throw RegistrationError(reason: "Missing module results", canRetry: true)
            }
            
            var graph = graphScorer.computeVerdict(moduleA: a, moduleB: b, moduleC: c)
            
            // Apply grade demotion based on skips
            // Requirement: Even with 2 skips, if Module A is passed, grade should be 'C' and succeed.
            let grades = ["A", "B", "C", "D"]
            if let currentIndex = grades.firstIndex(of: graph.trustGrade) {
                var demotedIndex = currentIndex + skipsCount
                
                // If modules were skipped but Module A passed, ensure at least Grade C (index 2)
                // This prevents failure (Grade D) when skipping is intentional.
                if skipsCount > 0 && demotedIndex >= 3 {
                    demotedIndex = 2 // Force to "C"
                }
                
                // Also ensures it doesn't go beyond "D" index just in case
                demotedIndex = min(demotedIndex, grades.count - 1)
                
                graph = EvidenceGraphSummary(
                    edges: graph.edges,
                    trustGrade: grades[demotedIndex],
                    trustScore: graph.trustScore,
                    moduleScores: graph.moduleScores
                )
            }
            
            // Registration succeeds if Grade is at least C. 
            // Grade D leads to failure.
            if graph.trustGrade == "D" {
                 throw RegistrationError(reason: "인증 실패: 신뢰 등급이 너무 낮습니다 (D)", canRetry: true)
            }
            
            // 6. Submit
            state = .submitting
            
            // Sign package (Mock signature)
            let signature = Data() // In real app: KeyStore.shared.sign(...)
            
            let package = RegistrationPackage(
                sessionId: currentSession,
                nonce: currentNonce,
                atoms: [a, b, c],
                graphSummary: graph,
                signature: signature
            )
            
            let vc = try await networkClient.register(package: package, expirationDate: expirationDate)
            
            state = .success(vc)
            // AppState would observe this change or be updated by View
            
        } catch {
            let reason: String
            let canRetry: Bool
            
            if let moduleError = error as? ModuleError {
                canRetry = true
                switch moduleError {
                case .gazeNotDetected:
                    reason = "시선 안정성이 부족합니다"
                case .livenessNotDetected:
                    reason = "얼굴 라이브니스 검증에 실패했습니다"
                case .audioNotDetected:
                    reason = "음성 챌린지를 통과하지 못했습니다"
                case .touchNotDetected:
                    reason = "터치가 감지되지 않았습니다"
                case .faceNotDetected:
                    reason = "얼굴이 감지되지 않았습니다"
                }
            } else if let regError = error as? RegistrationError {
                reason = regError.reason
                canRetry = regError.canRetry
            } else {
                reason = error.localizedDescription
                canRetry = true
            }
            
            state = .failure(RegistrationError(reason: reason, canRetry: canRetry))
            errorMessage = reason
        }
    }
    
    
    private func bindProgress(processor: PassthroughSubject<ModuleProgress, Never>, baseProgress: Float) {
        cancellables.removeAll()
        processor
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                // Update specific module state wrapper if needed, 
                // but since 'state' is an enum with associated value, we need to replace it.
                // This is slightly tricky with associated values.
                // We'll just update the overall UI progress for simplicity in this scaffold
                // and assume the View refreshes based on the event.
                
                // Re-injecting into state enum for UI Text correctness:
                guard let self = self else { return }
                switch self.state {
                case .moduleA: self.state = .moduleA(progress)
                case .moduleB: self.state = .moduleB(progress)
                case .moduleC: self.state = .moduleC(progress)
                default: break
                }
                
                // Overall Bar - calculate based on time remaining
                // Module A: 5 sec, Module B/C: 15 sec each
                let moduleDuration: Float
                switch self.state {
                case .moduleA: moduleDuration = 5.0
                case .moduleB, .moduleC: moduleDuration = 15.0
                default: moduleDuration = 15.0
                }
                let elapsed = moduleDuration - Float(progress.timeRemaining)
                let moduleContribution = (elapsed / moduleDuration) * 0.33
                self.overallProgress = baseProgress + moduleContribution
            }
            .store(in: &cancellables)
    }
    
    func retry() {
        // Reset state
        state = .idle
        errorMessage = nil
        overallProgress = 0.0
        
        // Reset module results
        moduleAResult = nil
        moduleBResult = nil
        moduleCResult = nil
        
        // Recreate module processors to clear their internal state
        moduleAProcessor = ModuleAProcessor(
            sensorManager: sensorManager,
            faceLivenessEngine: faceLivenessEngine
        )
        moduleBProcessor = ModuleBProcessor(
            sensorManager: sensorManager,
            voiceChallengeEngine: voiceChallengeEngine
        )
        moduleCProcessor = ModuleCProcessor(sensorManager: sensorManager)
        
        // Start again
        startRegistration()
    }
    
    // MARK: - Skip Helpers
    
    private enum ModuleSkipError: Error {
        case skipped
    }
    
    private enum ModuleSkipTarget {
        case moduleB
        case moduleC
    }
    
    // Update callsites in runRegistrationFlow:
    // withSkipCheck(for: .moduleB) { ... }
    
    private func withSkipCheck(for target: ModuleSkipTarget, operation: @escaping () async throws -> EvidenceAtom) async throws -> EvidenceAtom {
        // Run operation with periodic skip checks
        return try await withThrowingTaskGroup(of: EvidenceAtom.self) { group in
            group.addTask {
                return try await operation()
            }
            
            group.addTask {
                // Periodically check for skip flag
                while true {
                    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    
                    if await self.checkSkip(for: target) {
                        throw ModuleSkipError.skipped
                    }
                }
            }
            
            // Return first completed result
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    // Helper to access MainActor properties from background task
    private func checkSkip(for target: ModuleSkipTarget) -> Bool {
        switch target {
        case .moduleB: return skipModuleB
        case .moduleC: return skipModuleC
        }
    }
    
    private func createSkippedAtom(module: String, nonce: String, sessionId: String) -> EvidenceAtom {
        return EvidenceAtom(
            module: module,
            commit: Data(),
            score: 0, // Skipped modules get 0 score
            meta: TimelineMeta(
                durationMs: 0,
                sampleCount: 0,
                flags: ["skipped": true],
                dataHash: "skipped"
            )
        )
    }
}
