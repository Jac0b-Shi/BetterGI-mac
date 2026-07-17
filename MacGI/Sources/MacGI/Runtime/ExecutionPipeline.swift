import CoreGraphics
import Foundation

// MARK: - BGI Recognition Definitions

enum RecognitionType: String, CaseIterable, Codable, Identifiable, Sendable {
    case none
    case templateMatch
    case colorMatch
    case ocrMatch
    case ocr
    case colorRangeAndOcr
    case detect

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "None"
        case .templateMatch: "TemplateMatch"
        case .colorMatch: "ColorMatch"
        case .ocrMatch: "OcrMatch"
        case .ocr: "Ocr"
        case .colorRangeAndOcr: "ColorRangeAndOcr"
        case .detect: "Detect"
        }
    }
}

enum TemplateMatchMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case cCoeffNormed
    case cCorrNormed
    case sqDiffNormed

    var id: String { rawValue }
}

enum OcrEngineType: String, CaseIterable, Codable, Identifiable, Sendable {
    case paddle = "Paddle"
    case yap = "Yap"

    var id: String { rawValue }
}

enum GameUiCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case unknown
    case main
    case talk
    case bigMap

    var id: String { rawValue }
}

enum RecognitionCoordinateSpace: String, CaseIterable, Codable, Identifiable, Sendable {
    /// BetterGI normalizes `CaptureContent.CaptureRectArea` to 1920x1080 for most assets.
    case bgi1080P

    /// Normalized [0, 1] fallback for Swift UI previews and HUD drawing.
    case normalized

    var id: String { rawValue }
}

struct RecognitionROI: Equatable, Codable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var coordinateSpace: RecognitionCoordinateSpace

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    func normalizedRect() -> CGRect {
        switch coordinateSpace {
        case .normalized:
            return rect
        case .bgi1080P:
            return CGRect(x: x / 1920.0, y: y / 1080.0, width: width / 1920.0, height: height / 1080.0)
        }
    }

    static func bgi1080P(x: Double, y: Double, width: Double, height: Double) -> RecognitionROI {
        RecognitionROI(x: x, y: y, width: width, height: height, coordinateSpace: .bgi1080P)
    }

    static func normalized(_ roi: NormalizedROI) -> RecognitionROI {
        RecognitionROI(x: roi.x, y: roi.y, width: roi.w, height: roi.h, coordinateSpace: .normalized)
    }
}

struct BGIColorScalar: Equatable, Codable, Sendable {
    var b: Double
    var g: Double
    var r: Double
    var a: Double

    static let maskGreen = BGIColorScalar(b: 0, g: 255, r: 0, a: 255)
}

/// Portable description of upstream BetterGI's `RecognitionObject`.
///
/// Pixel buffers and OpenCV `Mat` references are represented by resource names
/// on the Swift side. The field names intentionally stay close to the C# model
/// so a later Rust/OpenCV bridge can map this without a second translation layer.
struct RecognitionObject: Identifiable, Equatable, Codable, Sendable {
    let id: String
    var recognitionType: RecognitionType
    var regionOfInterest: RecognitionROI?
    var name: String?

    // Template match
    var templateAssetName: String?
    var threshold: Double
    var use3Channels: Bool
    var templateMatchMode: TemplateMatchMode
    var useMask: Bool
    var maskColor: BGIColorScalar
    var drawOnWindow: Bool
    var maxMatchCount: Int
    var useBinaryMatch: Bool
    var binaryThreshold: Int

    // Color match
    var colorConversionCode: Int
    var lowerColor: BGIColorScalar?
    var upperColor: BGIColorScalar?
    var matchCount: Int

    // OCR
    var ocrEngine: OcrEngineType
    var replaceDictionary: [String: [String]]
    var allContainMatchText: [String]
    var oneContainMatchText: [String]
    var regexMatchText: [String]
    var text: String

    // Swift runtime metadata
    var featureID: String?
    var tags: [String]
    var isEnabled: Bool

    init(
        id: String,
        recognitionType: RecognitionType,
        regionOfInterest: RecognitionROI? = nil,
        name: String? = nil,
        templateAssetName: String? = nil,
        threshold: Double = 0.8,
        use3Channels: Bool = false,
        templateMatchMode: TemplateMatchMode = .cCoeffNormed,
        useMask: Bool = false,
        maskColor: BGIColorScalar = .maskGreen,
        drawOnWindow: Bool = false,
        maxMatchCount: Int = -1,
        useBinaryMatch: Bool = false,
        binaryThreshold: Int = 128,
        colorConversionCode: Int = 4,
        lowerColor: BGIColorScalar? = nil,
        upperColor: BGIColorScalar? = nil,
        matchCount: Int = 1,
        ocrEngine: OcrEngineType = .paddle,
        replaceDictionary: [String: [String]] = [:],
        allContainMatchText: [String] = [],
        oneContainMatchText: [String] = [],
        regexMatchText: [String] = [],
        text: String = "",
        featureID: String? = nil,
        tags: [String] = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.recognitionType = recognitionType
        self.regionOfInterest = regionOfInterest
        self.name = name
        self.templateAssetName = templateAssetName
        self.threshold = threshold
        self.use3Channels = use3Channels
        self.templateMatchMode = templateMatchMode
        self.useMask = useMask
        self.maskColor = maskColor
        self.drawOnWindow = drawOnWindow
        self.maxMatchCount = maxMatchCount
        self.useBinaryMatch = useBinaryMatch
        self.binaryThreshold = binaryThreshold
        self.colorConversionCode = colorConversionCode
        self.lowerColor = lowerColor
        self.upperColor = upperColor
        self.matchCount = matchCount
        self.ocrEngine = ocrEngine
        self.replaceDictionary = replaceDictionary
        self.allContainMatchText = allContainMatchText
        self.oneContainMatchText = oneContainMatchText
        self.regexMatchText = regexMatchText
        self.text = text
        self.featureID = featureID
        self.tags = tags
        self.isEnabled = isEnabled
    }
}

struct RecognitionObservation: Identifiable, Equatable, Sendable {
    let id: String
    let objectID: String
    let objectName: String
    let recognitionType: RecognitionType
    let normalizedRect: CGRect
    let confidence: Double
    let text: String?
    let frameIndex: UInt64
    let timestamp: Date

    var displayText: String {
        if let text, !text.isEmpty {
            return "\(recognitionType.label): \(text)"
        }
        return "\(recognitionType.label): \(objectName)"
    }
}

extension RecognitionObject {
    static let bgiAutoPickObjects: [RecognitionObject] = [
        RecognitionObject(
            id: "AutoPick.FRo",
            recognitionType: .templateMatch,
            regionOfInterest: .bgi1080P(x: 1090, y: 330, width: 60, height: 420),
            name: "F",
            templateAssetName: "GameTask/AutoPick/Assets/1920x1080/F.png",
            featureID: "auto-pickup",
            tags: ["AutoPick", "FRo"]
        ),
        RecognitionObject(
            id: "AutoPick.ChatIconRo",
            recognitionType: .templateMatch,
            name: "ChatIcon",
            templateAssetName: "GameTask/AutoSkip/Assets/1920x1080/icon_option.png",
            featureID: "auto-pickup",
            tags: ["AutoPick", "ExcludeIcon"]
        ),
        RecognitionObject(
            id: "AutoPick.SettingsIconRo",
            recognitionType: .templateMatch,
            name: "SettingsIcon",
            templateAssetName: "GameTask/AutoPick/Assets/1920x1080/icon_settings.png",
            featureID: "auto-pickup",
            tags: ["AutoPick", "ExcludeIcon"]
        ),
        RecognitionObject(
            id: "AutoPick.LRo",
            recognitionType: .templateMatch,
            regionOfInterest: .bgi1080P(x: 1810, y: 550, width: 70, height: 100),
            name: "L",
            templateAssetName: "GameTask/AutoPick/Assets/1920x1080/L.png",
            featureID: "auto-pickup",
            tags: ["AutoPick", "BlockPick"]
        ),
        RecognitionObject(
            id: "AutoPick.ChatPickRo",
            recognitionType: .templateMatch,
            regionOfInterest: .bgi1080P(x: 1200, y: 350, width: 50, height: 510),
            name: "chatPickF",
            templateAssetName: "GameTask/AutoPick/Assets/1920x1080/F.png",
            featureID: "auto-dialog",
            tags: ["AutoPick", "DialogueOption"]
        )
    ]

    static let bgiAutoSkipObjects: [RecognitionObject] = [
        RecognitionObject(
            id: "AutoSkip.StopAutoButtonRo",
            recognitionType: .templateMatch,
            regionOfInterest: .bgi1080P(x: 0, y: 0, width: 384, height: 135),
            name: "StopAutoButton",
            templateAssetName: "GameTask/AutoSkip/Assets/1920x1080/stop_auto.png",
            drawOnWindow: true,
            featureID: "auto-dialog",
            tags: ["AutoSkip"]
        ),
        RecognitionObject(
            id: "AutoSkip.DisabledUiButtonRo",
            recognitionType: .templateMatch,
            regionOfInterest: .bgi1080P(x: 0, y: 0, width: 640, height: 135),
            name: "DisabledUiButton",
            templateAssetName: "GameTask/AutoSkip/Assets/1920x1080/disabled_ui.png",
            drawOnWindow: true,
            featureID: "auto-dialog",
            tags: ["AutoSkip"]
        ),
        RecognitionObject(
            id: "AutoSkip.PlayingTextRo",
            recognitionType: .ocrMatch,
            regionOfInterest: .bgi1080P(x: 100, y: 35, width: 85, height: 35),
            name: "PlayingText",
            oneContainMatchText: ["播", "番", "放", "中"],
            featureID: "auto-dialog",
            tags: ["AutoSkip", "TalkState"]
        ),
        RecognitionObject(
            id: "AutoSkip.OptionIconRo",
            recognitionType: .templateMatch,
            regionOfInterest: .bgi1080P(x: 960, y: 90, width: 640, height: 980),
            name: "OptionIcon",
            templateAssetName: "GameTask/AutoSkip/Assets/1920x1080/icon_option.png",
            maxMatchCount: 8,
            featureID: "auto-dialog",
            tags: ["AutoSkip", "DialogueOption"]
        ),
        RecognitionObject(
            id: "AutoSkip.DailyRewardIconRo",
            recognitionType: .templateMatch,
            regionOfInterest: .bgi1080P(x: 960, y: 90, width: 640, height: 980),
            name: "DailyRewardIcon",
            templateAssetName: "GameTask/AutoSkip/Assets/1920x1080/icon_daily_reward.png",
            featureID: "auto-dialog",
            tags: ["AutoSkip", "DialogueOption", "DailyReward"]
        ),
        RecognitionObject(
            id: "AutoSkip.ExploreIconRo",
            recognitionType: .templateMatch,
            regionOfInterest: .bgi1080P(x: 960, y: 90, width: 640, height: 980),
            name: "ExploreIcon",
            templateAssetName: "GameTask/AutoSkip/Assets/1920x1080/icon_explore.png",
            featureID: "auto-dialog",
            tags: ["AutoSkip", "DialogueOption", "Explore"]
        ),
        RecognitionObject(
            id: "AutoSkip.ExclamationIconRo",
            recognitionType: .templateMatch,
            regionOfInterest: .bgi1080P(x: 960, y: 90, width: 640, height: 980),
            name: "IconExclamation",
            templateAssetName: "GameTask/AutoSkip/Assets/1920x1080/icon_exclamation.png",
            featureID: "auto-dialog",
            tags: ["AutoSkip", "DialogueOption"]
        ),
        RecognitionObject(
            id: "AutoSkip.PageCloseRo",
            recognitionType: .templateMatch,
            regionOfInterest: .bgi1080P(x: 1680, y: 0, width: 240, height: 135),
            name: "PageClose",
            templateAssetName: "GameTask/AutoSkip/Assets/1920x1080/page_close.png",
            drawOnWindow: true,
            featureID: "auto-dialog",
            tags: ["AutoSkip", "ClosePopup"]
        ),
        RecognitionObject(
            id: "AutoSkip.SubmitGoodsRo",
            recognitionType: .templateMatch,
            regionOfInterest: .bgi1080P(x: 0, y: 0, width: 960, height: 360),
            name: "SubmitGoods",
            templateAssetName: "GameTask/AutoSkip/Assets/1920x1080/submit_goods.png",
            threshold: 0.9,
            use3Channels: true,
            templateMatchMode: .cCorrNormed,
            drawOnWindow: true,
            featureID: "auto-dialog",
            tags: ["AutoSkip", "SubmitGoods"]
        ),
        RecognitionObject(
            id: "AutoSkip.HangoutSkipRo",
            recognitionType: .templateMatch,
            regionOfInterest: .bgi1080P(x: 0, y: 0, width: 384, height: 135),
            name: "HangoutSkip",
            templateAssetName: "GameTask/AutoSkip/Assets/1920x1080/hangout_skip.png",
            featureID: "auto-hangout",
            tags: ["AutoSkip", "Hangout"]
        ),
        RecognitionObject(
            id: "AutoSkip.HangoutSelected",
            recognitionType: .templateMatch,
            regionOfInterest: .bgi1080P(x: 0, y: 0, width: 1920, height: 1080),
            name: "HangoutSelected",
            templateAssetName: "GameTask/AutoSkip/Assets/1920x1080/hangout_selected.png",
            threshold: 0.85,
            tags: ["AutoSkip", "Hangout"]
        ),
        RecognitionObject(
            id: "AutoSkip.HangoutUnselected",
            recognitionType: .templateMatch,
            regionOfInterest: .bgi1080P(x: 0, y: 0, width: 1920, height: 1080),
            name: "HangoutUnselected",
            templateAssetName: "GameTask/AutoSkip/Assets/1920x1080/hangout_unselected.png",
            threshold: 0.85,
            tags: ["AutoSkip", "Hangout"]
        )
    ]

    static let bgiQuickTeleportBigMapStatusObjects: [RecognitionObject] = [
        RecognitionObject(
            id: "QuickTeleport.MapScaleButtonRo",
            recognitionType: .templateMatch,
            regionOfInterest: .bgi1080P(x: 30, y: 440, width: 40, height: 200),
            name: "MapScaleButton",
            templateAssetName: "GameTask/QuickTeleport/Assets/1920x1080/MapScaleButton.png",
            featureID: "quick-teleport",
            tags: ["QuickTeleport", "BigMap", "Status"]
        ),
        RecognitionObject(
            id: "QuickTeleport.MapSettingsButtonRo",
            recognitionType: .templateMatch,
            regionOfInterest: .bgi1080P(x: 25, y: 990, width: 58, height: 62),
            name: "MapSettingsButton",
            templateAssetName: "GameTask/QuickTeleport/Assets/1920x1080/MapSettingsButton.png",
            featureID: "quick-teleport",
            tags: ["QuickTeleport", "BigMap", "Status"]
        ),
        RecognitionObject(
            id: "QuickTeleport.MapUndergroundSwitchButtonRo",
            recognitionType: .templateMatch,
            regionOfInterest: .bgi1080P(x: 1800, y: 250, width: 90, height: 570),
            name: "MapUndergroundSwitchButton",
            templateAssetName: "GameTask/QuickTeleport/Assets/1920x1080/MapUndergroundSwitchButton.png",
            use3Channels: true,
            featureID: "quick-teleport",
            tags: ["QuickTeleport", "BigMap", "Underground"]
        )
    ]

    static let bgiQuickTeleportTeleportObjects: [RecognitionObject] = [
        RecognitionObject(
            id: "QuickTeleport.TeleportButtonRo",
            recognitionType: .templateMatch,
            regionOfInterest: .bgi1080P(x: 1440, y: 960, width: 100, height: 120),
            name: "GoTeleport",
            templateAssetName: "GameTask/QuickTeleport/Assets/1920x1080/GoTeleport.png",
            featureID: "quick-teleport",
            tags: ["QuickTeleport", "TeleportButton"]
        ),
        RecognitionObject(
            id: "QuickTeleport.MapCloseButtonRo",
            recognitionType: .templateMatch,
            regionOfInterest: .bgi1080P(x: 1813, y: 19, width: 58, height: 58),
            name: "MapCloseButton",
            templateAssetName: "GameTask/QuickTeleport/Assets/1920x1080/MapCloseButton.png",
            featureID: "quick-teleport",
            tags: ["QuickTeleport", "MapCloseButton"]
        )
    ]

    static let bgiQuickTeleportMapChooseIconObjects: [RecognitionObject] = [
        quickTeleportMapChooseIconObject(assetName: "TeleportWaypoint.png", threshold: 0.7),
        quickTeleportMapChooseIconObject(assetName: "StatueOfTheSeven.png"),
        quickTeleportMapChooseIconObject(assetName: "Domain.png"),
        quickTeleportMapChooseIconObject(assetName: "Domain2.png"),
        quickTeleportMapChooseIconObject(assetName: "ObsidianTotemPole.png"),
        quickTeleportMapChooseIconObject(assetName: "PortableWaypoint.png"),
        quickTeleportMapChooseIconObject(assetName: "Mansion.png"),
        quickTeleportMapChooseIconObject(assetName: "SubSpaceWaypoint.png"),
        quickTeleportMapChooseIconObject(assetName: "NodKraiMeetingPoint.png"),
        quickTeleportMapChooseIconObject(assetName: "TabletOfTona.png")
    ]

    static let bgiCommonElementPaimonMenuObject = RecognitionObject(
        id: "Common.Element.PaimonMenuRo",
        recognitionType: .templateMatch,
        regionOfInterest: RecognitionROI(x: 0, y: 0, width: 0.25, height: 0.25, coordinateSpace: .normalized),
        name: "PaimonMenu",
        templateAssetName: "GameTask/Common/Element/Assets/1920x1080/paimon_menu.png",
        threshold: 0.72,
        featureID: "map-tracking",
        tags: ["Common", "Element", "PaimonMenu", "MainUI"]
    )

    static let bgiCommonElementMainUIObjects: [RecognitionObject] = [
        bgiCommonElementPaimonMenuObject
    ]

    static let bgiCommonElementPageCloseWhiteObject = RecognitionObject(
        id: "Common.Element.PageCloseWhiteRo",
        recognitionType: .templateMatch,
        regionOfInterest: .bgi1080P(x: 1680, y: 0, width: 240, height: 135),
        name: "PageCloseWhite",
        templateAssetName: "GameTask/Common/Element/Assets/1920x1080/page_close_white.png",
        drawOnWindow: true,
        tags: ["Common", "Element", "PageCloseWhite"]
    )

    static let bgiAutoWoodMenuBagObject = RecognitionObject(
        id: "AutoWood.MenuBagRo",
        recognitionType: .templateMatch,
        regionOfInterest: .bgi1080P(x: 0, y: 0, width: 960, height: 1080),
        name: "MenuBag",
        templateAssetName: "GameTask/AutoWood/Assets/1920x1080/menu_bag.png",
        tags: ["AutoWood", "Relogin", "Menu"]
    )

    static let bgiAutoWoodConfirmObject = RecognitionObject(
        id: "AutoWood.ConfirmRo",
        recognitionType: .templateMatch,
        name: "AutoWoodConfirm",
        templateAssetName: "GameTask/AutoWood/Assets/1920x1080/confirm.png",
        tags: ["AutoWood", "Relogin", "Confirm"]
    )

    static let bgiAutoWoodEnterGameObject = RecognitionObject(
        id: "AutoWood.EnterGameRo",
        recognitionType: .templateMatch,
        regionOfInterest: .bgi1080P(x: 0, y: 540, width: 1920, height: 540),
        name: "EnterGame",
        templateAssetName: "GameTask/AutoWood/Assets/1920x1080/exit_welcome.png",
        tags: ["AutoWood", "Relogin", "EnterGame"]
    )

    static let bgiAutoWoodReloginObjects: [RecognitionObject] = [
        bgiAutoWoodMenuBagObject,
        bgiAutoWoodConfirmObject,
        bgiAutoWoodEnterGameObject
    ]

    static let bgiPartyChooseViewObject = RecognitionObject(
        id: "Common.PartyBtnChooseViewRo",
        recognitionType: .templateMatch,
        regionOfInterest: .bgi1080P(x: 1700, y: 936, width: 220, height: 144),
        name: "PartyBtnChooseView",
        templateAssetName: "GameTask/Common/Element/Assets/1920x1080/party_btn_choose_view.png",
        threshold: 0.8,
        tags: ["Common", "Party", "ChooseView"]
    )

    static let bgiPartyDeleteObject = RecognitionObject(
        id: "Common.PartyBtnDeleteRo",
        recognitionType: .templateMatch,
        regionOfInterest: .bgi1080P(x: 575, y: 867, width: 54, height: 54),
        name: "PartyBtnDelete",
        templateAssetName: "GameTask/Common/Element/Assets/1920x1080/party_btn_delete.png",
        threshold: 0.8,
        tags: ["Common", "Party", "Delete"]
    )

    static let bgiPartyChooseViewObjects: [RecognitionObject] = [
        bgiPartyChooseViewObject
    ]

    static let bgiPartyDeleteObjects: [RecognitionObject] = [
        bgiPartyDeleteObject
    ]

    static let bgiFishingExitButtonObject = RecognitionObject(
        id: "AutoFishing.ExitFishingButtonRo",
        recognitionType: .templateMatch,
        regionOfInterest: .bgi1080P(x: 1850, y: 1000, width: 70, height: 80),
        name: "ExitFishing",
        templateAssetName: "GameTask/AutoFishing/Assets/1920x1080/exit_fishing.png",
        threshold: 0.8,
        tags: ["AutoFishing", "Exit"]
    )

    static let bgiFishingExitButtonObjects: [RecognitionObject] = [
        bgiFishingExitButtonObject
    ]

    static let bgiAutoFightConfirmObject = RecognitionObject(
        id: "AutoFight.ConfirmRa",
        recognitionType: .templateMatch,
        regionOfInterest: .bgi1080P(x: 960, y: 540, width: 960, height: 540),
        name: "Confirm",
        templateAssetName: "GameTask/AutoFight/Assets/1920x1080/confirm.png",
        threshold: 0.8,
        featureID: "auto-fight",
        tags: ["AutoFight", "Confirm", "RevivePrompt"]
    )

    static let bgiRevivePromptTextObject = RecognitionObject(
        id: "Common.BvStatus.RevivePromptText",
        recognitionType: .ocr,
        regionOfInterest: RecognitionROI(x: 0, y: 0, width: 1, height: 0.5, coordinateSpace: .normalized),
        name: "RevivePromptText",
        oneContainMatchText: ["复苏", "Revive"],
        featureID: "bgi-status",
        tags: ["Common", "BvStatus", "RevivePrompt"]
    )

    // MARK: - AutoEat

    static let bgiAutoEatRecoveryObject = RecognitionObject(
        id: "AutoEat.RecoveryRo",
        recognitionType: .templateMatch,
        regionOfInterest: RecognitionROI(x: 0, y: 0, width: 1, height: 1, coordinateSpace: .normalized),
        name: "Recovery",
        templateAssetName: "GameTask/AutoEat/Assets/1920x1080/Recovery.png",
        threshold: 0.8,
        tags: ["AutoEat", "Recovery"]
    )

    static let bgiAutoEatResurrectionObject = RecognitionObject(
        id: "AutoEat.ResurrectionRo",
        recognitionType: .templateMatch,
        regionOfInterest: RecognitionROI(x: 0, y: 0, width: 1, height: 1, coordinateSpace: .normalized),
        name: "Resurrection",
        templateAssetName: "GameTask/AutoEat/Assets/1920x1080/Resurrection.png",
        threshold: 0.8,
        tags: ["AutoEat", "Resurrection"]
    )

    static let bgiAutoEatObjects: [RecognitionObject] = [
        bgiAutoEatRecoveryObject,
        bgiAutoEatResurrectionObject
    ]

    // MARK: - Small Features

    static let bgiGameLoadingEnterGameObject = RecognitionObject(
        id: "GameLoading.EnterGameRo",
        recognitionType: .templateMatch,
        regionOfInterest: RecognitionROI(x: 0, y: 0, width: 1, height: 1, coordinateSpace: .normalized),
        name: "EnterGame",
        templateAssetName: "GameTask/GameLoading/Assets/1920x1080/enter_game.png",
        threshold: 0.85,
        tags: ["GameLoading"]
    )

    static let bgiGameLoadingObjects: [RecognitionObject] = [
        bgiGameLoadingEnterGameObject
    ]

    static let bgiSereniteaPotIconObject = RecognitionObject(
        id: "SereniteaPot.IconRo",
        recognitionType: .templateMatch,
        regionOfInterest: RecognitionROI(x: 0, y: 0, width: 1, height: 0.3, coordinateSpace: .normalized),
        name: "SereniteaPot",
        templateAssetName: "GameTask/QuickSereniteaPot/Assets/1920x1080/SereniteaPotIcon.png",
        threshold: 0.85,
        tags: ["SereniteaPot"]
    )

    static let bgiSereniteaPotObjects: [RecognitionObject] = [
        bgiSereniteaPotIconObject
    ]

    static let bgiCookIconObject = RecognitionObject(
        id: "Common.CookIconRo",
        recognitionType: .templateMatch,
        regionOfInterest: RecognitionROI(x: 0, y: 0, width: 0.3, height: 0.3, coordinateSpace: .normalized),
        name: "CookIcon",
        templateAssetName: "GameTask/Common/Element/Assets/1920x1080/ui_left_top_cook_icon.png",
        threshold: 0.85,
        tags: ["Common", "Cook"]
    )

    static let bgiCookObjects: [RecognitionObject] = [bgiCookIconObject]

    static let bgiP0Defaults: [RecognitionObject] =
        bgiAutoPickObjects
        + bgiAutoSkipObjects
        + bgiQuickTeleportBigMapStatusObjects
        + bgiQuickTeleportTeleportObjects
        + bgiQuickTeleportMapChooseIconObjects
        + bgiCommonElementMainUIObjects
        + [bgiCommonElementPageCloseWhiteObject, bgiAutoFightConfirmObject]
        + bgiAutoWoodReloginObjects
        + bgiPartyChooseViewObjects + bgiPartyDeleteObjects
        + bgiFishingExitButtonObjects
        + bgiAutoEatObjects
        + bgiFishingBiteObjects
        + bgiChestObjects
        + bgiSalvageObjects
        + bgiGameLoadingObjects + bgiSereniteaPotObjects + bgiCookObjects

    private static func quickTeleportMapChooseIconObject(
        assetName: String,
        threshold: Double = 0.8
    ) -> RecognitionObject {
        RecognitionObject(
            id: "QuickTeleport.\(assetName)MapChooseIcon",
            recognitionType: .templateMatch,
            regionOfInterest: .bgi1080P(x: 1270, y: 100, width: 50, height: 880),
            name: "\(assetName)MapChooseIcon",
            templateAssetName: "GameTask/QuickTeleport/Assets/1920x1080/\(assetName)",
            threshold: threshold,
            maxMatchCount: 20,
            featureID: "quick-teleport",
            tags: ["QuickTeleport", "MapChooseIcon"]
        )
    }
}

// MARK: - Trigger Definitions

enum TaskTriggerID: String, CaseIterable, Codable, Identifiable, Sendable {
    case recognitionTest = "RecognitionTest"
    case gameLoading = "GameLoading"
    case autoPick = "AutoPick"
    case quickTeleport = "QuickTeleport"
    case autoSkip = "AutoSkip"
    case autoFish = "AutoFish"
    case autoEat = "AutoEat"
    case mapMask = "MapMask"
    case skillCd = "SkillCd"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recognitionTest: "识别测试"
        case .gameLoading: "游戏加载"
        case .autoPick: "自动拾取"
        case .quickTeleport: "快速传送"
        case .autoSkip: "自动剧情"
        case .autoFish: "自动钓鱼"
        case .autoEat: "自动吃药"
        case .mapMask: "地图遮罩"
        case .skillCd: "技能冷却"
        }
    }
}

struct TaskTriggerDescriptor: Identifiable, Equatable, Sendable {
    let id: TaskTriggerID
    var featureID: String
    var name: String
    var isEnabled: Bool
    var priority: Int
    var isExclusive: Bool
    var isBackgroundRunning: Bool
    var supportedGameUiCategory: GameUiCategory
    var recognitionObjectIDs: [String]
}

extension TaskTriggerDescriptor {
    static let bgiInitialTriggers: [TaskTriggerDescriptor] = [
        TaskTriggerDescriptor(
            id: .gameLoading,
            featureID: "game-loading",
            name: "游戏加载",
            isEnabled: false,
            priority: 100,
            isExclusive: false,
            isBackgroundRunning: false,
            supportedGameUiCategory: .unknown,
            recognitionObjectIDs: []
        ),
        TaskTriggerDescriptor(
            id: .autoPick,
            featureID: "auto-pickup",
            name: "自动拾取",
            isEnabled: true,
            priority: 30,
            isExclusive: false,
            isBackgroundRunning: false,
            supportedGameUiCategory: .unknown,
            recognitionObjectIDs: RecognitionObject.bgiAutoPickObjects.map(\.id)
        ),
        TaskTriggerDescriptor(
            id: .autoSkip,
            featureID: "auto-dialog",
            name: "自动剧情",
            isEnabled: true,
            priority: 20,
            isExclusive: false,
            isBackgroundRunning: false,
            supportedGameUiCategory: .talk,
            recognitionObjectIDs: RecognitionObject.bgiAutoSkipObjects.map(\.id) + ["AutoPick.ChatPickRo"]
        ),
        TaskTriggerDescriptor(
            id: .autoFish,
            featureID: "semi-auto-fishing",
            name: "自动钓鱼",
            isEnabled: false,
            priority: 10,
            isExclusive: false,
            isBackgroundRunning: false,
            supportedGameUiCategory: .unknown,
            recognitionObjectIDs: []
        ),
        TaskTriggerDescriptor(
            id: .autoEat,
            featureID: "auto-heal",
            name: "自动吃药",
            isEnabled: false,
            priority: 10,
            isExclusive: false,
            isBackgroundRunning: false,
            supportedGameUiCategory: .unknown,
            recognitionObjectIDs: []
        ),
        TaskTriggerDescriptor(
            id: .mapMask,
            featureID: "map-overlay",
            name: "地图遮罩",
            isEnabled: false,
            priority: 0,
            isExclusive: false,
            isBackgroundRunning: false,
            supportedGameUiCategory: .unknown,
            recognitionObjectIDs: []
        ),
        TaskTriggerDescriptor(
            id: .skillCd,
            featureID: "cooldown-reminder",
            name: "技能冷却",
            isEnabled: false,
            priority: 0,
            isExclusive: false,
            isBackgroundRunning: false,
            supportedGameUiCategory: .unknown,
            recognitionObjectIDs: []
        )
    ]
}

struct TriggerDecision: Identifiable, Equatable, Sendable {
    let id: String
    let triggerID: TaskTriggerID
    let priority: Int
    let reason: String
    let confidence: Double
    let actions: [InputAction]
    let observationIDs: [String]
    let timestamp: Date
}

struct RuntimeCostMetrics: Equatable, Sendable {
    var processingCostMs: Double
    var captureCostMs: Double
    var triggerCostMs: Double
    var confidence: Double
    var skippedTicks: UInt32
}

struct AutomationRuntimeSnapshot: Equatable, Sendable {
    var frameIndex: UInt64
    var timestamp: Date
    var currentGameUiCategory: GameUiCategory
    var recognitionObjects: [RecognitionObject]
    var observations: [RecognitionObservation]
    var decisions: [TriggerDecision]
    var metrics: RuntimeCostMetrics

    static let empty = AutomationRuntimeSnapshot(
        frameIndex: 0,
        timestamp: Date(),
        currentGameUiCategory: .unknown,
        recognitionObjects: RecognitionObject.bgiP0Defaults,
        observations: [],
        decisions: [],
        metrics: RuntimeCostMetrics(
            processingCostMs: 0,
            captureCostMs: 0,
            triggerCostMs: 0,
            confidence: 0,
            skippedTicks: 0
        )
    )
}

protocol TaskTrigger {
    var descriptor: TaskTriggerDescriptor { get }
    func onCapture(_ content: CapturedFrame, observations: [RecognitionObservation]) -> TriggerDecision?
}

// MARK: - Script Group Scheduler

enum BGIScriptGroupProjectType: String, CaseIterable, Codable, Identifiable, Sendable {
    case javascript = "Javascript"
    case keyMouse = "KeyMouse"
    case pathing = "Pathing"
    case shell = "Shell"

    var id: String { rawValue }
}

enum BGIScriptGroupProjectStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case enabled = "Enabled"
    case disabled = "Disabled"

    var id: String { rawValue }
}

/// Swift mirror of BetterGI `ScriptGroupProject`.
///
/// The field semantics and string values intentionally follow upstream
/// `ScriptGroupProject`; Codable keeps Swift's default camelCase keys to match
/// BetterGI `ConfigService.JsonOptions`.
struct BGIScriptGroupProject: Identifiable, Equatable, Codable, Sendable {
    var index: Int
    var name: String
    var folderName: String
    var type: BGIScriptGroupProjectType
    var status: BGIScriptGroupProjectStatus
    var schedule: String
    var runNum: Int
    var nextFlag: Bool?
    var skipFlag: Bool?
    var jsScriptSettingsJSON: String

    var id: String {
        "\(index)|\(type.rawValue)|\(folderName)|\(name)"
    }

    init(
        index: Int,
        name: String,
        folderName: String,
        type: BGIScriptGroupProjectType,
        status: BGIScriptGroupProjectStatus = .enabled,
        schedule: String = "Daily",
        runNum: Int = 1,
        nextFlag: Bool? = false,
        skipFlag: Bool? = false,
        jsScriptSettingsJSON: String = "{}"
    ) {
        self.index = index
        self.name = name
        self.folderName = folderName
        self.type = type
        self.status = status
        self.schedule = schedule
        self.runNum = max(1, runNum)
        self.nextFlag = nextFlag
        self.skipFlag = skipFlag
        self.jsScriptSettingsJSON = jsScriptSettingsJSON
    }

    private enum CodingKeys: String, CodingKey {
        case index
        case name
        case folderName
        case type
        case status
        case schedule
        case runNum
        case nextFlag
        case skipFlag
        case jsScriptSettingsJSON
        case jsScriptSettingsObject
        case allowJsNotification
        case allowJsHTTPHash
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decodeIfPresent(Int.self, forKey: .index) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        folderName = try container.decodeIfPresent(String.self, forKey: .folderName) ?? ""
        type = try container.decodeIfPresent(BGIScriptGroupProjectType.self, forKey: .type) ?? .javascript
        status = try container.decodeIfPresent(BGIScriptGroupProjectStatus.self, forKey: .status) ?? .enabled
        schedule = try container.decodeIfPresent(String.self, forKey: .schedule) ?? "Daily"
        runNum = max(1, try container.decodeIfPresent(Int.self, forKey: .runNum) ?? 1)
        nextFlag = try container.decodeIfPresent(Bool.self, forKey: .nextFlag) ?? false
        skipFlag = try container.decodeIfPresent(Bool.self, forKey: .skipFlag) ?? false

        if let json = try container.decodeIfPresent(String.self, forKey: .jsScriptSettingsJSON) {
            jsScriptSettingsJSON = json
        } else if let object = try container.decodeIfPresent(BGIJSONValue.self, forKey: .jsScriptSettingsObject) {
            jsScriptSettingsJSON = Self.settingsJSONString(from: object)
        } else {
            jsScriptSettingsJSON = "{}"
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(index, forKey: .index)
        try container.encode(name, forKey: .name)
        try container.encode(folderName, forKey: .folderName)
        try container.encode(type, forKey: .type)
        try container.encode(status, forKey: .status)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(runNum, forKey: .runNum)
        if nextFlag != false {
            try container.encode(nextFlag, forKey: .nextFlag)
        }
        if skipFlag != false {
            try container.encode(skipFlag, forKey: .skipFlag)
        }
        try container.encode(Self.settingsObject(fromJSONString: jsScriptSettingsJSON), forKey: .jsScriptSettingsObject)
    }

    static func javascript(
        index: Int,
        name: String,
        folderName: String,
        status: BGIScriptGroupProjectStatus = .enabled,
        schedule: String = "Daily",
        runNum: Int = 1,
        nextFlag: Bool? = false,
        skipFlag: Bool? = false,
        settingsJSON: String = "{}"
    ) -> BGIScriptGroupProject {
        BGIScriptGroupProject(
            index: index,
            name: name,
            folderName: folderName,
            type: .javascript,
            status: status,
            schedule: schedule,
            runNum: runNum,
            nextFlag: nextFlag,
            skipFlag: skipFlag,
            jsScriptSettingsJSON: settingsJSON
        )
    }

    private static func settingsJSONString(from value: BGIJSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private static func settingsObject(fromJSONString string: String) -> BGIJSONValue {
        guard let data = string.data(using: .utf8),
              let value = try? JSONDecoder().decode(BGIJSONValue.self, from: data) else {
            return .object([:])
        }
        return value
    }
}

struct BGIScriptGroupConfig: Equatable, Codable, Sendable {
    var shellConfig: BGIShellConfig
    var enableShellConfig: Bool

    init(
        shellConfig: BGIShellConfig = BGIShellConfig(),
        enableShellConfig: Bool = false
    ) {
        self.shellConfig = shellConfig
        self.enableShellConfig = enableShellConfig
    }
}

struct BGIScriptGroup: Identifiable, Equatable, Codable, Sendable {
    var index: Int
    var name: String
    var config: BGIScriptGroupConfig
    var projects: [BGIScriptGroupProject]
    var nextFlag: Bool

    var id: String { "\(index)|\(name)" }

    init(
        index: Int = 0,
        name: String,
        config: BGIScriptGroupConfig = BGIScriptGroupConfig(),
        projects: [BGIScriptGroupProject],
        nextFlag: Bool = false
    ) {
        self.index = index
        self.name = name
        self.config = config
        self.projects = projects
        self.nextFlag = nextFlag
    }

    private enum CodingKeys: String, CodingKey {
        case index
        case name
        case config
        case projects
        case nextFlag
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decodeIfPresent(Int.self, forKey: .index) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        config = try container.decodeIfPresent(BGIScriptGroupConfig.self, forKey: .config) ?? BGIScriptGroupConfig()
        projects = try container.decodeIfPresent([BGIScriptGroupProject].self, forKey: .projects) ?? []
        nextFlag = try container.decodeIfPresent(Bool.self, forKey: .nextFlag) ?? false
    }
}

enum BGIScriptGroupScheduler {
    static func nextGroups(_ groups: [BGIScriptGroup]) -> [BGIScriptGroup] {
        guard groups.contains(where: \.nextFlag) else { return groups }
        var shouldInclude = false
        return groups.compactMap { group in
            if group.nextFlag {
                shouldInclude = true
                var copy = group
                copy.nextFlag = false
                return copy
            }
            return shouldInclude ? group : nil
        }
    }

    static func nextProjects(in group: BGIScriptGroup) -> [BGIScriptGroupProject] {
        guard group.projects.contains(where: { $0.nextFlag ?? false }) else {
            return group.projects
        }

        var shouldRun = false
        var result: [BGIScriptGroupProject] = []
        for var project in group.projects {
            if project.nextFlag ?? false {
                shouldRun = true
            }
            if !shouldRun {
                project.skipFlag = true
            }
            result.append(project)
        }
        return shouldRun ? result : group.projects
    }

    static func executableRuns(from projects: [BGIScriptGroupProject]) -> [BGIScriptGroupProject] {
        projects.flatMap { project -> [BGIScriptGroupProject] in
            guard project.skipFlag != true, project.status == .enabled else { return [] }
            return Array(repeating: project, count: max(1, project.runNum))
        }
    }
}

// MARK: - Mock Dispatcher

final class MockAutomationRuntime {
    private var skippedTicks: UInt32 = 0
    private var previousGameUiCategory: GameUiCategory = .unknown
    private var previousGameUiChangeTime = Date()

    func process(
        frame: CapturedFrame,
        recognitionObjects: [RecognitionObject],
        triggerDescriptors: [TaskTriggerDescriptor],
        enabledFeatureIDs: Set<String>,
        confidenceFloor: Double,
        keyBindings: KeyBindingsConfig,
        captureCostMs: Double = 4.1,
        observationProvider: (([RecognitionObject]) -> [RecognitionObservation])? = nil
    ) -> AutomationRuntimeSnapshot {
        let startedAt = Date()
        let currentGameUiCategory = mockGameUiCategory(for: frame)
        if currentGameUiCategory != previousGameUiCategory {
            previousGameUiChangeTime = Date()
        }

        let runnableTriggers = selectRunnableTriggers(
            from: triggerDescriptors,
            enabledFeatureIDs: enabledFeatureIDs,
            currentGameUiCategory: currentGameUiCategory
        )
        let activeObjectIDs = Set(runnableTriggers.flatMap(\.recognitionObjectIDs))
        let activeObjects = recognitionObjects.filter { object in
            object.isEnabled
            && activeObjectIDs.contains(object.id)
            && object.featureID.map(enabledFeatureIDs.contains) != false
        }

        let observations = observationProvider?(activeObjects)
            ?? activeObjects.compactMap { object in
                mockObservation(for: object, frame: frame, confidenceFloor: confidenceFloor)
            }
        let decisions = mockDecisions(
            frame: frame,
            triggers: runnableTriggers,
            observations: observations,
            enabledFeatureIDs: enabledFeatureIDs,
            keyBindings: keyBindings
        )
        .sorted { $0.priority > $1.priority }

        if observations.isEmpty {
            skippedTicks += 1
        }
        previousGameUiCategory = currentGameUiCategory

        let processingCost = max(0.4, Date().timeIntervalSince(startedAt) * 1000)
        let peakConfidence = observations.map(\.confidence).max() ?? 0
        return AutomationRuntimeSnapshot(
            frameIndex: frame.frameIndex,
            timestamp: frame.timestamp,
            currentGameUiCategory: currentGameUiCategory,
            recognitionObjects: activeObjects,
            observations: observations,
            decisions: decisions,
            metrics: RuntimeCostMetrics(
                processingCostMs: processingCost,
                captureCostMs: captureCostMs,
                triggerCostMs: decisions.isEmpty ? 0.3 : 2.7,
                confidence: peakConfidence,
                skippedTicks: skippedTicks
            )
        )
    }

    private func selectRunnableTriggers(
        from descriptors: [TaskTriggerDescriptor],
        enabledFeatureIDs: Set<String>,
        currentGameUiCategory: GameUiCategory
    ) -> [TaskTriggerDescriptor] {
        let enabled = descriptors
            .filter { $0.isEnabled && enabledFeatureIDs.contains($0.featureID) }
            .sorted { $0.priority > $1.priority }

        let selected: [TaskTriggerDescriptor]
        if let exclusive = enabled.first(where: \.isExclusive) {
            selected = [exclusive]
        } else {
            selected = enabled
        }

        let sinceUiChanged = Date().timeIntervalSince(previousGameUiChangeTime)
        return selected.filter { descriptor in
            previousGameUiCategory != currentGameUiCategory
            || sinceUiChanged <= 30
            || descriptor.supportedGameUiCategory == .unknown
            || descriptor.supportedGameUiCategory == currentGameUiCategory
        }
    }

    private func mockObservation(
        for object: RecognitionObject,
        frame: CapturedFrame,
        confidenceFloor: Double
    ) -> RecognitionObservation? {
        let confidence = min(0.99, confidenceFloor)
        guard confidence >= object.threshold else { return nil }
        guard shouldEmit(object: object, frameIndex: frame.frameIndex) else { return nil }

        let text: String?
        switch object.id {
        case "AutoSkip.PlayingTextRo":
            text = "播放中"
        case "AutoSkip.OptionIconRo":
            text = "我知道了"
        case "AutoPick.FRo":
            text = "甜甜花"
        default:
            text = nil
        }

        return RecognitionObservation(
            id: "\(object.id)-\(frame.frameIndex)",
            objectID: object.id,
            objectName: object.name ?? object.id,
            recognitionType: object.recognitionType,
            normalizedRect: object.regionOfInterest?.normalizedRect() ?? CGRect(x: 0, y: 0, width: 1, height: 1),
            confidence: confidence,
            text: text,
            frameIndex: frame.frameIndex,
            timestamp: frame.timestamp
        )
    }

    private func shouldEmit(object: RecognitionObject, frameIndex: UInt64) -> Bool {
        switch object.id {
        case "AutoSkip.PlayingTextRo":
            return true
        case "AutoSkip.OptionIconRo":
            return frameIndex % 2 == 0
        case "AutoPick.FRo":
            return frameIndex % 3 != 0
        case "AutoPick.LRo":
            return false
        default:
            return frameIndex % 5 == 0
        }
    }

    private func mockDecisions(
        frame: CapturedFrame,
        triggers: [TaskTriggerDescriptor],
        observations: [RecognitionObservation],
        enabledFeatureIDs: Set<String>,
        keyBindings: KeyBindingsConfig
    ) -> [TriggerDecision] {
        var decisions: [TriggerDecision] = []
        let triggerMap = Dictionary(uniqueKeysWithValues: triggers.map { ($0.id, $0) })

        if enabledFeatureIDs.contains("auto-pickup"),
           let descriptor = triggerMap[.autoPick],
           let pickupMatch = observations.first(where: { $0.objectID == "AutoPick.FRo" }),
           observations.first(where: { $0.objectID == "AutoPick.LRo" }) == nil,
           let pickAction = keyBindings.inputAction(for: .pickUpOrInteract) {
            decisions.append(TriggerDecision(
                id: "AutoPick-\(frame.frameIndex)",
                triggerID: .autoPick,
                priority: descriptor.priority,
                reason: "识别到 AutoPickAssets.PickRo，按原逻辑准备发送 PickVk: \(keyBindings.key(for: .pickUpOrInteract).displayName)",
                confidence: pickupMatch.confidence,
                actions: [pickAction],
                observationIDs: [pickupMatch.id],
                timestamp: frame.timestamp
            ))
        }

        if enabledFeatureIDs.contains("auto-dialog"),
           let descriptor = triggerMap[.autoSkip] {
            let autoSkipMatches = observations.filter { $0.objectID.hasPrefix("AutoSkip.") }
            if let option = observations.first(where: { $0.objectID == "AutoSkip.OptionIconRo" }),
               let clickPoint = InputTargetResolver.screenPoint(for: option.normalizedRect, in: frame) {
                decisions.append(TriggerDecision(
                    id: "AutoSkip-option-\(frame.frameIndex)",
                    triggerID: .autoSkip,
                    priority: descriptor.priority,
                    reason: "识别到 OptionIconRo，按 ChatOptionChoose 准备点击对话选项",
                    confidence: option.confidence,
                    actions: [.leftClick(at: clickPoint)],
                    observationIDs: autoSkipMatches.map(\.id),
                    timestamp: frame.timestamp
                ))
            } else if let playing = observations.first(where: { $0.objectID == "AutoSkip.PlayingTextRo" }) {
                decisions.append(TriggerDecision(
                    id: "AutoSkip-space-\(frame.frameIndex)",
                    triggerID: .autoSkip,
                    priority: descriptor.priority,
                    reason: "处于 Talk UI，按 QuicklySkipConversationsEnabled 准备 Space",
                    confidence: playing.confidence,
                    actions: [.keyPress(key: .space)],
                    observationIDs: [playing.id],
                    timestamp: frame.timestamp
                ))
            }
        }

        return decisions
    }

    private func mockGameUiCategory(for frame: CapturedFrame) -> GameUiCategory {
        frame.frameIndex % 4 == 0 ? .talk : .unknown
    }
}
