# QualiaKit

![Platform](https://img.shields.io/badge/platform-iOS%2016%2B%20%7C%20macOS%2013%2B-lightgrey)
![Language](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

**Feel the meaning of text.** QualiaKit bridges the gap between digital semantics and human perception. It analyzes the sentiment of user input in real-time and triggers corresponding haptic feedback.
Turn flat text into a tactile experience. QualiaKit triggers haptic feedback based on real-time text sentiment analysis. It provides on-device interpretation of user input to bridge digital semantics and human perception.

---

```swift
TextField("Enter text", text: $userInput)
    .qualiaFeedback(trigger: $userInput)
```

That's it. **One modifier.** Your users now feel emotions as they type.

---

## Why QualiaKit?

Most haptic libraries require manual triggering. QualiaKit makes haptics semantic.
Privacy First: 100% on-device analysis. No data ever leaves the user's phone.

Modular Architecture:
Qualia (Core): Uses NLTagger. Ultra-lightweight (0 extra size).
QualiaBert: Optional add-on for transformer-based accuracy.

---

## Installation

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

## Quick Start

### SwiftUI (Zero Config)

```swift
import SwiftUI
import Qualia

struct ContentView: View {
    @State private var text = ""

    var body: some View {
        TextField("Type something...", text: $text)
            .qualiaFeedback(trigger: $text)
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

## Advanced Usage

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

## Bring Your Own Model

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

## Testing

```bash
swift test

# With real BERT model
export QUALIAKIT_TEST_MODEL_PATH=/path/to/model.mlmodelc
swift test
```

---

## Requirements

- iOS 16.0+ / macOS 13.0+
- Swift 5.9+
- Xcode 15.0+

## License

MIT License. See [LICENSE](LICENSE) for details.
