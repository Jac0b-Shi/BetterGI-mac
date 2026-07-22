import SwiftUI

struct SkillCdTriggerSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if let settings = appState.skillCdTriggerSettings {
            Group {
                BGISettingLine(
                    title: "角色 CD 配置",
                    subtitle: "为未识别到 CD 数字的指定角色配置默认值；只填写角色名时使用默认 CD"
                ) {
                    VStack(alignment: .trailing, spacing: 8) {
                        ForEach(appState.skillCdRulesDraft.indices, id: \.self) { index in
                            HStack(spacing: 8) {
                                TextField("角色名", text: Binding(
                                    get: { appState.skillCdRulesDraft[index].roleName },
                                    set: { appState.skillCdRulesDraft[index].roleName = $0 }))
                                    .frame(width: 130)
                                TextField("CD（秒）", text: Binding(
                                    get: { appState.skillCdRulesDraft[index].cdValueText },
                                    set: { appState.skillCdRulesDraft[index].cdValueText = $0 }))
                                    .frame(width: 90)
                                Button {
                                    appState.removeSkillCdRule(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("删除配置")
                            }
                        }
                        HStack {
                            Button {
                                appState.addSkillCdRule()
                            } label: {
                                Label("新增配置", systemImage: "plus")
                            }
                            Button("保存角色 CD") { appState.saveSkillCdRules() }
                        }
                    }
                }

                toggleLine(
                    "使用战技时触发",
                    "使用战技时也进行一次识别，否则仅在切人时触发",
                    settings.triggerOnSkillUse
                ) { appState.saveSkillCdTriggerSettings(triggerOnSkillUse: $0) }

                toggleLine(
                    "冷却为 0 时隐藏",
                    "开启后倒计时为 0 时隐藏计时器",
                    settings.hideWhenZero
                ) { appState.saveSkillCdTriggerSettings(hideWhenZero: $0) }

                numberLine("横坐标", "范围 0-1920，默认值 1520", settings.pX) {
                    appState.saveSkillCdTriggerSettings(pX: $0)
                }
                numberLine("纵坐标", "范围 0-1080，默认值 245", settings.pY) {
                    appState.saveSkillCdTriggerSettings(pY: $0)
                }
                numberLine("计时器间隔", "范围 0-200，默认值 91.2", settings.gap) {
                    appState.saveSkillCdTriggerSettings(gap: $0)
                }
                numberLine("计时器大小", "范围 0-10，默认值 1", settings.scale) {
                    appState.saveSkillCdTriggerSettings(scale: $0)
                }

                BGISettingLine(
                    title: "计时器颜色",
                    subtitle: "支持 #RRGGBB 或 #RRGGBBAA 格式"
                ) {
                    VStack(alignment: .trailing, spacing: 8) {
                        SkillCdColorField(title: "CD >= 0.8s 数字", text: $appState.skillCdTextNormalColorDraft)
                        SkillCdColorField(title: "CD >= 0.8s 背景", text: $appState.skillCdBackgroundNormalColorDraft)
                        SkillCdColorField(title: "CD < 0.8s 数字", text: $appState.skillCdTextReadyColorDraft)
                        SkillCdColorField(title: "CD < 0.8s 背景", text: $appState.skillCdBackgroundReadyColorDraft)
                        Button("保存颜色") { appState.saveSkillCdColors() }
                    }
                }
            }
        }
    }

    private func toggleLine(
        _ title: String,
        _ subtitle: String,
        _ value: Bool,
        save: @escaping (Bool) -> Void
    ) -> some View {
        BGISettingLine(title: title, subtitle: subtitle) {
            Toggle("", isOn: Binding(get: { value }, set: { save($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private func numberLine(
        _ title: String,
        _ subtitle: String,
        _ value: Double,
        save: @escaping (Double) -> Void
    ) -> some View {
        BGISettingLine(title: title, subtitle: subtitle) {
            TextField("", value: Binding(get: { value }, set: { save($0) }), format: .number)
                .frame(width: 90)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct SkillCdColorField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.skillCd(hex: text) ?? .clear)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(BGIColors.border, lineWidth: 1))
                .frame(width: 24, height: 24)
            TextField("#RRGGBBAA", text: $text)
                .frame(width: 120)
        }
    }
}

extension Color {
    static func skillCd(hex value: String) -> Color? {
        let hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6 || hex.count == 8, let raw = UInt64(hex, radix: 16) else { return nil }
        let alpha = hex.count == 8 ? Double(raw & 0xFF) / 255 : 1
        let rgb = hex.count == 8 ? raw >> 8 : raw
        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: alpha)
    }
}
