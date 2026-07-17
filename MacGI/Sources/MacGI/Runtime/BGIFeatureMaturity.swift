import Foundation

// MARK: - Feature Maturity

/// Tracks the verification state of each ported feature.
/// Mirrors the upstream BetterGI quality gates.
enum BGIFeatureMaturity: Int, Comparable, Sendable {
    case stub = 0            // 占位符，不能运行
    case unitTested = 1      // 有合成测试，单元通过
    case fixtureVerified = 2 // 固定素材验证通过
    case dryRunVerified = 3  // 真实帧干跑通过
    case realInputVerified = 4 // 真实窗口+真实输入验证
    case productionReady = 5 // 可生产使用

    static func < (lhs: BGIFeatureMaturity, rhs: BGIFeatureMaturity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .stub: "stub"
        case .unitTested: "unit-tested"
        case .fixtureVerified: "fixture-verified"
        case .dryRunVerified: "dry-run-verified"
        case .realInputVerified: "real-input-verified"
        case .productionReady: "production-ready"
        }
    }
}

// MARK: - Feature Registry

/// Central registry of ported features and their maturity.
/// Used by UI to show status and by runtime to gate execution.
enum BGIFeatureRegistry {
    struct Entry: Sendable {
        let name: String
        let maturity: BGIFeatureMaturity
        let enabledInProduction: Bool
    }

    static let features: [String: Entry] = [
        "bigmap-open-ui":        Entry(name: "大地图 UI 打开/识别", maturity: .dryRunVerified, enabledInProduction: true),
        "bigmap-click-confirm":  Entry(name: "大地图点击确认", maturity: .fixtureVerified, enabledInProduction: false),
        "bigmap-coord-projection": Entry(name: "大地图坐标投影", maturity: .unitTested, enabledInProduction: false),
        "bigmap-movemap":        Entry(name: "MoveMapTo 拖图", maturity: .unitTested, enabledInProduction: false),
        "bigmap-sift-assets":    Entry(name: "SIFT 资产解析", maturity: .unitTested, enabledInProduction: false),
        "bigmap-sift-match":     Entry(name: "SIFT KnnMatchRect", maturity: .unitTested, enabledInProduction: false),
        "bigmap-sift-provider":  Entry(name: "SIFT 大地图中心 Provider", maturity: .unitTested, enabledInProduction: false),
        "bigmap-nearest-tp":     Entry(name: "最近传送点查找", maturity: .fixtureVerified, enabledInProduction: true),
        "pathing-move":          Entry(name: "Pathing 移动", maturity: .dryRunVerified, enabledInProduction: true),
        "autoskip-talk":         Entry(name: "自动剧情-对话推进", maturity: .dryRunVerified, enabledInProduction: true),
        "autoskip-popup":        Entry(name: "自动剧情-弹窗关闭", maturity: .unitTested, enabledInProduction: true),
        "autopick":              Entry(name: "自动拾取", maturity: .unitTested, enabledInProduction: true),
        "autoeat":               Entry(name: "自动吃药", maturity: .unitTested, enabledInProduction: false),
        "autofight-dsl":         Entry(name: "自动战斗-DSL解析", maturity: .unitTested, enabledInProduction: true),
        "autofight-combat":      Entry(name: "自动战斗-战斗编排", maturity: .unitTested, enabledInProduction: false),
        "autofishing-yolo":      Entry(name: "自动钓鱼-YOLO检测", maturity: .unitTested, enabledInProduction: false),
        "autofishing-loop":      Entry(name: "自动钓鱼-钓鱼循环", maturity: .stub, enabledInProduction: false),
        "autoboss":              Entry(name: "首领讨伐", maturity: .stub, enabledInProduction: false),
        "autodomain":            Entry(name: "秘境刷本", maturity: .stub, enabledInProduction: false),
        "autoleyline":           Entry(name: "地脉花", maturity: .stub, enabledInProduction: false),
        "autoopenchest":         Entry(name: "自动开宝箱", maturity: .unitTested, enabledInProduction: false),
        "autoartifact":          Entry(name: "圣遗物分解", maturity: .stub, enabledInProduction: false),
        "switchparty":           Entry(name: "切换队伍", maturity: .unitTested, enabledInProduction: true),
        "settime":               Entry(name: "调整时间", maturity: .unitTested, enabledInProduction: true),
        "relogin":               Entry(name: "重新登录", maturity: .unitTested, enabledInProduction: false),
        "vad-onnx":              Entry(name: "VAD ONNX推理", maturity: .unitTested, enabledInProduction: false),
        "vad-capture":           Entry(name: "VAD 音频采集", maturity: .stub, enabledInProduction: false),
        "yolo-inference":        Entry(name: "YOLO 推理管道", maturity: .unitTested, enabledInProduction: true),
        "small-tasks":           Entry(name: "小功能(音乐/烹饪/尘歌壶/兑换码)", maturity: .stub, enabledInProduction: false),
    ]

    /// Whether a feature is safe to run in production.
    static func isProductionReady(_ featureID: String) -> Bool {
        features[featureID]?.enabledInProduction ?? false
    }

    /// Maturity label for UI display.
    static func maturityLabel(_ featureID: String) -> String {
        features[featureID]?.maturity.label ?? "unknown"
    }
}
