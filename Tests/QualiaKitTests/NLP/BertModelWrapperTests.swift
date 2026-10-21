import XCTest
import QualiaBert

final class BertModelWrapperTests: XCTestCase {
    func testInvalidModelURL() {
        let invalidURL = URL(fileURLWithPath: "/nonexistent/model.mlmodel")
        XCTAssertThrowsError(try BertModelWrapper(modelURL: invalidURL))
    }
}

// Output correctness is covered by independent raw/transformed public-model
// fixtures in CoreMLRuntimeTests and protected committed-golden parity in
// CurrentModelContractTests. A local reimplementation of softmax and a
// range-only model smoke test cannot establish production correctness.
