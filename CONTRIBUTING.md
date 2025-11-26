# Contributing to QualiaKit

Thank you for your interest in contributing to QualiaKit! 🎉

## Getting Started

### Prerequisites

- macOS 13.0+ or iOS 16.0+
- Xcode 15.0+
- Swift 5.9+
- SwiftLint (optional, but recommended)

### Setup

1. **Fork and clone the repository**

   ```bash
   git clone https://github.com/yourusername/QualiaKit.git
   cd QualiaKit
   ```

2. **Install SwiftLint** (recommended)

   ```bash
   brew install swiftlint
   ```

3. **Build the package**

   ```bash
   swift build
   ```

4. **Run tests**
   ```bash
   swift test
   ```

## Development Workflow

### Code Style

We use SwiftLint to enforce code style. Please ensure your code passes linting before submitting a PR:

```bash
swiftlint lint
```

Key style guidelines:

- **Line length**: 120 characters max
- **Indentation**: 4 spaces (no tabs)
- **Naming**: Use descriptive names following Swift conventions
- **Documentation**: Public APIs must have documentation comments

### Running Tests

Run all tests:

```bash
swift test
```

Run specific tests:

```bash
swift test --filter BertTokenizerTests
```

Run tests with a real BERT model (optional):

```bash
export QUALIAKIT_TEST_MODEL_PATH=/path/to/your/model.mlmodel
swift test
```

### Test Coverage

We aim for >70% test coverage on core components. When adding new features, please include tests.

## Pull Request Process

1. **Create a feature branch**

   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**

   - Write clean, well-documented code
   - Add tests for new functionality
   - Update documentation as needed

3. **Ensure tests pass**

   ```bash
   swift test
   swiftlint lint
   ```

4. **Commit your changes**

   ```bash
   git commit -m "Add feature: your feature description"
   ```

   Use clear, descriptive commit messages following conventional commits:

   - `feat:` for new features
   - `fix:` for bug fixes
   - `docs:` for documentation changes
   - `test:` for test additions/changes
   - `refactor:` for code refactoring

5. **Push to your fork**

   ```bash
   git push origin feature/your-feature-name
   ```

6. **Create a Pull Request**
   - Provide a clear description of your changes
   - Link any related issues
   - Ensure CI checks pass

### PR Checklist

Before submitting your PR, please ensure:

- [ ] Code builds without errors
- [ ] All tests pass
- [ ] SwiftLint checks pass
- [ ] New functionality includes tests
- [ ] Public APIs are documented
- [ ] README updated (if needed)
- [ ] No breaking changes (or clearly marked if unavoidable)

## Testing Guidelines

### Unit Tests

- Test one thing per test method
- Use descriptive test names: `testFeature_Scenario_ExpectedResult`
- Use `XCTAssert` methods appropriately
- Clean up resources in `tearDown`

### Integration Tests

- Mark tests that require external resources (models) as skippable
- Use `XCTSkip` for tests that can't run in all environments
- Document required environment variables

### Mock Providers

Use `MockHapticProvider` for testing haptic functionality:

```swift
let mockProvider = MockHapticProvider()
mockProvider.play(.positive)
XCTAssertEqual(mockProvider.playedEmotions.count, 1)
```

## Reporting Issues

When reporting issues, please include:

- **Description**: Clear description of the problem
- **Steps to reproduce**: Detailed steps to reproduce the issue
- **Expected behavior**: What you expected to happen
- **Actual behavior**: What actually happened
- **Environment**: OS version, Swift version, Xcode version
- **Code sample**: Minimal code that reproduces the issue (if applicable)

## Feature Requests

We welcome feature requests! Please:

1. Check if the feature has already been requested
2. Clearly describe the use case
3. Explain how it benefits users
4. Consider implementation challenges

## Code of Conduct

- Be respectful and inclusive
- Welcome newcomers
- Focus on constructive feedback
- Help others learn and grow

## Questions?

Feel free to:

- Open an issue for questions
- Start a discussion in GitHub Discussions
- Reach out to maintainers

Thank you for contributing to QualiaKit! 🚀
