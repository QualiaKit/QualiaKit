# Migration Guide: v1.x → v2.0

This guide will help you migrate from QualiaKit v1.x to v2.0.

## Overview

QualiaKit v2.0 introduces a major API redesign focused on:

- **Explicit configuration** for haptic behavior
- **Separation of concerns** between analysis and haptic feedback
- **New methods** for fine-grained control

## Breaking Changes

### 1. `analyzeAndFeel()` Now Plays Haptics Automatically

**v1.x Behavior:**

```swift
let (emotion, _) = await client.analyzeAndFeel(text)
// No haptics were played - you had to call HapticEngine manually
HapticEngine.shared.play(for: emotion)
```

**v2.0 Behavior:**

```swift
let (emotion, _) = await client.analyzeAndFeel(text)
// ✅ Haptics play automatically (if config.autoPlayHaptics = true)
```

**Migration:** If you were calling haptics manually after `analyzeAndFeel()`, remove those calls:

```swift
// Before (v1.x)
let (emotion, _) = await client.analyzeAndFeel(text)
HapticEngine.shared.play(for: emotion)

// After (v2.0) - Option A: Use new behavior (recommended)
let (emotion, _) = await client.analyzeAndFeel(text)
// Haptics play automatically!

// After (v2.0) - Option B: Use silent config + manual control
let client = try QualiaClient(
    vocabURL: vocabURL,
    modelURL: modelURL,
    config: .silent
)
let (emotion, _) = await client.analyzeAndFeel(text)
await client.feel(emotion) // Manual control
```

### 2. New `analyze()` Method for Haptics-Free Analysis

If you only want sentiment analysis without haptics:

**v1.x:**

```swift
// You had to disable haptics manually or not call HapticEngine
let (emotion, score) = await client.analyzeAndFeel(text)
// Hope you don't accidentally trigger haptics elsewhere
```

**v2.0:**

```swift
// Clean separation: analyze() never plays haptics
let (emotion, score) = await client.analyze(text)
```

### 3. Configuration Parameter Added to Initializer

**v1.x:**

```swift
let client = try QualiaClient(vocabURL: vocabURL, modelURL: modelURL)
```

**v2.0:**

```swift
// Default config parameter (backward compatible)
let client = try QualiaClient(vocabURL: vocabURL, modelURL: modelURL)

// Or with explicit config
let client = try QualiaClient(
    vocabURL: vocabURL,
    modelURL: modelURL,
    config: .standard
)
```

**Migration:** No changes needed if you're using the default configuration.

### 4. Heartbeat Management Moved Inside QualiaClient

**v1.x:**

```swift
let (emotion, _) = await client.analyzeAndFeel(text)
HapticEngine.shared.play(for: emotion)
HapticEngine.shared.updateHeartbeat(shouldPlay: emotion == .intense)
```

**v2.0:**

```swift
let (emotion, _) = await client.analyzeAndFeel(text)
// ✅ Everything happens automatically based on config!
```

**Migration:** Remove manual `updateHeartbeat()` calls. Heartbeat is now managed automatically by `QualiaClient` based on emotion and configuration.

## New Features

### 1. Configuration Presets

Choose the right preset for your use case:

```swift
// Standard mode - auto-haptics enabled
let client = try QualiaClient(vocabURL: vocabURL, modelURL: modelURL, config: .standard)

// Silent mode - no haptics
let client = try QualiaClient(vocabURL: vocabURL, modelURL: modelURL, config: .silent)

// Testing mode - optimized for unit tests
let client = try QualiaClient(vocabURL: vocabURL, modelURL: modelURL, config: .testing)

// Accessibility mode - reduced intensity
let client = try QualiaClient(vocabURL: vocabURL, modelURL: modelURL, config: .accessibility)
```

### 2. Custom Configuration

Fine-tune haptic behavior:

```swift
let config = QualiaConfiguration(
    autoPlayHaptics: true,
    enableHeartbeat: false,
    hapticIntensity: 0.7,
    hapticDelay: 0.2
)
let client = try QualiaClient(vocabURL: vocabURL, modelURL: modelURL, config: config)
```

### 3. New `feel()` Method

Explicitly trigger haptics for any emotion:

```swift
// Analyze without haptics
let (emotion, _) = await client.analyze(text)

// Later, manually trigger haptics
await client.feel(.intense)
```

### 4. Haptic Intensity Control

```swift
// Configure via QualiaConfiguration
let config = QualiaConfiguration(hapticIntensity: 0.5)
let client = try QualiaClient(vocabURL: vocabURL, modelURL: modelURL, config: config)

// Or set directly on HapticEngine
HapticEngine.shared.baseIntensity = 0.5
```

## Migration Steps

### Step 1: Review Your Usage

Audit your codebase for:

- [ ] Calls to `analyzeAndFeel()` followed by manual `HapticEngine.shared.play()`
- [ ] Manual `updateHeartbeat()` calls
- [ ] Places where you only need analysis without haptics

### Step 2: Choose Migration Strategy

**Option A: Embrace New Behavior (Recommended)**

Remove manual haptic calls and let `analyzeAndFeel()` handle everything:

```diff
- let (emotion, _) = await client.analyzeAndFeel(text)
- HapticEngine.shared.play(for: emotion)
- HapticEngine.shared.updateHeartbeat(shouldPlay: emotion == .intense)
+ let (emotion, _) = await client.analyzeAndFeel(text)
```

**Option B: Use Silent Config + Manual Control**

Keep manual control by using `.silent` configuration:

```swift
let client = try QualiaClient(
    vocabURL: vocabURL,
    modelURL: modelURL,
    config: .silent
)
let (emotion, _) = await client.analyzeAndFeel(text)
await client.feel(emotion) // Manual control
```

**Option C: Use `analyze()` for Analysis-Only**

Replace `analyzeAndFeel()` with `analyze()` where haptics aren't needed:

```diff
- let (emotion, score) = await client.analyzeAndFeel(text)
+ let (emotion, score) = await client.analyze(text)
```

### Step 3: Update Initialization

If you need non-default behavior, add configuration:

```swift
let client = try QualiaClient(
    vocabURL: vocabURL,
    modelURL: modelURL,
    config: .standard // or .silent, .testing, .accessibility
)
```

### Step 4: Update Tests

For unit tests, use `.testing` configuration:

```swift
let client = try QualiaClient(
    vocabURL: vocabURL,
    modelURL: modelURL,
    config: .testing
)
```

### Step 5: Test Thoroughly

- [ ] Verify haptics play when expected
- [ ] Verify heartbeat triggers for intense emotions
- [ ] Test all emotion types
- [ ] Validate configuration presets

## Common Migration Scenarios

### Scenario 1: Interactive Storytelling App

**Before:**

```swift
let (emotion, _) = await qualiaClient.analyzeAndFeel(text)
HapticEngine.shared.play(for: emotion)
HapticEngine.shared.updateHeartbeat(shouldPlay: emotion == .intense)
```

**After:**

```swift
// Just remove manual haptic calls
let (emotion, _) = await qualiaClient.analyzeAndFeel(text)
```

### Scenario 2: Analytics Dashboard (Analysis Only)

**Before:**

```swift
let (emotion, score) = await qualiaClient.analyzeAndFeel(text)
// Hopefully no haptics triggered elsewhere
```

**After:**

```swift
// Use analyze() for clean separation
let (emotion, score) = await qualiaClient.analyze(text)
```

### Scenario 3: Unit Tests

**Before:**

```swift
let client = try QualiaClient(vocabURL: vocabURL, modelURL: modelURL)
let (emotion, _) = await client.analyzeAndFeel("test")
// Haptics might trigger during tests
```

**After:**

```swift
let client = try QualiaClient(
    vocabURL: vocabURL,
    modelURL: modelURL,
    config: .testing
)
let (emotion, _) = await client.analyze("test")
```

### Scenario 4: Accessibility Features

**Before:**

```swift
let client = try QualiaClient(vocabURL: vocabURL, modelURL: modelURL)
// No way to reduce haptic intensity
```

**After:**

```swift
let client = try QualiaClient(
    vocabURL: vocabURL,
    modelURL: modelURL,
    config: .accessibility // 50% intensity
)
```

## Need Help?

If you encounter any issues during migration:

1. Review the [README.md](README.md) for updated examples
2. Check the [API documentation](#) (coming soon)
3. Open an issue on [GitHub](https://github.com/yourusername/QualiaKit/issues)

## Rollback Plan

If you need to temporarily rollback to v1.x behavior:

```swift
let client = try QualiaClient(
    vocabURL: vocabURL,
    modelURL: modelURL,
    config: .silent
)

// Then manually call haptics as in v1.x
let (emotion, _) = await client.analyzeAndFeel(text)
await client.feel(emotion)
HapticEngine.shared.updateHeartbeat(shouldPlay: emotion == .intense)
```

However, this is **not recommended** long-term. Embrace v2.0's improved API!
