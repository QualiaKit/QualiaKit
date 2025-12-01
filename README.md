# QualiaKit

![Platform](https://img.shields.io/badge/platform-iOS%2016%2B%20%7C%20macOS%2013%2B-lightgrey)
![Language](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

**Semantic Haptic Feedback Engine for iOS.**

QualiaKit bridges the gap between digital semantics and human perception. It analyzes the sentiment of user input in real-time and triggers corresponding haptic feedback, turning flat text into a tactile experience.

---

### The 30-Second Hook

```swift
TextField("Enter text", text: $userInput)
    .qualiaFeedback(trigger: $userInput)
````

That's it. **One modifier.** Your users now feel the emotional tone of their text as they type.

-----

## Key Features

  * **⚡️ Zero Latency:** Optimized for real-time typing loops.
  * **🔒 Privacy First:** 100% on-device analysis. No data ever leaves the user's phone.
  * **🧩 Modular Architecture:**
      * **Qualia (Core):** Uses Apple's `NLTagger`. Ultra-lightweight (0 extra size).
      * **QualiaBert:** Optional add-on for transformer-based accuracy using CoreML.
  * **🎛 Extensible:** Bring your own ML model or heuristic provider easily.

-----

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "[https://github.com/QualiaKit/QualiaKit.git](https://github.com/QualiaKit/QualiaKit.git)", from: "2.0.0")
]
```

**Choose your target configuration:**

#### Option 1: Lightweight (Recommended)

Use Apple's built-in NLP. No extra models required.

```swift
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "Qualia", package: "QualiaKit")
        ]
    )
]
```

#### Option 2: Heavy Duty (High Accuracy)

Use a BERT-based transformer model.

```swift
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "Qualia", package: "QualiaKit"),
            .product(name: "QualiaBert", package: "QualiaKit") // Add the extension
        ]
    )
]
```

-----

## Usage

### 1\. SwiftUI (Zero Config)

The easiest way to integrate. The device vibrates based on sentiment intensity automatically.

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

### 2\. Programmatic API

For more control or non-UI contexts.

```swift
import Qualia

// Initialize (uses NLTagger by default)
let client = QualiaClient()

// Analyze only
let (emotion, score) = await client.analyze("I am absolutely furious!")
print(emotion) // Output: .negative

// Analyze + Trigger Haptics manually
let (emotion, score) = await client.analyzeAndFeel("This is wonderful news.")
```

### 3\. Using BERT (High Accuracy)

*Note: You must provide your own CoreML model file or download a compatible one.*
```swift
import Qualia
import QualiaBert

// Initialize BERT provider with your local resources
let provider = try BertProvider(
    vocabURL: Bundle.main.url(forResource: "bert-vocab", withExtension: "txt")!,
    modelURL: Bundle.main.url(forResource: "sentiment-model", withExtension: "mlmodelc")!
)

// Inject the provider into the client
let client = QualiaClient(provider: provider)
let (emotion, score) = await client.analyzeAndFeel("This is absolutely amazing!")
```
-----

## Advanced Customization

### Configuration

Fine-tune the haptic experience.

```swift
let config = QualiaConfiguration(
    autoPlayHaptics: true,
    enableHeartbeat: false, // Disables background "pulse"
    hapticIntensity: 0.7,   // Scale vibration strength
    hapticDelay: 0.1        // Debounce time
)

let client = QualiaClient(config: config)
```

### Bring Your Own Model

QualiaKit is model-agnostic. Implement `SentimentProvider` to connect any backend (e.g., OpenAI API, TFLite, Custom CoreML).

```swift
import Qualia

struct GPTProvider: SentimentProvider {
    func analyzeSentiment(_ text: String, language: NLLanguage) async throws -> Double {
        // Call your external API or custom logic here
        return await myCustomAnalyzer.predict(text) // Returns -1.0 to 1.0
    }
}

let client = QualiaClient(provider: GPTProvider())
```

-----

## Requirements

  - iOS 16.0+ / macOS 13.0+
  - Swift 5.9+
  - Xcode 15.0+

## License

QualiaKit is available under the MIT license. See the [LICENSE](https://www.google.com/search?q=LICENSE) file for more info.

```
