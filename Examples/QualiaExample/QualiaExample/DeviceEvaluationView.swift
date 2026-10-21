#if QUALIA_DEVICE_EVALUATION
import SwiftUI

struct DeviceEvaluationView: View {
    @StateObject private var model = DeviceEvaluationModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var calm = "pending"
    @State private var acceleration = "pending"
    @State private var accent = "pending"
    @State private var comfort = "pending"

    var body: some View {
        NavigationStack {
            Form {
                if model.russianAvailable {
                    Section("RuBERT · русский текст") {
                        Text("Настоящая модель тональности. Расшифровка классов восстановлена по примерам и пока не подтверждена автором. Проценты — softmax, а не проверенная уверенность.")
                        TextEditor(text: $model.russianText).frame(minHeight: 90)
                        Button("Проанализировать текст") { model.analyzeRussianText() }.disabled(model.busy)
                        if !model.russianOutput.isEmpty { Text(model.russianOutput).font(.caption.monospaced()).textSelection(.enabled) }
                        Button("Проверить модель и скорость") { model.runRussian(seconds: nil) }.disabled(model.busy)
                        Button("Замеры и 5 минут нагрузки") { model.runRussian(seconds: 300) }.disabled(model.busy)
                        Text("Свои тексты остаются на устройстве и не записываются в отчёт. Замеры используют фиксированные контрольные фразы.").font(.caption)
                    }
                }
                Section("1 · Автоматический прогон") {
                    Text(model.status)
                    if model.busy { ProgressView(value: model.progress > 0 ? model.progress : nil) }
                    Text("Около 5 минут: три серии замеров, Core ML, остановка эффектов и нагрузка. Оставь приложение открытым.")
                    Button("Начать полный прогон") { model.runAll() }.disabled(model.busy)
                    Button("Короткая проверка без нагрузки") { model.runAll(sustainedSeconds: nil) }.disabled(model.busy)
                    Button("Остановить", role: .destructive) { model.stop() }
                }
                Section("2 · Сравнить ощущения") {
                    Text("Каждый вариант: 3 секунды ровного ритма, 3 секунды ускорения, отдельный удар и остановка. Всего около 8 секунд. Это варианты для сравнения, комфорт ещё не подтверждён.")
                    ForEach(DeviceTactileProfile.allCases) { profile in
                        Button("Проверить \(profile.title)") {
                            calm = "pending"; acceleration = "pending"; accent = "pending"; comfort = "pending"
                            model.tactileScenario(profile)
                        }.disabled(!model.finished || model.busy || model.trialToAssess != nil)
                    }
                    if model.trialToAssess != nil {
                        distinguishability("Ровный ритм", selection: $calm)
                        distinguishability("Ускорение", selection: $acceleration)
                        distinguishability("Отдельный удар", selection: $accent)
                        Picker("Комфорт", selection: $comfort) {
                            Text("Выбери оценку").tag("pending")
                            Text("Комфортно").tag("comfortable")
                            Text("Неприятно / слишком сильно").tag("uncomfortable")
                        }
                        Button("Сохранить оценки") { model.assessTrial(calm: calm, acceleration: acceleration, accent: accent, comfort: comfort) }
                            .disabled([calm, acceleration, accent, comfort].contains("pending"))
                    }
                    ForEach(Array(model.trialSummaries.enumerated()), id: \.offset) { _, text in Text(text).font(.caption) }
                    Menu("Предпочитаемый вариант") {
                        ForEach(DeviceTactileProfile.allCases) { profile in
                            Button(profile.title) { model.prefer(profile) }
                        }
                    }.disabled(!model.finished || model.busy)
                }
                Section("3 · Сворачивание") {
                    Button("Запустить и свернуть приложение") { model.backgroundScenario() }.disabled(!model.finished || model.busy)
                    Text("После запуска сверни приложение во время ритма и вернись. Оно должно сразу замолчать и оставаться тихим.")
                    if model.backgroundObserved {
                        Button("Остановилось и не возобновилось") { model.assessBackground("passed") }.disabled(model.busy)
                        Button("Продолжалось или возобновилось") { model.assessBackground("failed") }.disabled(model.busy)
                    }
                }
                Section("4 · Уменьшение движения") {
                    Text("Включи в настройках iPhone: Универсальный доступ → Движение → Уменьшение движения. Вернись и запусти проверку: ритма не будет, отдельный удар сохранится.")
                    Button("Проверить настройку") { model.checkReduceMotion() }.disabled(!model.finished || model.busy)
                }
                Section("Отчёт") {
                    ForEach(model.summary, id: \.self) { Text($0).font(.caption.monospaced()) }
                    if let url = model.reportURL { ShareLink("Экспортировать текущий отчёт", item: url) }
                    Text("Каждый прогон сохраняется отдельно. Оценки ощущений остаются привязаны к своему варианту.")
                    Text("Общий прогон использует Apple и маленькую арифметическую модель. RuBERT проверяется отдельными кнопками выше. Ритм управляется заданными сигналами. Semantic-качество сюжетной модели здесь не оценивается.").font(.caption)
                }
            }
            .navigationTitle("Qualia Device Lab")
        }
        .task { model.start() }
        .onChange(of: scenePhase) { _, phase in model.sceneChanged(phase) }
    }

    private func distinguishability(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("Выбери оценку").tag("pending")
            Text("Различимо").tag("distinct")
            Text("Есть, но трудно различить").tag("indistinct")
            Text("Не ощущается").tag("absent")
        }
    }
}
#endif
