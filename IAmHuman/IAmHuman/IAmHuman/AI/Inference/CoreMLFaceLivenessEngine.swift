import Foundation
import CoreML
import Vision

final class CoreMLFaceLivenessEngine: FaceLivenessEngine {
    let modelVersion: String = "FaceLivenessV1"

    private let model: MLModel?
    private let inputName: String?

    var isModelBacked: Bool {
        model != nil
    }

    init(bundle: Bundle = .main) {
        self.model = CoreMLFaceLivenessEngine.loadModel(named: modelVersion, bundle: bundle)
        self.inputName = model?.modelDescription.inputDescriptionsByName.keys.first
    }

    func infer(pixelBuffer: CVPixelBuffer, faceObservation: VNFaceObservation?) -> FaceLivenessResult {
        _ = faceObservation
        guard let model, let inputName else {
            return .unknown(usedFallback: false)
        }

        do {
            let provider = try MLDictionaryFeatureProvider(
                dictionary: [inputName: MLFeatureValue(pixelBuffer: pixelBuffer)]
            )
            let prediction = try model.prediction(from: provider)

            if let probabilities = parseProbabilities(from: prediction), !probabilities.isEmpty {
                let live = probabilities["live"] ?? probabilities["real"] ?? probabilities["human"] ?? 0
                let spoofBase = probabilities["spoof"] ?? probabilities["fake"]
                let spoof = spoofBase ?? max(0, 1 - live)
                let confidence = max(live, spoof)
                return FaceLivenessResult(
                    label: live >= spoof ? .live : .spoof,
                    liveProbability: live,
                    spoofProbability: spoof,
                    confidence: confidence,
                    usedFallback: false
                )
            }

            if let logits = parseLogits(from: prediction), logits.count >= 2 {
                let live = sigmoid(logits[0])
                let spoof = sigmoid(logits[1])
                let confidence = max(live, spoof)
                return FaceLivenessResult(
                    label: live >= spoof ? .live : .spoof,
                    liveProbability: live,
                    spoofProbability: spoof,
                    confidence: confidence,
                    usedFallback: false
                )
            }
        } catch {
            return .unknown(usedFallback: false)
        }

        return .unknown(usedFallback: false)
    }

    private static func loadModel(named name: String, bundle: Bundle) -> MLModel? {
        if let compiledURL = bundle.url(forResource: name, withExtension: "mlmodelc"),
           let model = try? MLModel(contentsOf: compiledURL) {
            return model
        }

        if let sourceURL = bundle.url(forResource: name, withExtension: "mlmodel"),
           let compiledURL = try? MLModel.compileModel(at: sourceURL),
           let model = try? MLModel(contentsOf: compiledURL) {
            return model
        }

        return nil
    }

    private func parseProbabilities(from provider: MLFeatureProvider) -> [String: Float]? {
        for name in provider.featureNames {
            guard let value = provider.featureValue(for: name) else { continue }
            guard value.type == .dictionary else { continue }
            let raw = value.dictionaryValue
            var result: [String: Float] = [:]
            for (key, number) in raw {
                result[String(describing: key).lowercased()] = number.floatValue
            }
            return result
        }
        return nil
    }

    private func parseLogits(from provider: MLFeatureProvider) -> [Float]? {
        for name in provider.featureNames {
            guard let value = provider.featureValue(for: name) else { continue }
            guard value.type == .multiArray, let array = value.multiArrayValue else { continue }
            return array.toFloatArray()
        }
        return nil
    }

    private func sigmoid(_ x: Float) -> Float {
        1.0 / (1.0 + exp(-x))
    }
}

private extension MLMultiArray {
    func toFloatArray() -> [Float] {
        let count = self.count
        var output = [Float]()
        output.reserveCapacity(count)

        for index in 0..<count {
            output.append(self[index].floatValue)
        }

        return output
    }
}
