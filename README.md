# QualiaKit 🧠⚡️

![Platform](https://img.shields.io/badge/platform-iOS%2016%2B%20%7C%20macOS%2013%2B-lightgrey)
![Language](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-blue)
![Zero Dependencies](https://img.shields.io/badge/dependencies-zero-green)
![SwiftUI Ready](https://img.shields.io/badge/SwiftUI-ready-blue)
![Pluggable AI](https://img.shields.io/badge/AI-pluggable-purple)

**Feel the meaning of text.** QualiaKit transforms sentiment analysis into tactile haptic feedback, bridging digital semantics and human perception.

---

## ✨ The Magic Line

```swift
TextField("Enter text", text: $userInput)
    .qualiaFeedback(trigger: $userInput)
```

That's it. **One modifier.** Your users now feel emotions as they type.

---

## 🎯 Why QualiaKit?

| Feature              | Qualia (Core)    | QualiaBert (Add-on)       |
| -------------------- | ---------------- | ------------------------- |
| **Bundle Size**      | **0 bytes** ✨   | ~100 MB                   |
| **Sentiment Engine** | iOS NLTagger     | BERT (CoreML)             |
| **Accuracy**         | Good             | Excellent (Russian)       |
| **Languages**        | 50+              | 50+ (BERT for RU)         |
| **Dependencies**     | Zero             | Qualia                    |
| **Use Case**         | Lightweight apps | Enterprise, high accuracy |

**You choose.** Need zero bloat? Use Qualia. Need maximum accuracy? Add QualiaBert.

---

## 🚀 Installation

### Option 1: Lightweight (Recommended)

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/QualiaKit/QualiaKit.git", from: "2.0.0")
]

targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "Qualia", package: "QualiaKit")
        ]
    )
]
```

### Option 2: Heavy Duty (High Accuracy)

```swift
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "Qualia", package: "QualiaKit"),
            .product(name: "QualiaBert", package: "QualiaKit")  // Add this
        ]
    )
]
```

---

## 💡 Quick Start

### SwiftUI (Zero Config)

```swift
import SwiftUI
import Qualia

struct ContentView: View {
    @State private var text = ""

    var body: some View {
        TextField("Type something...", text: $text)
            .qualiaFeedback(trigger: $text)  // ← Magic happens here
    }
}
```

**Done.** The device vibrates based on sentiment as the user types.

### Programmatic API

```swift
import Qualia

// Initialize (uses NLTagger by default)
let client = QualiaClient()

// Analyze + haptic feedback
let (emotion, score) = await client.analyzeAndFeel("I'm so happy!")
// emotion: .positive, score: 0.8

// Analysis only
let (emotion, score) = await client.analyze("Neutral text")

// Manual haptic control
client.feel(.intense)
```

### With BERT (High Accuracy)

```swift
import Qualia
import QualiaBert

// Initialize BERT provider
let provider = try BertProvider(
    vocabURL: Bundle.main.url(forResource: "vocab", withExtension: "txt")!,
    modelURL: Bundle.main.url(forResource: "rusentiment", withExtension: "mlmodelc")!
)

let client = QualiaClient(provider: provider)
let (emotion, score) = await client.analyzeAndFeel("Это потрясающе!")
```

---

## 🏗️ Architecture

QualiaKit follows an **enterprise-grade plugin architecture**, inspired by Firebase and Google ML Kit.

```
┌─────────────────────────────────────────┐
│         Your App (SwiftUI/UIKit)        │
└────────────────┬────────────────────────┘
                 │
     ┌───────────▼──────────┐
     │   QualiaClient       │  ← Unified API
     └───────────┬──────────┘
                 │
     ┌───────────▼──────────┐
     │  SentimentProvider   │  ← Protocol
     └───────────┬──────────┘
                 │
     ┌───────────┴───────────────┐
     │                           │
┌────▼────────┐         ┌────────▼──────┐
│ NLTagger    │         │ BertProvider  │
│ (Built-in)  │         │ (Optional)    │
└─────────────┘         └───────────────┘
     0 bytes                 ~100 MB
```

### Design Patterns Used

- **Strategy Pattern**: Pluggable `SentimentProvider`
- **Dependency Injection**: Provider-based initialization
- **Adapter Pattern**: `NLTaggerProvider` wraps iOS APIs
- **Composite Pattern**: `BertProvider` falls back to NLTagger for non-Russian text

---

## 🎨 Advanced Usage

### Custom Configuration

```swift
let config = QualiaConfiguration(
    autoPlayHaptics: true,
    enableHeartbeat: false,
    hapticIntensity: 0.7,
    hapticDelay: 0.2
)

let client = QualiaClient(config: config)
```

**Presets:**

- `.standard` - Default behavior
- `.silent` - Analysis only, no haptics
- `.testing` - Optimized for unit tests
- `.accessibility` - Reduced intensity (50%)

### Custom Keywords

```swift
client.intenseKeywords.append("urgent")
client.mysteriousKeywords.append("secret")

let (emotion, _) = await client.analyze("This is urgent!")
// emotion: .intense (keyword match)
```

### Environment Injection (SwiftUI)

```swift
let customClient = QualiaClient(provider: MyCustomProvider())

ContentView()
    .environment(\.qualiaClient, customClient)
```

---

## 🔌 Bring Your Own Model

QualiaKit is **fully extensible**. Use any sentiment model:

```swift
import Qualia

struct MyCustomProvider: SentimentProvider {
    func analyzeSentiment(_ text: String, language: NLLanguage) async throws -> Double {
        // Your custom ML model, API call, or heuristic
        return customScore  // -1.0 to 1.0
    }
}

let client = QualiaClient(provider: MyCustomProvider())
```

**Use cases:**

- Enterprise models (banking, healthcare)
- Domain-specific sentiment (finance, legal)
- Multi-modal analysis (text + audio)
- Cloud APIs (OpenAI, Anthropic)

---

## 🎮 Real-World Applications

| Industry          | Use Case                                 |
| ----------------- | ---------------------------------------- |
| **Storytelling**  | Haptic feedback in interactive novels    |
| **Accessibility** | Tactile cues for visually impaired users |
| **Gaming**        | Real-time emotional feedback             |
| **Mental Health** | Meditation apps with haptic guidance     |
| **Education**     | Multi-sensory language learning          |
| **Enterprise**    | Secure, on-device sentiment analysis     |

---

## 🧪 Testing

```bash
# Run all tests
swift test

# With real BERT model
export QUALIAKIT_TEST_MODEL_PATH=/path/to/model.mlmodelc
swift test

# SwiftLint
swiftlint lint
```

**Test Results:** ✅ 44 tests, 0 failures

---

## 📊 Performance

| Metric          | Qualia (NLTagger) | QualiaBert             |
| --------------- | ----------------- | ---------------------- |
| Bundle addition | **0 bytes**       | ~100 MB                |
| Inference time  | ~5ms              | ~20ms                  |
| Languages       | 50+               | 50+ (BERT for Russian) |
| Privacy         | 100% on-device    | 100% on-device         |

---

## 🛡️ Requirements

- iOS 16.0+ / macOS 13.0+
- Swift 5.9+
- Xcode 15.0+

---

## 📖 Documentation

- [API Documentation](https://qualiakit.github.io/QualiaKit) _(coming soon)_
- [Migration Guide v1 → v2](MIGRATION.md) _(coming soon)_
- [Contributing Guidelines](CONTRIBUTING.md)

---

## 🤝 Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

**Quick checklist:**

- [ ] Tests pass (`swift test`)
- [ ] SwiftLint clean (`swiftlint lint`)
- [ ] Public APIs documented
- [ ] New features include tests

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

Built with ❤️ to create **embodied digital experiences**.

> "Translating Sense (Meaning) into Sense (Feeling)."

---

## ⭐️ Star History

[![Star History Chart](https://api.star-history.com/svg?repos=QualiaKit/QualiaKit&type=Date)](https://star-history.com/#QualiaKit/QualiaKit&Date)

---

**Made with Swift** • **Zero Dependencies** • **Privacy First** • **Pluggable AI**
