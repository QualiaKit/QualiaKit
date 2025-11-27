# Changelog

All notable changes to QualiaKit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2025-11-27

### Added

- `QualiaConfiguration` for flexible behavior control
- Configuration presets: `.standard`, `.silent`, `.testing`, `.accessibility`
- `analyze(_:)` method for haptics-free sentiment analysis
- `feel(_:)` method for explicit haptic triggering
- Haptic intensity support with configurable multiplier (0.0 - 1.0)
- Configurable haptic delay for synchronization
- `baseIntensity` property on `HapticEngine`
- Intensity parameter to `HapticProvider` protocol
- `playedIntensities` tracking in `MockHapticProvider` for testing

### Changed

- **BREAKING:** `analyzeAndFeel()` now automatically plays haptics when `config.autoPlayHaptics = true`
- **BREAKING:** Heartbeat management is now automatic based on emotion and configuration
- `QualiaClient.init()` now accepts optional `config` parameter with default `.standard`
- `HapticEngine.play()` now accepts optional intensity parameter
- `HapticProvider.play()` signature updated to include intensity parameter
- Enhanced documentation with comprehensive examples

### Fixed

- Thread safety issues with `HapticEngine.shared` access from non-MainActor contexts
- Improved type safety with `Sendable` conformance for `HapticEngine`

### Migration

See [MIGRATION.md](MIGRATION.md) for detailed migration guide from v1.x to v2.0.

## [1.0.0] - 2025-11-26

### Added

- Initial release of QualiaKit
- BERT-based sentiment analysis
- Core Haptics integration
- Heartbeat patterns for intense emotions
- Keyword-based emotion detection (intense, mysterious)
- Multi-language support (Russian via BERT, English via NaturalLanguage)
- `MockHapticProvider` for testing
- Comprehensive test suite
- SwiftLint integration
- GitHub Actions CI/CD

[2.0.0]: https://github.com/yourusername/QualiaKit/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/yourusername/QualiaKit/releases/tag/v1.0.0
