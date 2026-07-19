import SwiftUI

struct FeaturesPage: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BGIPageTitle(title: "实时触发的自动化任务设置")
            ForEach(appState.features) { feature in
                BGITaskCard(icon: feature.icon, title: feature.name, subtitle: feature.detail) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { appState.featureEnabled(feature.id) },
                            set: { appState.setFeature(feature.id, enabled: $0) }
                        )
                    )
                    .labelsHidden()
                    .disabled(!appState.canControlFeature(feature.id))
                }
            }
        }
    }
}

struct SoloTasksPage: View {
    @EnvironmentObject private var appState: AppState

    private let tasks: [(BGIIcon, String, String)] = [
        (.fgi("\u{f6d2}"), "自动七圣召唤", "全自动打牌 - 点击查看使用教程"),
        (.fgi("\u{f6b2}"), "自动伐木", "装备「王树瑞佑」，通过循环重启游戏刷新并收集木材 - 点击查看使用教程"),
        (.fgi("\u{f71d}"), "自动战斗", "自动执行选择的战斗策略 - 点击查看使用教程"),
        (.fgi("\u{f438}"), "自动秘境", "基于钟离的自动循环刷本 - 点击查看使用教程"),
        (.fgi("\u{e629}"), "自动首领讨伐", "自动传送、战斗并领取奖励"),
        (.fgi("\u{e588}"), "自动幽境危战", "自动传送并进入幽境危战 - 点击查看使用教程"),
        (.fgi("\u{e3a8}"), "全自动钓鱼（单个鱼塘）", "不要携带眼宠！在出现钓鱼F按钮的位置启动本任务 - 点击查看使用教程"),
        (.fgi("\u{f7ff}"), "自动地脉花", "自动定位并刷取地脉花 - 点击查看使用教程"),
        (.symbol("music.note"), "自动千音雅集", "可以自动演奏单个，也可以全自动完成整个专辑 - 点击查看使用教程"),
        (.fgi("\u{e43f}"), "自动烹饪", "在手动烹饪界面运行，自动识别并点击结束烹饪"),
        (.fgi("\u{f4bb}"), "自动分解圣遗物", "指定匹配表达式逐一筛选分解，支持5星圣遗物 - 点击查看使用教程")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BGIPageTitle(title: "独立任务设置")
            ForEach(tasks, id: \.1) { task in
                BGITaskCard(icon: task.0, title: task.1, subtitle: task.2) {
                    Text("Core 暂未开放")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
