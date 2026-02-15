# Contributing

Contributions are welcome. If you're fixing a bug or adding something small, feel free to open a PR directly. For larger changes, open an issue first so we can discuss the approach.

## Building and testing

```bash
swift build
swift test
```

SwiftLint is optional but appreciated — `brew install swiftlint` if you don't have it, then `swiftlint lint` before submitting.

## Pull requests

Branch off `main`, keep commits focused, and make sure tests pass. If you're adding new public API, include tests for it. That's about it.

## Reporting bugs

Open an issue with a short description of the problem, what you expected, and a minimal code sample if possible. Include your OS and Swift version.
