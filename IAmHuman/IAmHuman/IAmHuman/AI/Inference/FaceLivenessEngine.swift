import Foundation
import CoreVideo
import Vision

enum FaceLivenessLabel: String {
    case live
    case spoof
    case unknown
}

struct FaceLivenessResult {
    var label: FaceLivenessLabel
    var liveProbability: Float
    var spoofProbability: Float
    var confidence: Float
    var usedFallback: Bool

    var isLive: Bool {
        label == .live
    }

    static func unknown(usedFallback: Bool) -> FaceLivenessResult {
        FaceLivenessResult(
            label: .unknown,
            liveProbability: 0,
            spoofProbability: 0,
            confidence: 0,
            usedFallback: usedFallback
        )
    }
}

protocol FaceLivenessEngine: AnyObject {
    var modelVersion: String { get }
    var isModelBacked: Bool { get }

    func infer(pixelBuffer: CVPixelBuffer, faceObservation: VNFaceObservation?) -> FaceLivenessResult
}
