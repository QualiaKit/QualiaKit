import CoreML

public class BertModelWrapper {
    private let model: MLModel

    public init(modelURL: URL) throws {
        let compiledUrl = try MLModel.compileModel(at: modelURL)
        self.model = try MLModel(contentsOf: compiledUrl)
    }

    public func predictSentiment(inputIds: [Int], attentionMask: [Int]) throws -> Double {
        let shape = [1, NSNumber(value: inputIds.count)] as [NSNumber]
        let inputIdsMultiArray = try MLMultiArray(shape: shape, dataType: .int32)
        let maskMultiArray = try MLMultiArray(shape: shape, dataType: .int32)
        let tokenTypeMultiArray = try MLMultiArray(shape: shape, dataType: .int32)

        for i in 0..<inputIds.count {
            inputIdsMultiArray[[0, i] as [NSNumber]] = NSNumber(value: inputIds[i])
            maskMultiArray[[0, i] as [NSNumber]] = NSNumber(value: attentionMask[i])
            tokenTypeMultiArray[[0, i] as [NSNumber]] = 0
        }

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIdsMultiArray),
            "attention_mask": MLFeatureValue(multiArray: maskMultiArray),
            "token_type_ids": MLFeatureValue(multiArray: tokenTypeMultiArray),
        ])

        let output = try model.prediction(from: input)

        if let probs = output.featureValue(for: "classLabel_probs")?.dictionaryValue
            as? [String: Double]
        {

            let l0 = probs["LABEL_0"] ?? 0.0  // Negative
            let l1 = probs["LABEL_1"] ?? 0.0  // Neutral
            let l2 = probs["LABEL_2"] ?? 0.0  // Positive
            let l3 = probs["LABEL_3"] ?? 0.0
            let l4 = probs["LABEL_4"] ?? 0.0

            let softmaxed = softmax([l0, l1, l2, l3, l4])

            let pNegative = softmaxed[0]
            let pPositive = softmaxed[2]

            return pPositive - pNegative
        }
        return 0.0
    }

    private func softmax(_ inputs: [Double]) -> [Double] {
        let maxInput = inputs.max() ?? 0.0
        let expValues = inputs.map { exp($0 - maxInput) }
        let sumExp = expValues.reduce(0, +)
        return expValues.map { $0 / sumExp }
    }
}
