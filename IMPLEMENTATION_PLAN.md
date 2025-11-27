QualiaKit v2.0 - API Redesign Plan
🎯 Цель
Сделать API библиотеки более explicit и гибким, разделив анализ и haptic feedback, добавив конфигурацию.

📋 Phase 1: Core Configuration
1.1 Создать QualiaConfiguration.swift
Файл: src/Core/QualiaConfiguration.swift

import Foundation
import CoreGraphics
public struct QualiaConfiguration {
    /// Automatically play haptics when using analyzeAndFeel()
    public var autoPlayHaptics: Bool
    
    /// Enable heartbeat pattern for intense emotions
    public var enableHeartbeat: Bool
    
    /// Haptic intensity multiplier (0.0 - 1.0)
    public var hapticIntensity: CGFloat
    
    /// Delay before playing haptics (in seconds)
    public var hapticDelay: TimeInterval
    
    public init(
        autoPlayHaptics: Bool = true,
        enableHeartbeat: Bool = true,
        hapticIntensity: CGFloat = 1.0,
        hapticDelay: TimeInterval = 0.0
    ) {
        self.autoPlayHaptics = autoPlayHaptics
        self.enableHeartbeat = enableHeartbeat
        self.hapticIntensity = hapticIntensity
        self.hapticDelay = hapticDelay
    }
    
    // MARK: - Presets
    
    /// Standard configuration with auto-haptics enabled
    public static let standard = QualiaConfiguration()
    
    /// Silent mode - no automatic haptics
    public static let silent = QualiaConfiguration(autoPlayHaptics: false, enableHeartbeat: false)
    
    /// Testing mode - analysis only
    public static let testing = QualiaConfiguration(autoPlayHaptics: false, enableHeartbeat: false)
    
    /// Accessibility mode - reduced haptic intensity
    public static let accessibility = QualiaConfiguration(hapticIntensity: 0.5)
}
📋 Phase 2: Refactor QualiaClient
2.1 Обновить 
QualiaClient.swift
Изменения:

2.1.1 Добавить configuration property
public class QualiaClient {
    // ... existing properties ...
    
    private let config: QualiaConfiguration
    
    // ИЗМЕНИТЬ: Добавить config в init
    public init(
        vocabURL: URL, 
        modelURL: URL,
        config: QualiaConfiguration = .standard
    ) throws {
        self.tokenizer = try BertTokenizer(vocabURL: vocabURL)
        self.modelWrapper = try BertModelWrapper(modelURL: modelURL)
        self.haptics = HapticEngine.shared
        self.config = config
    }
2.1.2 Переименовать и разделить методы
// НОВЫЙ МЕТОД: Только анализ (без haptics)
public func analyze(_ text: String) async -> (SenseEmotion, Double) {
    return await performAnalysis(text)
}
// ИЗМЕНИТЬ: analyzeAndFeel теперь ДЕЙСТВИТЕЛЬНО делает haptics
public func analyzeAndFeel(_ text: String) async -> (SenseEmotion, Double) {
    let (emotion, score) = await performAnalysis(text)
    
    // Play haptics if configured
    if config.autoPlayHaptics {
        await playHapticFeedback(for: emotion)
    }
    
    return (emotion, score)
}
// НОВЫЙ МЕТОД: Явно trigger haptics для любой эмоции
@MainActor
public func feel(_ emotion: SenseEmotion) {
    playHapticFeedback(for: emotion)
}
// ПРИВАТНЫЙ: Вынести общую логику анализа
private func performAnalysis(_ text: String) async -> (SenseEmotion, Double) {
    let lowercased = text.lowercased()
    if intenseKeywords.contains(where: { lowercased.contains($0) }) {
        return (.intense, 0.0)
    }
    if mysteriousKeywords.contains(where: { lowercased.contains($0) }) {
        return (.mysterious, 0.0)
    }
    let score = await calculateSentimentScore(text)
    var emotion: SenseEmotion = .neutral
    if score > 0.2 { emotion = .positive } 
    else if score < -0.2 { emotion = .negative }
    return (emotion, score)
}
// ПРИВАТНЫЙ: Централизованная логика haptics
@MainActor
private func playHapticFeedback(for emotion: SenseEmotion) {
    // Apply delay if configured
    if config.hapticDelay > 0 {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(config.hapticDelay * 1_000_000_000))
            HapticEngine.shared.play(for: emotion)
        }
    } else {
        HapticEngine.shared.play(for: emotion)
    }
    
    // Handle heartbeat for intense emotions
    if config.enableHeartbeat {
        HapticEngine.shared.updateHeartbeat(shouldPlay: emotion == .intense)
    }
}
📋 Phase 3: Update HapticEngine (Optional Enhancement)
3.1 Добавить intensity support в 
HapticEngine.swift
@MainActor
public final class HapticEngine: ObservableObject {
    public static let shared = HapticEngine()
    
    // НОВОЕ: Настраиваемая интенсивность
    public var baseIntensity: CGFloat = 1.0
    
    private init() {
        prepareHaptics()
    }
    public func prepareHaptics() {
        HapticManager.shared.prepare()
    }
    // ИЗМЕНИТЬ: Добавить intensity параметр
    public func play(for emotion: SenseEmotion, intensity: CGFloat? = nil) {
        let finalIntensity = intensity ?? baseIntensity
        HapticManager.shared.play(emotion, intensity: finalIntensity)
    }
    public func updateHeartbeat(shouldPlay: Bool) {
        if shouldPlay {
            HapticManager.shared.startHeartbeat()
        } else {
            HapticManager.shared.stopHeartbeat()
        }
    }
}
3.2 Update 
HapticProvider.swift
 protocol
public protocol HapticProvider {
    func prepare()
    func play(_ emotion: SenseEmotion, intensity: CGFloat)
    func startHeartbeat()
    func stopHeartbeat()
}
3.3 Update 
IOSHapticProvider.swift
public func play(_ emotion: SenseEmotion, intensity: CGFloat = 1.0) {
    switch emotion {
    case .positive: notification.notificationOccurred(.success)
    case .negative: rigid.impactOccurred()
    case .intense: heavy.impactOccurred(intensity: intensity)
    case .mysterious: soft.impactOccurred(intensity: 0.8 * intensity)
    case .neutral: light.impactOccurred()
    }
}
📋 Phase 4: Backward Compatibility (Опционально)
4.1 Добавить deprecated методы с предупреждениями
// В QualiaClient.swift
@available(*, deprecated, renamed: "analyze(_:)", message: "Use analyze() for analysis without haptics, or analyzeAndFeel() for analysis with automatic haptics")
public func analyzeSentiment(_ text: String) async -> (SenseEmotion, Double) {
    return await analyze(text)
}
📋 Phase 5: Testing
5.1 Обновить QualiaClientTests.swift
Создать новый файл или обновить существующий:

import XCTest
@testable import QualiaKit
final class QualiaClientConfigTests: XCTestCase {
    
    func testSilentConfigurationDoesNotPlayHaptics() async throws {
        let mockProvider = MockHapticProvider()
        
        let client = try QualiaClient(
            vocabURL: vocabURL,
            modelURL: modelURL,
            config: .silent
        )
        
        _ = await client.analyzeAndFeel("Happy text")
        
        // Haptics should NOT be played in silent mode
        XCTAssertEqual(mockProvider.playedEmotions.count, 0)
    }
    
    func testStandardConfigurationPlaysHaptics() async throws {
        let client = try QualiaClient(
            vocabURL: vocabURL,
            modelURL: modelURL,
            config: .standard
        )
        
        _ = await client.analyzeAndFeel("Happy text")
        
        // Should play haptics with standard config
        // (Verify through HapticEngine.shared mock)
    }
    
    func testAnalyzeNeverPlaysHaptics() async throws {
        let client = try QualiaClient(
            vocabURL: vocabURL,
            modelURL: modelURL,
            config: .standard
        )
        
        _ = await client.analyze("Happy text")
        
        // analyze() should NEVER play haptics regardless of config
        // (Verify no haptics played)
    }
    
    func testFeelExplicitlyPlaysHaptics() async throws {
        let client = try QualiaClient(
            vocabURL: vocabURL,
            modelURL: modelURL,
            config: .silent
        )
        
        await client.feel(.positive)
        
        // Should play haptics even with silent config
        // (Verify haptics played)
    }
}
5.2 Добавить тесты для Configuration presets
func testConfigurationPresets() {
    let standard = QualiaConfiguration.standard
    XCTAssertTrue(standard.autoPlayHaptics)
    XCTAssertTrue(standard.enableHeartbeat)
    XCTAssertEqual(standard.hapticIntensity, 1.0)
    
    let silent = QualiaConfiguration.silent
    XCTAssertFalse(silent.autoPlayHaptics)
    XCTAssertFalse(silent.enableHeartbeat)
    
    let accessibility = QualiaConfiguration.accessibility
    XCTAssertEqual(accessibility.hapticIntensity, 0.5)
}
📋 Phase 6: Documentation
6.1 Обновить 
README.md
Добавить секцию:

## 🎛️ Configuration
QualiaKit supports flexible configuration for different use cases:
### Quick Start (Standard Mode)
```swift
let client = try QualiaClient(vocabURL: vocabURL, modelURL: modelURL)
let (emotion, score) = await client.analyzeAndFeel(text)
// ✅ Haptics play automatically
Silent Mode (Analysis Only)
let client = try QualiaClient(
    vocabURL: vocabURL, 
    modelURL: modelURL,
    config: .silent
)
let (emotion, score) = await client.analyze(text)
// No haptics, just analysis
Custom Configuration
let config = QualiaConfiguration(
    autoPlayHaptics: true,
    enableHeartbeat: false,
    hapticIntensity: 0.7
)
let client = try QualiaClient(vocabURL: vocabURL, modelURL: modelURL, config: config)
API Methods
analyze(_:) - Pure analysis, no haptics
analyzeAndFeel(_:) - Analysis + automatic haptics (if config allows)
feel(_:) - Explicitly trigger haptics for any emotion
Configuration Presets
.standard - Default behavior with haptics
.silent - No automatic haptics or heartbeat
.testing - Optimized for unit tests
.accessibility - Reduced haptic intensity
### 6.2 Создать `MIGRATION.md`
```markdown
# Migration Guide: v1.x → v2.0
## Breaking Changes
### Method Behavior Changes
#### `analyzeAndFeel()` now ACTUALLY plays haptics
**v1.x:**
```swift
let (emotion, _) = await client.analyzeAndFeel(text)
HapticEngine.shared.play(for: emotion) // Manual haptics
v2.0:

let (emotion, _) = await client.analyzeAndFeel(text)
// ✅ Haptics play automatically (if config.autoPlayHaptics = true)
New analyze() method for haptics-free analysis
v2.0:

// Use analyze() when you don't want haptics
let (emotion, score) = await client.analyze(text)
// Use analyzeAndFeel() when you want automatic haptics
let (emotion, score) = await client.analyzeAndFeel(text)
Migration Steps
1. Review your usage
If you were calling haptics manually after analyzeAndFeel(), you have two options:

Option A: Use new behavior (recommended)

// Remove manual haptic calls
- let (emotion, _) = await client.analyzeAndFeel(text)
- HapticEngine.shared.play(for: emotion)
+ let (emotion, _) = await client.analyzeAndFeel(text)
Option B: Use silent config + manual control

let client = try QualiaClient(
    vocabURL: vocabURL,
    modelURL: modelURL,
    config: .silent
)
let (emotion, _) = await client.analyzeAndFeel(text)
HapticEngine.shared.play(for: emotion) // Still manual
2. Update initialization
Add config if you want non-default behavior:

let client = try QualiaClient(
    vocabURL: vocabURL,
    modelURL: modelURL,
    config: .standard // or .silent, .testing, etc.
)
3. Tests
For unit tests, use .testing or .silent config:

let client = try QualiaClient(
    vocabURL: vocabURL,
    modelURL: modelURL,
    config: .testing
)
---
## 📋 Phase 7: Update Chapter App
### 7.1 Обновить [PartyWritingViewModel.swift](file:///Users/anton/Desktop/party/Chapter/Chapter/ViewModels/PartyWritingViewModel.swift)
```swift
// В init()
guard let vocabURL = Bundle.main.url(forResource: "vocab", withExtension: "txt"),
      let modelURL = Bundle.main.url(forResource: "RuBSentimentModel", withExtension: "mlpackage")
else {
    fatalError("QualiaKit resources not found in bundle")
}
// ИЗМЕНИТЬ: Добавить config
self.qualiaClient = try! QualiaClient(
    vocabURL: vocabURL, 
    modelURL: modelURL,
    config: .standard // Явно указываем стандартное поведение
)
7.2 Упростить методы
// УБРАТЬ все ручные вызовы HapticEngine после analyzeAndFeel
// БЫЛО:
let (emotion, _) = await qualiaClient.analyzeAndFeel(text)
HapticEngine.shared.play(for: emotion) // Manual
// СТАЛО:
let (emotion, _) = await qualiaClient.analyzeAndFeel(text)
// ✅ Haptics автоматически!
7.3 Обновить applyEmotion
private func applyEmotion(_ newEmotion: SenseEmotion) {
    if newEmotion != emotion.currentEmotion {
        withAnimation {
            emotion.currentEmotion = newEmotion
        }
    }
    
    // УБРАТЬ: Heartbeat теперь управляется в analyzeAndFeel
    // HapticEngine.shared.updateHeartbeat(shouldPlay: newEmotion == .intense)
}
Note: Heartbeat будет автоматически управляться внутри playHapticFeedback в QualiaClient

📋 Phase 8: Version Bumping
8.1 Обновить 
Package.swift
// Изменить версию на 2.0.0
8.2 Git Tagging
git tag -a v2.0.0 -m "API redesign: Configuration support and explicit analyze/feel separation"
git push origin v2.0.0
8.3 Обновить CHANGELOG.md
# Changelog
## [2.0.0] - 2025-11-27
### Added
- `QualiaConfiguration` for flexible behavior control
- Configuration presets: `.standard`, `.silent`, `.testing`, `.accessibility`
- `analyze(_:)` method for haptics-free analysis
- `feel(_:)` method for explicit haptic triggering
- Haptic intensity support
- Configurable haptic delay
### Changed
- **BREAKING:** `analyzeAndFeel()` now automatically plays haptics (if `config.autoPlayHaptics = true`)
- **BREAKING:** Heartbeat management moved inside QualiaClient
- `QualiaClient.init()` now accepts optional `config` parameter
### Deprecated
- None (clean break in major version)
### Migration
See [MIGRATION.md](MIGRATION.md) for detailed migration guide
📋 Phase 9: Future Enhancements (Optional для v2.1+)
9.1 Observability через Combine
public class QualiaClient {
    public let emotionPublisher = PassthroughSubject<(SenseEmotion, Double), Never>()
    
    private func performAnalysis(_ text: String) async -> (SenseEmotion, Double) {
        // ... existing logic ...
        
        // Publish detected emotion
        emotionPublisher.send((emotion, score))
        
        return (emotion, score)
    }
}
9.2 Analytics/Logging Support
public protocol QualiaAnalytics {
    func emotionDetected(_ emotion: SenseEmotion, score: Double, text: String)
    func hapticPlayed(_ emotion: SenseEmotion)
}
public class QualiaClient {
    public var analytics: QualiaAnalytics?
}
9.3 Custom Haptic Patterns
public struct HapticPattern {
    let pulses: [(intensity: CGFloat, delay: TimeInterval)]
}
public class QualiaClient {
    public var customPatterns: [SenseEmotion: HapticPattern] = [:]
}
✅ Implementation Checklist
Core (Required)
 Create QualiaConfiguration.swift
 Update QualiaClient.init() with config parameter
 Add analyze() method
 Update analyzeAndFeel() to actually play haptics
 Add feel() method
 Extract performAnalysis() private method
 Extract playHapticFeedback() private method
Enhancement (Optional)
 Add intensity support to HapticEngine
 Update HapticProvider protocol
 Update IOSHapticProvider implementation
Testing
 Add QualiaClientConfigTests
 Test silent configuration
 Test standard configuration
 Test analyze() never plays haptics
 Test feel() always plays haptics
 Test configuration presets
Documentation
 Update 
README.md
 with configuration examples
 Create MIGRATION.md guide
 Update inline code documentation
 Add configuration JSDoc
Integration
 Update Chapter app to use new API
 Remove manual haptic calls
 Test in Chapter app
 Verify backward compatibility
Release
 Update version to 2.0.0
 Create git tag
 Update CHANGELOG.md
 Push to GitHub
🎯 Expected Outcome
Before:

let (emotion, _) = await client.analyzeAndFeel(text)
HapticEngine.shared.play(for: emotion)
HapticEngine.shared.updateHeartbeat(shouldPlay: emotion == .intense)
After:

let (emotion, _) = await client.analyzeAndFeel(text)
// ✅ Everything happens automatically!
Or for explicit control:

let (emotion, _) = await client.analyze(text)
if myCustomLogic(emotion) {
    await client.feel(.intense)
}
📊 Estimated Timeline
Phase	Complexity	Time Estimate
Phase 1: Configuration	Low	30 min
Phase 2: QualiaClient Refactor	Medium	1-2 hours
Phase 3: HapticEngine Enhancement	Low-Medium	1 hour
Phase 4: Backward Compatibility	Low	15 min
Phase 5: Testing	Medium	1-2 hours
Phase 6: Documentation	Low	30 min
Phase 7: Chapter Update	Medium	1 hour
Phase 8: Release	Low	15 min
Total: 5-7 hours for complete implementation with tests and docs.

💡 Tips
Start with Phase 1 and 2 - это core changes
Phase 3 опционален - можно сделать в v2.1
Не забудь тесты - они помогут с рефакторингом
Migration guide критичен - пользователям нужно понять breaking changes