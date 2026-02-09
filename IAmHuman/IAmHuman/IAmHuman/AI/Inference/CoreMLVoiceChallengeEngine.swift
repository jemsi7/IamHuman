import Foundation
import CoreML

final class CoreMLVoiceChallengeEngine: VoiceChallengeEngine {
    let modelVersion: String = "VoiceChallengeV1"

    private let model: MLModel?
    private let inputName: String?

    var isModelBacked: Bool {
        model != nil
    }

    init(bundle: Bundle = .main) {
        self.model = CoreMLVoiceChallengeEngine.loadModel(named: modelVersion, bundle: bundle)
        self.inputName = model?.modelDescription.inputDescriptionsByName.keys.first
    }

    func infer(audioFeatures: AudioCapture.AudioFeatures) -> VoiceChallengeResult {
        guard let model, let inputName else {
            return .unknown(usedFallback: false)
        }

        do {
            guard let featureValue = try makeInputValue(model: model, inputName: inputName, audioFeatures: audioFeatures) else {
                return .unknown(usedFallback: false)
            }

            let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: featureValue])
            let prediction = try model.prediction(from: provider)

            if let probabilities = parseProbabilities(from: prediction), !probabilities.isEmpty {
                return buildResult(from: probabilities)
            }

            if let logits = parseLogits(from: prediction), logits.count >= 3 {
                let probs = softmax(logits)
                let mapped: [VoiceChallengeLabel: Float] = [
                    .ah: probs[0],
                    .oh: probs[1],
                    .silence: probs[2]
                ]
                return buildResult(from: mapped)
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

    private func makeInputValue(
        model: MLModel,
        inputName: String,
        audioFeatures: AudioCapture.AudioFeatures
    ) throws -> MLFeatureValue? {
        guard let desc = model.modelDescription.inputDescriptionsByName[inputName] else {
            return nil
        }

        switch desc.type {
        case .multiArray:
            guard let constraint = desc.multiArrayConstraint else {
                return nil
            }
            let vector = audioFeatures.normalizedVector
            let elementCount = constraint.shape.reduce(1) { partialResult, number in
                partialResult * max(number.intValue, 1)
            }

            let array = try MLMultiArray(shape: [NSNumber(value: elementCount)], dataType: .float32)
            for i in 0..<elementCount {
                let value = vector.isEmpty ? 0 : vector[min(i, vector.count - 1)]
                array[i] = NSNumber(value: value)
            }
            return MLFeatureValue(multiArray: array)

        case .dictionary:
            let dict: [AnyHashable: NSNumber] = [
                "energy": NSNumber(value: audioFeatures.normalizedEnergy),
                "pitch": NSNumber(value: audioFeatures.normalizedPitch),
                "zcr": NSNumber(value: audioFeatures.normalizedZeroCrossingRate)
            ]
            return try MLFeatureValue(dictionary: dict)

        default:
            return nil
        }
    }

    private func parseProbabilities(from provider: MLFeatureProvider) -> [VoiceChallengeLabel: Float]? {
        for name in provider.featureNames {
            guard let value = provider.featureValue(for: name) else { continue }
            guard value.type == .dictionary else { continue }

            var mapped: [VoiceChallengeLabel: Float] = [:]
            for (key, number) in value.dictionaryValue {
                let lower = String(describing: key).lowercased()
                if let label = mapLabel(from: lower) {
                    mapped[label] = number.floatValue
                }
            }

            return mapped
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

    private func softmax(_ logits: [Float]) -> [Float] {
        guard let maxValue = logits.max() else { return [] }
        let exps = logits.map { exp($0 - maxValue) }
        let sum = exps.reduce(0, +)
        if sum == 0 { return logits.map { _ in 0 } }
        return exps.map { $0 / sum }
    }

    private func buildResult(from probs: [VoiceChallengeLabel: Float]) -> VoiceChallengeResult {
        let best = probs.max { lhs, rhs in lhs.value < rhs.value }
        return VoiceChallengeResult(
            label: best?.key ?? .unknown,
            confidence: best?.value ?? 0,
            probabilities: probs,
            usedFallback: false
        )
    }

    private func mapLabel(from key: String) -> VoiceChallengeLabel? {
        let normalized = key.replacingOccurrences(of: " ", with: "").lowercased()

        switch normalized {
        case "ah", "aa", "class_ah", "ahprob", "ah_prob":
            return .ah
        case "oh", "oo", "class_oh", "ohprob", "oh_prob":
            return .oh
        case "silence", "quiet", "none", "class_silence", "silenceprob", "silence_prob":
            return .silence
        default:
            if normalized.contains("silence") || normalized.contains("quiet") {
                return .silence
            }
            if normalized.contains("ah") {
                return .ah
            }
            if normalized.contains("oh") {
                return .oh
            }
            return nil
        }
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
