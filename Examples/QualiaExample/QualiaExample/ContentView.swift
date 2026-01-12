import Qualia
import SwiftUI

struct ContentView: View {
    @State private var userInput: String = ""
    @State private var currentEmotion: String = "neutral"

    private let qualiaClient = QualiaClient()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                EmotionIndicator(emotion: currentEmotion)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: currentEmotion)

                VStack(spacing: 16) {
                    Text("Feel Your Words")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Type something in English")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))

                    ZStack(alignment: .leading) {
                        if userInput.isEmpty {
                            Text("Start typing...")
                                .foregroundColor(.white.opacity(0.5))
                                .font(.system(size: 18, design: .rounded))
                        }

                        TextField("", text: $userInput)
                            .font(.system(size: 18, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .qualiaFeedback(trigger: $userInput)
                            .onChange(of: userInput) { oldValue, newValue in
                                updateEmotion(from: newValue)
                            }
                    }
                    .padding()
                    .frame(height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 32)
                }

                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 14))
                    Text("Powered by QualiaKit")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.6))
                .padding(.bottom, 40)
            }
        }
    }

    private func updateEmotion(from text: String) {
        guard !text.isEmpty else {
            currentEmotion = "neutral"
            return
        }

        let stopWords = [
            "a", "an", "the", "this", "that", "these", "those",
            "it", "its", "i", "me", "my", "you", "your",
            "he", "she", "we", "they", "is", "am", "are",
            "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did",
            "will", "would", "should", "could", "may", "might",
            "can", "of", "in", "on", "at", "to", "for",
            "with", "from", "by", "about", "as", "into",
        ]

        let trimmedLower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if stopWords.contains(trimmedLower) {
            currentEmotion = "neutral"
            return
        }

        let lowercased = text.lowercased()
        let positiveNegations = [
            "not bad", "not terrible", "not awful", "not horrible",
            "not wrong", "not poor", "not weak", "not worse",
        ]

        if positiveNegations.contains(where: { lowercased.contains($0) }) {
            currentEmotion = "positive"
            return
        }

        var processedText = text.trimmingCharacters(in: .whitespaces)
        let hasPunctuation = processedText.last.map { "!?.,:;".contains($0) } ?? false

        if !hasPunctuation && processedText.count < 15 {
            processedText += "."
        }

        Task {
            let (emotion, score) = await qualiaClient.analyze(processedText)

            await MainActor.run {
                switch emotion {
                case .positive:
                    currentEmotion = "positive"
                case .negative:
                    currentEmotion = "negative"
                case .neutral:
                    currentEmotion = "neutral"
                case .intense:
                    currentEmotion = "positive"
                case .mysterious:
                    currentEmotion = "positive"
                }
            }
        }
    }

    private var gradientColors: [Color] {
        switch currentEmotion {
        case "positive":
            return [
                Color(red: 0.4, green: 0.8, blue: 0.6),
                Color(red: 0.2, green: 0.6, blue: 0.9),
            ]
        case "negative":
            return [
                Color(red: 0.9, green: 0.4, blue: 0.4),
                Color(red: 0.6, green: 0.2, blue: 0.5),
            ]
        default:
            return [
                Color(red: 0.3, green: 0.4, blue: 0.7),
                Color(red: 0.5, green: 0.3, blue: 0.6),
            ]
        }
    }
}

struct EmotionIndicator: View {
    let emotion: String

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                circleColor.opacity(0.3),
                                circleColor.opacity(0.1),
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                Circle()
                    .fill(circleColor)
                    .frame(width: 100, height: 100)
                    .shadow(color: circleColor.opacity(0.5), radius: 20, x: 0, y: 10)

                Text(emoji)
                    .font(.system(size: 50))
            }

            Text(emotionLabel)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
    }

    private var emoji: String {
        switch emotion {
        case "positive": return "😊"
        case "negative": return "😔"
        default: return "😐"
        }
    }

    private var emotionLabel: String {
        switch emotion {
        case "positive": return "Positive Vibes"
        case "negative": return "Negative Feels"
        default: return "Neutral"
        }
    }

    private var circleColor: Color {
        switch emotion {
        case "positive": return Color(red: 0.4, green: 0.9, blue: 0.6)
        case "negative": return Color(red: 1.0, green: 0.4, blue: 0.4)
        default: return Color(red: 0.7, green: 0.7, blue: 0.9)
        }
    }
}

#Preview {
    ContentView()
}
