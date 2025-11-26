# QualiaKit 🧠⚡️

![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20macOS-lightgrey)
![Language](https://img.shields.io/badge/language-Swift%205.9-orange)
![License](https://img.shields.io/badge/license-MIT-blue)
[![CI](https://github.com/QualiaKit/QualiaKit/workflows/CI/badge.svg)](https://github.com/QualiaKit/QualiaKit/actions)

**QualiaKit** is an open-source framework designed to bridge the gap between digital text and human sensory perception. By combining **Natural Language Processing (BERT)** with **Haptic Feedback**, it allows users to "feel" the semantic weight of information.

> "Translating Sense (Meaning) into Sense (Feeling)."

## 🌟 Key Features

- **Embodied Semantics:** Transforms abstract text metrics (sentiment, aggression, suspense) into physical tactile patterns.
- **On-Device Intelligence:** Uses a highly optimized, pure-Swift implementation of WordPiece tokenization and CoreML BERT inference. Zero server dependency, 100% privacy.
- **Modular Architecture:**
  - `NLP`: BERT tokenization and sentiment analysis
  - `Haptics`: Core Haptics integration with heartbeat patterns
  - `QualiaClient`: Unified interface for semantic-haptic synthesis

## 📦 Installation

Add QualiaKit to your project via Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/QualiaKit.git", from: "1.0.0")
]
```

## 🚀 Quick Start

```swift
import QualiaKit

// Initialize the client with your BERT model and vocabulary
let vocabURL = Bundle.main.url(forResource: "vocab", withExtension: "txt")!
let modelURL = Bundle.main.url(forResource: "bert_sentiment", withExtension: "mlmodel")!

let client = try QualiaClient(vocabURL: vocabURL, modelURL: modelURL)

// Analyze text and trigger haptic feedback
let (emotion, score) = await client.analyzeAndFeel("This is an amazing discovery!")

print("Emotion: \(emotion), Score: \(score)")
// The device will vibrate based on the detected emotion
```

### Customizing Keywords

```swift
// Add custom keywords for intense emotions
client.intenseKeywords.append("danger")
client.intenseKeywords.append("urgent")

// Add custom mysterious keywords
client.mysteriousKeywords.append("enigma")
```

## 🎮 Use Cases

- **Interactive Storytelling**: Add tactile feedback to your narrative apps
- **Accessibility**: Enhance text-to-speech with haptic cues
- **Gaming**: Real-time emotional feedback during gameplay
- **Mental Health**: Meditation and anxiety relief through haptic patterns
- **Education**: Multi-sensory language learning

## 🧪 Testing

Run tests:

```bash
swift test
```

Run tests with a real BERT model:

```bash
export QUALIAKIT_TEST_MODEL_PATH=/path/to/your/model.mlmodel
swift test
```

Run SwiftLint:

```bash
swiftlint lint
```

### Mock Provider for Testing

Use `MockHapticProvider` in your tests:

```swift
import XCTest
@testable import QualiaKit

let mockProvider = MockHapticProvider()
mockProvider.play(.positive)

XCTAssertEqual(mockProvider.playedEmotions.count, 1)
XCTAssertEqual(mockProvider.emotionCounts[.positive], 1)
```

## 🛠 Requirements

- iOS 16.0+ / macOS 13.0+
- Swift 5.9+
- Xcode 15.0+

## 📖 Documentation

- [Contributing Guidelines](CONTRIBUTING.md)
- API Documentation (coming soon)

## 🤝 Contributing

We welcome contributions! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting a PR.

### Quick Checklist

- [ ] Code builds and tests pass
- [ ] SwiftLint checks pass
- [ ] New features include tests
- [ ] Public APIs are documented

## 📄 License

QualiaKit is released under the MIT License. See [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

Built with ❤️ for creating more embodied digital experiences.
