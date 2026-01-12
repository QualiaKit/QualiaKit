import XCTest
@testable import Qualia

/// Tests for keyword configuration loading from plist and custom overrides
final class KeywordConfigurationTests: XCTestCase {
    
    // MARK: - Keyword Loading Tests
    
    func testLoadKeywordsFromBundle_UsesFallbackWhenNoPlist() {
        // Since tests run without app bundle plist, this should use fallback
        let keywords = QualiaConfiguration.loadKeywordsFromBundle()
        
        // Verify fallback keywords are loaded
        XCTAssertFalse(keywords.intense.isEmpty, "Fallback intense keywords should not be empty")
        XCTAssertTrue(keywords.intense.contains("blood"), "Should contain English intense keyword")
        XCTAssertTrue(keywords.intense.contains("кровь"), "Should contain Russian intense keyword")
        
        // Verify mysterious keywords are loaded
        XCTAssertFalse(keywords.mysterious.isEmpty, "Fallback mysterious keywords should not be empty")
        XCTAssertTrue(keywords.mysterious.contains("mystery"), "Should contain English mysterious keyword")
        XCTAssertTrue(keywords.mysterious.contains("тайна"), "Should contain Russian mysterious keyword")
    }
    
    func testStandardConfigurationLoadsKeywords() {
        // Test that standard configuration loads keywords (from plist or fallback)
        let config = QualiaConfiguration.standard
        
        // Verify keywords are populated
        XCTAssertFalse(config.intenseKeywords.isEmpty, "Standard config should have intense keywords")
        XCTAssertFalse(config.mysteriousKeywords.isEmpty, "Standard config should have mysterious keywords")
        
        // Verify some expected keywords (from fallback)
        XCTAssertTrue(config.intenseKeywords.contains("attack"))
        XCTAssertTrue(config.mysteriousKeywords.contains("shadow"))
    }
    
    // MARK: - Custom Keyword Override Tests
    
    func testCustomIntenseKeywords() {
        // Test that custom keywords can be provided
        let customIntense = ["danger", "warning", "alert"]
        let config = QualiaConfiguration(intenseKeywords: customIntense)
        
        XCTAssertEqual(config.intenseKeywords, customIntense, "Should use custom intense keywords")
        // Mysterious keywords should still load from bundle
        XCTAssertFalse(config.mysteriousKeywords.isEmpty, "Should still have default mysterious keywords")
    }
    
    func testCustomMysteriousKeywords() {
        // Test that custom mysterious keywords can be provided
        let customMysterious = ["enigma", "puzzle", "riddle"]
        let config = QualiaConfiguration(mysteriousKeywords: customMysterious)
        
        XCTAssertEqual(config.mysteriousKeywords, customMysterious, "Should use custom mysterious keywords")
        // Intense keywords should still load from bundle
        XCTAssertFalse(config.intenseKeywords.isEmpty, "Should still have default intense keywords")
    }
    
    func testCustomBothKeywordSets() {
        // Test that both keyword sets can be customized simultaneously
        let customIntense = ["danger", "warning"]
        let customMysterious = ["enigma", "puzzle"]
        let config = QualiaConfiguration(
            intenseKeywords: customIntense,
            mysteriousKeywords: customMysterious
        )
        
        XCTAssertEqual(config.intenseKeywords, customIntense)
        XCTAssertEqual(config.mysteriousKeywords, customMysterious)
    }
    
    func testEmptyCustomKeywords() {
        // Test that empty arrays can be provided (disabling keyword detection)
        let config = QualiaConfiguration(
            intenseKeywords: [],
            mysteriousKeywords: []
        )
        
        XCTAssertTrue(config.intenseKeywords.isEmpty, "Should accept empty intense keywords")
        XCTAssertTrue(config.mysteriousKeywords.isEmpty, "Should accept empty mysterious keywords")
    }
    
    // MARK: - Integration Tests with QualiaClient
    
    func testClientUsesConfigKeywords() async {
        // Test that QualiaClient correctly uses keywords from config
        let config = QualiaConfiguration.standard
        let client = QualiaClient(config: config)
        
        // Test intense keyword detection
        let (intenseEmotion, _) = await client.analyze("There is blood everywhere")
        XCTAssertEqual(intenseEmotion, .intense, "Should detect intense emotion from keyword")
        
        // Test mysterious keyword detection
        let (mysteriousEmotion, _) = await client.analyze("A shadow appeared in the mystery")
        XCTAssertEqual(mysteriousEmotion, .mysterious, "Should detect mysterious emotion from keyword")
    }
    
    func testClientWithCustomKeywords() async {
        // Test that QualiaClient works with custom keywords
        let config = QualiaConfiguration(
            intenseKeywords: ["urgent", "critical"],
            mysteriousKeywords: ["strange", "weird"]
        )
        let client = QualiaClient(config: config)
        
        // Test custom intense keyword
        let (intenseEmotion, _) = await client.analyze("This is urgent")
        XCTAssertEqual(intenseEmotion, .intense, "Should detect custom intense keyword")
        
        // Test custom mysterious keyword
        let (mysteriousEmotion, _) = await client.analyze("Something strange happened")
        XCTAssertEqual(mysteriousEmotion, .mysterious, "Should detect custom mysterious keyword")
        
        // Test that old keywords no longer trigger
        let (oldKeywordEmotion, _) = await client.analyze("blood")
        XCTAssertNotEqual(oldKeywordEmotion, .intense, "Should not detect old intense keyword")
    }
    
    func testClientWithDisabledKeywords() async {
        // Test that QualiaClient works with keyword detection disabled
        let config = QualiaConfiguration(
            intenseKeywords: [],
            mysteriousKeywords: []
        )
        let client = QualiaClient(config: config)
        
        // Even with keywords present, should fall back to sentiment analysis
        let (emotion1, _) = await client.analyze("blood")
        XCTAssertNotEqual(emotion1, .intense, "Should not detect intense with empty keywords")
        
        let (emotion2, _) = await client.analyze("mystery")
        XCTAssertNotEqual(emotion2, .mysterious, "Should not detect mysterious with empty keywords")
    }
    
    // MARK: - Keyword Detection Behavior Tests
    
    func testKeywordMatchingIsCaseInsensitive() async {
        // Test that keyword matching is case-insensitive
        let config = QualiaConfiguration.standard
        let client = QualiaClient(config: config)
        
        let (emotion1, _) = await client.analyze("BLOOD")
        let (emotion2, _) = await client.analyze("Blood")
        let (emotion3, _) = await client.analyze("blood")
        
        XCTAssertEqual(emotion1, .intense)
        XCTAssertEqual(emotion2, .intense)
        XCTAssertEqual(emotion3, .intense)
    }
    
    func testKeywordPartialMatching() async {
        // Test that keywords match as substrings
        let config = QualiaConfiguration.standard
        let client = QualiaClient(config: config)
        
        // "attack" should match "attacked", "attacking", etc.
        let (emotion, _) = await client.analyze("They attacked us")
        XCTAssertEqual(emotion, .intense, "Should match keyword as substring")
    }
    
    func testMultilingualKeywords() async {
        // Test that both Russian and English keywords work
        let config = QualiaConfiguration.standard
        let client = QualiaClient(config: config)
        
        // Russian intense keyword
        let (emotion1, _) = await client.analyze("кровь")
        XCTAssertEqual(emotion1, .intense, "Should detect Russian intense keyword")
        
        // Russian mysterious keyword
        let (emotion2, _) = await client.analyze("тайна")
        XCTAssertEqual(emotion2, .mysterious, "Should detect Russian mysterious keyword")
    }
    
    // MARK: - Fallback Behavior Tests
    
    func testFallbackKeywordsExist() {
        // Test that fallback keywords are defined (when plist is not in app bundle)
        // This is tested indirectly by ensuring loadKeywordsFromBundle always returns values
        let keywords = QualiaConfiguration.loadKeywordsFromBundle()
        
        // Since test bundle doesn't have the plist, should use fallback keywords
        XCTAssertFalse(keywords.intense.isEmpty, "Should have fallback intense keywords")
        XCTAssertFalse(keywords.mysterious.isEmpty, "Should have fallback mysterious keywords")
        
        // Verify expected fallback keywords
        XCTAssertTrue(keywords.intense.contains("blood"))
        XCTAssertTrue(keywords.intense.contains("death"))
        XCTAssertTrue(keywords.mysterious.contains("mystery"))
        XCTAssertTrue(keywords.mysterious.contains("secret"))
    }
    
    // MARK: - Configuration Preset Tests
    
    func testAllPresetsHaveKeywords() {
        // Test that all configuration presets have keywords loaded
        let presets: [QualiaConfiguration] = [
            .standard,
            .silent,
            .testing,
            .accessibility
        ]
        
        for preset in presets {
            XCTAssertFalse(preset.intenseKeywords.isEmpty, "Preset should have intense keywords")
            XCTAssertFalse(preset.mysteriousKeywords.isEmpty, "Preset should have mysterious keywords")
        }
    }
}
