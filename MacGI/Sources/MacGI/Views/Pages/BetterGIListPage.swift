import SwiftUI

struct BetterGIListItem: Identifiable {
    let id = UUID()
    let icon: BGIIcon
    let title: String
    let subtitle: String
}

enum BetterGIListButtonMode {
    case none
    case start
    case toggle
}

struct BetterGIListPage: View {
    @EnvironmentObject private var appState: AppState

    let title: String
    let items: [BetterGIListItem]
    let buttonMode: BetterGIListButtonMode

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BGIPageTitle(title: title)
            ForEach(items) { item in
                BGITaskCard(icon: item.icon, title: item.title, subtitle: item.subtitle) {
                    trailing(for: item)
                }
            }
        }
    }

    @ViewBuilder
    private func trailing(for item: BetterGIListItem) -> some View {
        switch buttonMode {
        case .none:
            EmptyView()
        case .start:
            Text("Core 暂未开放")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .toggle:
            Toggle("", isOn: .constant(false))
                .labelsHidden()
                .disabled(true)
        }
    }
}

extension BetterGIListPage {
    static let oneDragonItems = [
        BetterGIListItem(icon: .fgi("\u{f073}"), title: "每日委托", subtitle: "自动完成日常委托并领取奖励"),
        BetterGIListItem(icon: .fgi("\u{f14e}"), title: "领取每日奖励", subtitle: "领取纪行、探索派遣、参量质变仪等常用奖励"),
        BetterGIListItem(icon: .symbol("envelope"), title: "邮件", subtitle: "自动领取游戏内邮件附件"),
        BetterGIListItem(icon: .fgi("\u{f784}"), title: "合成/锻造", subtitle: "按配置执行合成、锻造和材料处理"),
        BetterGIListItem(icon: .fgi("\u{f07a}"), title: "尘歌壶", subtitle: "领取洞天宝钱、信任等奖励"),
        BetterGIListItem(icon: .fgi("\u{f438}"), title: "地脉/秘境", subtitle: "按流程执行消耗体力的日常任务")
    ]

    static let schedulerItems = [
        BetterGIListItem(icon: .fgi("\u{f7a5}"), title: "调度器", subtitle: "按脚本组顺序执行全自动任务"),
        BetterGIListItem(icon: .symbol("folder"), title: "脚本组配置", subtitle: "管理本地脚本组、任务顺序与运行参数"),
        BetterGIListItem(icon: .symbol("arrow.triangle.2.circlepath"), title: "仓库更新", subtitle: "更新脚本仓库与资源索引")
    ]

    static let jsScriptItems = [
        BetterGIListItem(icon: .symbol("doc.text"), title: "JS 脚本列表", subtitle: "查看本地和仓库脚本，后续接入脚本运行器"),
        BetterGIListItem(icon: .symbol("square.and.arrow.down"), title: "导入脚本", subtitle: "从剪贴板、文件或仓库导入脚本"),
        BetterGIListItem(icon: .symbol("curlybraces"), title: "脚本调试", subtitle: "查看脚本参数、日志和运行状态")
    ]

    static let mapTrackingItems = [
        BetterGIListItem(icon: .symbol("map"), title: "地图追踪", subtitle: "按路径文件执行自动寻路和采集"),
        BetterGIListItem(icon: .fgi("\u{e411}"), title: "路径配置", subtitle: "管理路径组、队伍、循环与触发条件"),
        BetterGIListItem(icon: .fgi("\u{f279}"), title: "地图遮罩点位", subtitle: "未来显示在游戏窗口上方的地图点位叠加层")
    ]

    static let recordReplayItems = [
        BetterGIListItem(icon: .symbol("record.circle"), title: "键鼠录制", subtitle: "录制按键和鼠标动作，生成可回放脚本"),
        BetterGIListItem(icon: .symbol("play.rectangle"), title: "脚本回放", subtitle: "选择录制文件并执行回放"),
        BetterGIListItem(icon: .symbol("slider.horizontal.3"), title: "回放参数", subtitle: "速度、延迟和循环次数等参数")
    ]

    static let macroItems = [
        BetterGIListItem(icon: .symbol("gamecontroller"), title: "辅助操控", subtitle: "游戏内常用宏和手动辅助动作"),
        BetterGIListItem(icon: .symbol("bolt"), title: "一键战斗宏", subtitle: "按预设顺序发送技能与攻击动作"),
        BetterGIListItem(icon: .symbol("cursorarrow.click"), title: "点击辅助", subtitle: "等待 Core 暴露窗口检测、点击位置和动作队列能力")
    ]

    static let hotkeyItems = [
        BetterGIListItem(icon: .symbol("bolt"), title: "全局快捷键", subtitle: "启动/暂停、显示 HUD、停止任务等快捷键"),
        BetterGIListItem(icon: .symbol("keyboard"), title: "按键绑定", subtitle: "原神操作键位和自动化动作键位"),
        BetterGIListItem(icon: .symbol("rectangle.connected.to.line.below"), title: "热键作用域", subtitle: "后续接入全局监听和 YAAGL 窗口检测")
    ]

    static let notificationItems = [
        BetterGIListItem(icon: .symbol("bell"), title: "全局通知设置", subtitle: "影响下方所有通知的设置"),
        BetterGIListItem(icon: .symbol("cloud"), title: "启用 Webhook", subtitle: "Webhook 相关设置"),
        BetterGIListItem(icon: .symbol("link"), title: "启用 WebSocket", subtitle: "WebSocket 相关设置"),
        BetterGIListItem(icon: .symbol("bell.badge"), title: "启用 macOS 通知", subtitle: "macOS 通知别与游戏界面重叠，否则易误点通知"),
        BetterGIListItem(icon: .symbol("paperplane"), title: "启用飞书通知", subtitle: "飞书通知相关设置"),
        BetterGIListItem(icon: .symbol("ellipsis.message"), title: "启用 OneBot 通知", subtitle: "OneBot 通知相关设置"),
        BetterGIListItem(icon: .symbol("bubble.left.and.bubble.right"), title: "启用企业微信通知", subtitle: "企业微信通知相关设置"),
        BetterGIListItem(icon: .symbol("envelope"), title: "启用邮箱通知", subtitle: "邮箱相关设置（账号密码完全保存在本地）"),
        BetterGIListItem(icon: .symbol("paperplane.circle"), title: "启用 Telegram 通知", subtitle: "Telegram 机器人相关设置")
    ]
}
