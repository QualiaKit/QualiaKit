# QualiaKit

![Platform](https://img.shields.io/badge/platform-iOS%2016%2B%20%7C%20macOS%2013%2B-lightgrey)
![Language](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

![QualiaKit Demo](qualia-demo.gif)

QualiaKit analyzes the sentiment of text as users type and plays haptic feedback that matches the emotional tone. Everything runs on-device using Apple's `NLTagger` by default, so there's nothing to configure and no data leaves the phone.

If you need better accuracy, there's an optional `QualiaBert` module that runs a BERT model through CoreML instead.

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/QualiaKit/QualiaKit.git")
]
```

Then add `Qualia` to your target. This uses Apple's built-in NLP and doesn't bundle any extra models.

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "Qualia", package: "QualiaKit")
    ]
)
```

If you want the BERT-based provider, add `QualiaBert` as well:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "Qualia", package: "QualiaKit"),
        .product(name: "QualiaBert", package: "QualiaKit")
    ]
)
```

## Usage

### SwiftUI

The simplest integration is a single view modifier. It watches the bound text and triggers haptics automatically:

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

### Programmatic API

You can also use `QualiaClient` directly when you need more control or aren't in a SwiftUI context:

```swift
import Qualia

let client = QualiaClient()

// Analyze without triggering haptics
let (emotion, score) = await client.analyze("I am absolutely furious!")
print(emotion) // .negative

// Analyze and trigger haptics
let (emotion, score) = await client.analyzeAndFeel("This is wonderful news.")
```

### Using BERT

You'll need to provide your own CoreML model file or download a compatible one.

```swift
import Qualia
import QualiaBert

let provider = try BertProvider(
    vocabURL: Bundle.main.url(forResource: "bert-vocab", withExtension: "txt")!,
    modelURL: Bundle.main.url(forResource: "sentiment-model", withExtension: "mlmodelc")!
)

let client = QualiaClient(provider: provider)
let (emotion, score) = await client.analyzeAndFeel("This is absolutely amazing!")
```

## Configuration

You can adjust haptic behavior through `QualiaConfiguration`:

```swift
let config = QualiaConfiguration(
    autoPlayHaptics: true,
    enableHeartbeat: false, // Disables background "pulse"
    hapticIntensity: 0.7,   // Scale vibration strength
    hapticDelay: 0.1        // Debounce time
)

let client = QualiaClient(config: config)
```

## Custom providers

QualiaKit isn't tied to any specific model. Conform to `SentimentProvider` to plug in whatever backend you want — an API call, a TFLite model, your own heuristics, anything:

```swift
import Qualia

struct GPTProvider: SentimentProvider {
    func analyzeSentiment(_ text: String, language: NLLanguage) async throws -> Double {
        return await myCustomAnalyzer.predict(text) // Returns -1.0 to 1.0
    }
}

let client = QualiaClient(provider: GPTProvider())
```

## License

MIT. See [LICENSE](LICENSE) for details.
