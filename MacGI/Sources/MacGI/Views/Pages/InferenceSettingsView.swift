import SwiftUI

struct InferenceSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var settings = BetterGICoreInferenceSettings()
    @State private var maxThreads = 1
    @State private var loaded = false
    @State private var busy = false
    @State private var message = "正在读取推理设置…"

    var body: some View {
        BGISettingGroup(icon: "cpu", title: "AI 推理设置", subtitle: message) {
            Button("刷新") { perform() }
                .disabled(busy)
        } content: {
            BGISettingLine(title: "推理引擎", subtitle: "macOS 使用随 App 提供的本机 ONNX Runtime；参数保存后重启 BetterGI 生效。") {
                Text("CPU").foregroundStyle(.secondary)
            }
            BGISettingLine(title: "全局 CPU 线程数", subtitle: "0 为 ONNX Runtime 自动选择。") {
                Stepper("\(settings.cpuThreads)", value: $settings.cpuThreads, in: 0...maxThreads)
                    .frame(width: 140)
            }
            BGISettingLine(title: "OCR CPU 策略", subtitle: "文本检测与文字识别可分别限制线程，减少与游戏争用 CPU。") {
                Picker("", selection: $settings.paddleOcrCpu.mode) {
                    Text("跟随全局").tag(0)
                    Text("ORT 自动调度").tag(1)
                    Text("游戏流畅优先").tag(2)
                    Text("自定义").tag(3)
                }.labelsHidden().frame(width: 170)
            }
            if settings.paddleOcrCpu.mode == 3 {
                BGISettingLine(title: "检测 / 识别线程数", subtitle: "0 表示自动选择。") {
                    Stepper("检测 \(settings.paddleOcrCpu.detectionThreads)", value: $settings.paddleOcrCpu.detectionThreads, in: 0...maxThreads)
                    Stepper("识别 \(settings.paddleOcrCpu.recognitionThreads)", value: $settings.paddleOcrCpu.recognitionThreads, in: 0...maxThreads)
                }
                BGISettingLine(title: "节点并行执行", subtitle: "默认顺序执行；并行策略仅作用于 OCR。") {
                    Toggle("", isOn: $settings.paddleOcrCpu.parallelExecution).labelsHidden()
                    if settings.paddleOcrCpu.parallelExecution {
                        Stepper("线程 \(settings.paddleOcrCpu.interOpThreads)", value: $settings.paddleOcrCpu.interOpThreads, in: 0...maxThreads)
                    }
                }
            }
            if settings.paddleOcrCpu.mode >= 2 {
                BGISettingLine(title: "允许线程自旋", subtitle: "关闭可减少空闲 CPU 占用，可能增加唤醒延迟。") {
                    Toggle("", isOn: $settings.paddleOcrCpu.allowSpinning).labelsHidden()
                }
            }
            BGISettingLine(title: "保存与验证", subtitle: "验证使用已保存参数及独立模型会话，耗时包含模型加载。") {
                Button("保存") { perform(save: true) }
                Button("验证 OCR") { perform(scene: "ocr") }
                Button("验证古树") { perform(scene: "tree") }
            }
        }
        .disabled(busy || !loaded && appState.betterGICoreSupervisor == nil)
        .task { perform() }
    }

    private func perform(save: Bool = false, scene: String? = nil) {
        guard !busy else { return }
        guard let supervisor = appState.betterGICoreSupervisor else {
            message = "Core 尚未就绪，请稍后刷新。"
            return
        }
        busy = true
        let draft = settings
        Task {
            defer { busy = false }
            do {
                if let scene {
                    message = try await supervisor.benchmarkInference(scene: scene)
                } else {
                    let result = try await supervisor.inferenceSettings(save ? draft : nil)
                    settings = result.saved
                    maxThreads = result.maxThreads
                    loaded = true
                    message = result.pendingRestart ? "已保存，重启 BetterGI 后生效。" :
                        result.startupMessage.isEmpty ? "当前使用本机 CPU 推理。" : result.startupMessage
                }
            } catch { message = error.localizedDescription }
        }
    }
}
