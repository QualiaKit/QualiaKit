import Foundation
import XCTest
import QualiaKit
import QualiaTesting
import QualiaExamples

@MainActor
final class PilotTests: XCTestCase {
    func testShadowDoesNotDoublePrimaryPlaybackAndSuspensionDoesNotReplay() async throws {
        let renderer = RecordingHapticRenderer()
        let session = try await LivingStory.makeSession(renderer: renderer)
        let comparison = try await PilotComparison(primary: session, shadowAnalyzer: LivingStory.analyzer(),
                                                   shadowConfiguration: LivingStory.configuration())
        let result = try await comparison.process(LivingStory.input("build"))
        XCTAssertEqual(result.primaryCommandCount, 1)
        XCTAssertEqual(result.shadowCommandCount, 1)
        XCTAssertEqual(renderer.commands.count, 1, "Only the primary renderer receives the start")
        try await comparison.suspend()
        XCTAssertTrue(renderer.activeEffects.isEmpty)
        let afterStop = renderer.commands.count
        try await comparison.resume()
        XCTAssertEqual(renderer.commands.count, afterStop, "Resume must not replay either stream")
        try await comparison.reset()
    }

    func testFeedbackRequiresConsentAndExportsOnlyClosedSchemaAndMetadataHashes() throws {
        let secret = "arbitrary installation metadata must not leak"
        let identity = PilotFeedback.BuildIdentity(
            runtime: .init(identifier: secret, version: "runtime-private-version"),
            model: .init(identifier: secret, version: "model-private-version"),
            policy: .init(identifier: secret, version: "policy-private-version"),
            effect: .init(identifier: secret, version: "effect-private-version"))
        XCTAssertNil(PilotFeedback.make(consented: false, judgment: .inappropriate,
                                        hapticsDisabled: true, identity: identity))
        let feedback = try XCTUnwrap(PilotFeedback.make(consented: true, judgment: .inappropriate,
                                                        hapticsDisabled: true, identity: identity))
        let data = try JSONEncoder().encode(feedback)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["schemaVersion", "judgment", "hapticsDisabled", "runtime", "model", "policy", "effect"])
        XCTAssertEqual(json["judgment"] as? String, "inappropriate")
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        for field in ["runtime", "model", "policy", "effect"] {
            let metadata = try XCTUnwrap(json[field] as? [String: String])
            XCTAssertEqual(Set(metadata.keys), ["identifier", "version"])
            for value in metadata.values { XCTAssertNotNil(value.range(of: "^[a-f0-9]{64}$", options: .regularExpression)) }
        }
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains(secret))
        XCTAssertFalse(text.contains("private-version"))
    }
}
