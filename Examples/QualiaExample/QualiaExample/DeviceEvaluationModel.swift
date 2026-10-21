#if QUALIA_DEVICE_EVALUATION
import Combine
import CoreML
import Darwin
import Foundation
import QualiaKit
import SwiftUI
import UIKit

@MainActor
final class DeviceEvaluationModel: ObservableObject {
    @Published var status = "Готово к общей проверке"
    @Published var finished = false
    @Published var busy = false
    @Published var progress = 0.0
    @Published var summary: [String] = []
    @Published var reportURL: URL?
    @Published var trialToAssess: DeviceTactileTrial?
    @Published var trialSummaries: [String] = []
    @Published var backgroundObserved = false
    @Published var russianText = "Мне очень понравилась эта книга!"
    @Published var russianOutput = ""
    var russianAvailable: Bool { DeviceRussianAnalyzer.assetsURL != nil }
    private var russianAnalyzer: DeviceRussianAnalyzer?
    let renderer = DeviceTracingRenderer()
    private var session: QualiaSession?
    private var task: Task<Void, Never>?
    private var report = DeviceEvaluationReport()
    private var started = false
    private var automationStarted = false
    private var pendingAutomation: Task<Void, Never>?
    private var cleaning = false
    private var wasInactive = false
    private var awaitingBackground = false
    private var backgroundObservedRunID: String?

    func start() {
        guard !started else { return }
        started = true
        do {
            let url = try documents().appendingPathComponent("device-evaluation.json")
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                if let prior = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let id = prior["runID"] as? String, UUID(uuidString: id) != nil {
                    let archive = try documents().appendingPathComponent("DeviceEvaluationRuns", isDirectory: true)
                    try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
                    let priorURL = archive.appendingPathComponent(id + ".json")
                    if !FileManager.default.fileExists(atPath: priorURL.path) { try data.write(to: priorURL, options: .atomic) }
                }
                // Restore only v2; v1 remains available in the archive.
                if let version = try JSONSerialization.jsonObject(with: data) as? [String: Any], version["schemaVersion"] as? Int == 2 {
                    report = try JSONDecoder().decode(DeviceEvaluationReport.self, from: data)
                    // Restore the trace before save() takes its next snapshot. This
                    // restores records only; it must never replay physical effects.
                    renderer.records = report.commands
                    if report.automaticStatus == "running" {
                        report.automaticStatus = "interrupted"
                        report.errors.append("App process ended before automatic checks completed")
                    }
                    for index in report.trials.indices where report.trials[index].status == "running" {
                        report.trials[index].status = "interrupted"
                    }
                    if report.russianStatus == "running" { report.russianStatus = "interrupted" }
                    finished = report.automaticStatus == "completed"
                    status = finished ? "Предыдущий прогон сохранён" : "Готово. Предыдущий отчёт сохранён."
                    refreshSummary()
                    try save()
                }
            }
        } catch { status = "Не удалось прочитать предыдущий отчёт: \(error)" }
        scheduleAutomationWhenActive()
    }

    private func scheduleAutomationWhenActive() {
        guard started, !automationStarted, UIApplication.shared.applicationState == .active else { return }
        pendingAutomation?.cancel()
        pendingAutomation = Task {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard !Task.isCancelled, UIApplication.shared.applicationState == .active else { return }
            automationStarted = true
            #if targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--device-evaluation-self-test") { runAll(sustainedSeconds: 5, platformChecks: false) }
            #endif
            if ProcessInfo.processInfo.arguments.contains("--device-evaluation-russian") { runRussian(seconds: 300) }
            if ProcessInfo.processInfo.arguments.contains("--device-evaluation-russian-quick") { runRussian(seconds: nil) }
            if ProcessInfo.processInfo.arguments.contains("--device-evaluation-quick") { runAll(sustainedSeconds: nil) }
            if ProcessInfo.processInfo.arguments.contains("--device-evaluation-full") { runAll(sustainedSeconds: 300) }
        }
    }

    func runAll(sustainedSeconds: Int? = 300, platformChecks: Bool = true) {
        guard !busy, !cleaning else { return }
        busy = true
        finished = false
        backgroundObserved = false
        awaitingBackground = false
        backgroundObservedRunID = nil
        trialToAssess = nil
        report = DeviceEvaluationReport()
        report.automaticStatus = "running"
        report.metadata = metadata()
        report.metadata["automaticMode"] = sustainedSeconds == nil ? "quick" : "full"
        report.metadata["automaticPhase"] = "baselines"
        if sustainedSeconds == nil { report.metadata["sustained"] = "not-run: quick mode" }
        if !platformChecks { report.metadata["appleAnalysis"] = "not-run: simulator lacks NLTagger sentiment assets" }
        report.humanAssessment = ["background": "pending", "reduce-motion": "pending", "preferred-profile": "pending"]
        UIApplication.shared.isIdleTimerDisabled = true
        task = Task {
            do {
                try await session?.reset()
                renderer.records.removeAll()
                try save()
                for index in 0..<3 {
                    status = "Анализ текста, состояние и контекст: прогон \(index + 1)/3"
                    let worker = Task.detached { try await DeviceEvaluationBenchmark.run(appleAnalysisEnabled: platformChecks) }
                    report.benchmarks.append(try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() })
                    try save()
                }
                status = "Core ML: загрузка, токенизация и инференс публичной модели"
                report.metadata["automaticPhase"] = "public-coreml"
                try save()
                let coreML = Task.detached { try await DeviceCoreMLBenchmark.run() }
                report.coreML = try await withTaskCancellationHandler { try await coreML.value } onCancel: { coreML.cancel() }
                try save()
                status = "Автоматические проверки вибрации"
                report.metadata["automaticPhase"] = "haptics"
                try save()
                if platformChecks { try await automaticHaptics() }
                else { report.technicalChecks["hardware-tests"] = "not-run: simulator self-test" }
                if let sustainedSeconds {
                    status = "Длительный тест: оставь приложение открытым"
                    report.metadata["automaticPhase"] = "sustained"
                    try save()
                    progress = 0
                    let worker = Task.detached {
                        try await DeviceSustainedBenchmark.run(seconds: sustainedSeconds, publicFixture: !platformChecks) { value in
                            await self.setProgress(value)
                        }
                    }
                    report.sustained = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                }
                try Task.checkCancellation()
                report.automaticStatus = "completed"
                report.metadata["automaticPhase"] = "completed"
                finished = true
                status = platformChecks ? "Автоматический прогон сохранён. Далее — ощущения и сворачивание." : "Программная самопроверка завершена; физические проверки не выполнялись."
                refreshSummary()
                try save()
            } catch {
                report.automaticStatus = error is CancellationError ? "interrupted" : "failed"
                report.errors.append(String(describing: error))
                status = "Прогон не завершён: \(error)"
                await cleanup()
                persistOrReportError()
            }
            busy = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func setProgress(_ value: Double) { progress = value }

    private func makeSession(maximumDuration: Double = 3, scale: Float = 0.5) async throws -> QualiaSession {
        try await QualiaSession.horrorNarrative(analyzer: DeviceScriptedAnalyzer(), renderer: renderer,
            language: .init(policy: .requireExplicit, minimumConfidence: 0.75),
            context: .init(maximumFragments: 0, maximumCharacters: 1000),
            policy: .init(heartbeat: .init(startThreshold: 0.5, stopThreshold: 0.25, minimumBPM: 60, maximumBPM: 120)),
            haptics: .init(preferences: .init(continuousEffectsEnabled: !UIAccessibility.isReduceMotionEnabled,
                intensityScale: scale, maximumContinuousDuration: .seconds(maximumDuration))))
    }

    @discardableResult
    private func process(_ id: String) async throws -> QualiaResponse {
        guard let session else { throw DeviceEvaluationFailure.check("No session") }
        let response = try await session.process(.init(id: .init(rawValue: id), text: "Repository-authored synthetic fixture.", language: .init(rawValue: "en")))
        if let failure = response.execution.failure { throw failure }
        return response
    }

    private func check(_ name: String, _ condition: Bool) throws {
        report.technicalChecks[name] = condition ? "passed" : "failed"
        try save()
        if !condition { throw DeviceEvaluationFailure.check(name) }
    }
    private func automaticHaptics() async throws {
        try check("hardware-support", renderer.capabilities.supportsHaptics && renderer.capabilities.supportsContinuousHaptics)
        guard !UIAccessibility.isReduceMotionEnabled else {
            report.technicalChecks["ambient-tests"] = "not-run: Reduce Motion enabled"
            return
        }
        session = try await makeSession()
        let offset = renderer.records.count
        _ = try await process("build")
        try check("start", renderer.activeEffects.count == 1)
        try await Task.sleep(for: .seconds(1))
        _ = try await process("impact")
        let kinds = Array(renderer.records.dropFirst(offset).map(\.kind))
        try check("replace-and-independent-impact", kinds == ["start", "replace", "play"] && renderer.activeEffects.count == 1)
        try await Task.sleep(for: .milliseconds(500))
        try await session?.reset()
        try check("reset-stops-ambient", renderer.activeEffects.isEmpty)

        _ = try await process("high")
        try await session?.updateHapticPreferences(.disabled)
        try check("disable-stops-ambient", renderer.activeEffects.isEmpty)
        let disabledOffset = renderer.records.count
        _ = try await process("disabled")
        try check("disabled-produces-no-playback", renderer.records.count == disabledOffset)

        try await session?.reset()
        session = try await makeSession()
        _ = try await process("high")
        try await session?.suspend()
        try check("programmatic-suspend-stops-ambient", renderer.activeEffects.isEmpty)
        let suspendedOffset = renderer.records.count
        try await session?.resume()
        try check("resume-does-not-replay", renderer.activeEffects.isEmpty && !renderer.records.dropFirst(suspendedOffset).contains { ["start", "replace", "play"].contains($0.kind) })

        try await session?.updateHapticPreferences(.init(continuousEffectsEnabled: false, intensityScale: 0.5))
        let accentOffset = renderer.records.count
        _ = try await process("impact")
        try check("continuous-disabled-accent-still-works", renderer.records.dropFirst(accentOffset).map(\.kind) == ["play"] && renderer.activeEffects.isEmpty)

        try await session?.reset()
        session = try await makeSession(maximumDuration: 2)
        _ = try await process("high")
        try await Task.sleep(for: .milliseconds(2300))
        try check("physical-deadline-without-new-input", renderer.activeEffects.isEmpty)
        try await session?.reset()

        session = try await makeSession(scale: 0)
        let zeroOffset = renderer.records.count
        _ = try await process("impact")
        try check("zero-intensity-no-playback", renderer.records.count == zeroOffset && renderer.activeEffects.isEmpty)
        try await session?.reset()
    }

    func tactileScenario(_ profile: DeviceTactileProfile) {
        guard finished, !busy, !cleaning else { return }
        guard !UIAccessibility.isReduceMotionEnabled else {
            status = "Ритм отключён настройкой «Уменьшение движения». Её проверка доступна ниже."
            return
        }
        busy = true
        awaitingBackground = false
        trialToAssess = nil
        let trial = DeviceTactileTrial(id: UUID().uuidString, profile: profile.rawValue, intensityScale: profile.scale, status: "running")
        report.trials.append(trial)
        let index = report.trials.count - 1
        UIApplication.shared.isIdleTimerDisabled = true
        task = Task {
            do {
                try save()
                try await session?.reset()
                session = try await makeSession(maximumDuration: 12, scale: profile.scale)
                status = "\(profile.title): 1/4 · ровное сердцебиение, 3 секунды"
                _ = try await process("build")
                try await Task.sleep(for: .seconds(3))
                status = "2/4 · ускорение, 3 секунды"
                _ = try await process("high")
                try await Task.sleep(for: .seconds(3))
                status = "3/4 · отдельный удар"
                _ = try await process("impact")
                try await Task.sleep(for: .seconds(2))
                try await session?.reset()
                report.trials[index].status = "completed"
                trialToAssess = report.trials[index]
                status = "4/4 · остановлено. Оцени каждый этап."
            } catch {
                report.trials[index].status = error is CancellationError ? "interrupted" : "failed"
                report.errors.append("Tactile trial: \(error)")
                status = "Сценарий прерван; оценка не засчитывается"
                await cleanup()
            }
            refreshSummary()
            persistOrReportError()
            busy = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    func assessTrial(calm: String, acceleration: String, accent: String, comfort: String) {
        guard !busy, let trialToAssess,
              let index = report.trials.firstIndex(where: { $0.id == trialToAssess.id && $0.status == "completed" }) else { return }
        report.trials[index].assessment = ["calm": calm, "acceleration": acceleration, "accent": accent, "comfort": comfort]
        self.trialToAssess = nil
        status = "Оценка сохранена. Можно сравнить следующий вариант."
        refreshSummary()
        persistOrReportError()
    }

    func prefer(_ profile: DeviceTactileProfile) {
        guard report.trials.contains(where: { $0.profile == profile.rawValue && !$0.assessment.isEmpty }) else {
            status = "Сначала прослушай и оцени этот вариант"
            return
        }
        report.humanAssessment["preferred-profile"] = profile.rawValue
        persistOrReportError()
    }

    func backgroundScenario() {
        guard finished, !busy, !cleaning, !UIAccessibility.isReduceMotionEnabled else { return }
        busy = true
        awaitingBackground = true
        backgroundObserved = false
        backgroundObservedRunID = nil
        task = Task {
            do {
                try await session?.reset()
                session = try await makeSession(maximumDuration: 12, scale: 0.75)
                _ = try await process("high")
                status = "Сверни приложение сейчас, затем вернись: ритм должен прекратиться."
                try await Task.sleep(for: .seconds(12))
                awaitingBackground = false
                status = "Время истекло. Для проверки повтори и сверни во время вибрации."
                try await session?.reset()
            } catch {
                await cleanup()
            }
            persistOrReportError()
            busy = false
        }
    }

    func assessBackground(_ value: String) {
        guard !busy, backgroundObserved, backgroundObservedRunID == report.runID else { return }
        report.humanAssessment["background"] = value
        status = "Оценка сворачивания сохранена"
        persistOrReportError()
    }

    func checkReduceMotion() {
        guard finished, !busy, !cleaning else { return }
        guard UIAccessibility.isReduceMotionEnabled else {
            status = "Включи «Уменьшение движения» в настройках iPhone, вернись и повтори проверку."
            return
        }
        busy = true
        task = Task {
            do {
                try await session?.reset()
                session = try await makeSession()
                let offset = renderer.records.count
                _ = try await process("impact")
                try check("system-reduce-motion-ambient-suppressed", renderer.activeEffects.isEmpty &&
                          renderer.records.dropFirst(offset).map(\.kind) == ["play"])
                report.humanAssessment["reduce-motion"] = "system-toggle-observed; ambient suppressed; accent dispatched"
                try await session?.reset()
                status = "Уменьшение движения: ритм отключён, отдельный удар сохранён"
            } catch { report.errors.append("Reduce Motion: \(error)"); await cleanup() }
            persistOrReportError()
            busy = false
        }
    }

    func stop() {
        guard !cleaning else { return }
        cleaning = true
        awaitingBackground = false
        let interrupted = task
        interrupted?.cancel()
        Task {
            await interrupted?.value
            await cleanup()
            status = "Остановлено"
            persistOrReportError()
            cleaning = false
        }
    }

    func sceneChanged(_ phase: ScenePhase) {
        guard started else { return }
        if phase == .active {
            scheduleAutomationWhenActive()
            if wasInactive, awaitingBackground, backgroundObservedRunID == report.runID {
                backgroundObserved = true
                status = "После возвращения должно быть тихо. Оцени результат ниже."
            }
            wasInactive = false
            return
        }
        pendingAutomation?.cancel()
        wasInactive = true
        guard busy, !cleaning else { return }
        cleaning = true
        let hadAmbient = !renderer.activeEffects.isEmpty
        if awaitingBackground, hadAmbient { backgroundObservedRunID = report.runID }
        report.metadata["lastInactiveAt"] = ISO8601DateFormatter().string(from: Date())
        report.metadata["lastInactiveScenePhase"] = phase == .background ? "background" : "inactive"
        let interrupted = task
        interrupted?.cancel()
        Task {
            await interrupted?.value
            do {
                try await session?.suspend()
                if hadAmbient { report.technicalChecks["actual-scene-deactivation-cleanup"] = renderer.activeEffects.isEmpty ? "passed" : "failed" }
                if awaitingBackground, !wasInactive, backgroundObservedRunID == report.runID {
                    backgroundObserved = true
                    status = "После возвращения должно быть тихо. Оцени результат ниже."
                }
            } catch { report.errors.append("Scene cleanup: \(error)") }
            persistOrReportError()
            cleaning = false
        }
    }

    private func cleanup() async {
        do { try await session?.reset() }
        catch { report.errors.append("Cleanup: \(error)"); status = "Ошибка остановки: \(error)" }
    }

    func runRussian(seconds: Int?) {
        guard !busy, !cleaning, russianAvailable else { return }
        busy = true; finished = false
        backgroundObserved = false; awaitingBackground = false; trialToAssess = nil
        report = DeviceEvaluationReport(); report.metadata = metadata()
        report.metadata["analyzer"] = "Recovered RuBERT; diagnostic raw classes with provisional interpretation"
        report.metadata["method"] = "RuBERT: 35 source parity cases; cpuOnly and all; 3 text lengths each 5 warmups/30 samples; optional 300s load at up to 10Hz; nearest rank"
        report.metadata["hapticInput"] = "none: Russian inference measurements do not generate haptics"
        report.russianStatus = "running"
        UIApplication.shared.isIdleTimerDisabled = true
        task = Task {
            do {
                try await session?.reset()
                renderer.records.removeAll(); try save()
                let worker = Task.detached {
                    try await DeviceRussianBenchmark.run(seconds: seconds) { status, progress in
                        await self.updateRussianProgress(status, progress)
                    }
                }
                report.russian = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                report.russianStatus = "completed"
                status = "Замеры RuBERT завершены. Можно проверить свой текст."
            } catch is CancellationError {
                report.russianStatus = "interrupted"; status = "Замеры RuBERT прерваны"
            } catch {
                report.russianStatus = "failed"; report.errors.append("RuBERT: \(error)"); status = "Ошибка RuBERT: \(error)"
            }
            busy = false; progress = 0; UIApplication.shared.isIdleTimerDisabled = false
            refreshSummary(); persistOrReportError()
        }
    }
    private func updateRussianProgress(_ message: String, _ value: Double) {
        status = message; progress = value
        report.metadata["russianPhase"] = message
        report.metadata["russianProgress"] = String(value)
        persistOrReportError()
    }

    func analyzeRussianText() {
        guard !busy, !cleaning, let directory = DeviceRussianAnalyzer.assetsURL else { return }
        let text = russianText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { russianOutput = "Введи текст"; return }
        busy = true; status = "RuBERT анализирует текст"
        task = Task {
            do {
                if russianAnalyzer == nil {
                    let worker = Task.detached { try DeviceRussianAnalyzer(directory: directory, computeUnits: .all) }
                    russianAnalyzer = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                }
                guard let analyzer = russianAnalyzer else { throw DeviceEvaluationFailure.check("Missing Russian analyzer") }
                let result = try await analyzer.predict(text)
                try Task.checkCancellation()
                russianOutput = result.probabilities.enumerated().map { index, value in
                    "LABEL_\(index) · \(DeviceRussianAnalyzer.captions[index]): \(String(format: "%.1f", value * 100))%"
                }.joined(separator: "\n") + "\n\(result.tokenCount) токенов · \(String(format: "%.1f", result.stagesMilliseconds["total"] ?? 0)) мс" + (result.truncated ? " · текст обрезан до 128 токенов" : "")
                status = "Готово. Названия классов — экспериментальная расшифровка."
            } catch is CancellationError { status = "Анализ прерван" }
            catch { status = "Ошибка RuBERT: \(error)" }
            busy = false
        }
    }

    private func refreshSummary() {
        summary = report.benchmarks.last?.measurements.map { "\($0.name): p95 \(String(format: "%.3f", $0.p95)) мс" } ?? []
        if let russian = report.russian {
            summary += russian.modes.flatMap { mode in
                mode.measurements.filter { $0.name.hasSuffix("-total") }.map { "RuBERT \(mode.computeUnits) \($0.name): p95 \(String(format: "%.2f", $0.p95)) мс" }
            }
        }
        trialSummaries = report.trials.map { trial in
            let result = trial.assessment.isEmpty ? trial.status : trial.assessment.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            return "\(trial.profile) · \(result)"
        }
    }

    private func metadata() -> [String: String] {
        var system = utsname()
        uname(&system)
        let machine = withUnsafePointer(to: &system.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
        }
        #if targetEnvironment(simulator)
        let physical = "false"
        #else
        let physical = "true"
        #endif
        #if DEBUG
        let configuration = "Debug"
        #else
        let configuration = "Release"
        #endif
        return ["physicalDevice": physical, "device": machine, "os": UIDevice.current.systemVersion,
            "osBuild": ProcessInfo.processInfo.operatingSystemVersionString,
            "configuration": configuration, "concurrency": "1", "runtime": QualiaDiagnosticEvent.runtimeVersion,
            "policy": HorrorNarrativePolicy.version, "heartbeat": HeartbeatPolicyConfiguration.version,
            "analyzer": "AppleSentimentAnalyzer/1; public arithmetic Core ML fixture only",
            "hapticInput": "scripted signals; not narrative semantic inference",
            "sourceSHA256": sourceIdentity(),
            "lowPowerMode": String(ProcessInfo.processInfo.isLowPowerModeEnabled),
            "reduceMotionAtStart": String(UIAccessibility.isReduceMotionEnabled),
            "method": "v2: 3 sequential same-process baselines, 20 warmups/200 Apple samples, 100 warmups/1000 policy and context samples; nearest-rank; no isolated cold-cache claim",
            "tactileConfiguration": "thresholds 0.5/0.25; BPM 60...120; scales A=0.5 B=0.75 C=1; 3s rhythm +3s acceleration +2s accent; 12s hard limit",
            "energy": "CPU/thermal trace only in-app; watt/joule requires external Instruments",
        ]
    }

    private func sourceIdentity() -> String {
        if let value = ProcessInfo.processInfo.environment["QUALIA_EVALUATION_SOURCE"] { return value }
        do {
            guard let bundle = Bundle.main.url(forResource: "DeviceEvaluationAssets", withExtension: "bundle") else {
                return "unavailable"
            }
            let data = try Data(contentsOf: bundle.appendingPathComponent("build-identity.json"))
            struct Identity: Decodable { let sourceSHA256: String }
            return try JSONDecoder().decode(Identity.self, from: data).sourceSHA256
        } catch { return "unavailable" }
    }

    private func documents() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }
    private func save() throws {
        report.commands = renderer.records
        let directory = try documents()
        let archive = directory.appendingPathComponent("DeviceEvaluationRuns", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        let url = archive.appendingPathComponent(report.runID + ".json")
        try data.write(to: url, options: .atomic)
        try data.write(to: directory.appendingPathComponent("device-evaluation.json"), options: .atomic)
        reportURL = url
    }
    private func persistOrReportError() {
        do { try save() } catch { status = "Не удалось сохранить отчёт: \(error)" }
    }
}
#endif
