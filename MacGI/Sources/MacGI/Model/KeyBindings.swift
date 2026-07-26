import Foundation

// MARK: - GIKeyType

/// Mirrors BetterGI `KeyType`.
enum GIKeyType: String, Equatable, Sendable, CaseIterable {
    case keyPress
    case keyDown
    case keyUp
    case hold
}

// MARK: - GIAction

/// Mirrors BetterGI `GIActions`.
enum GIAction: String, Identifiable, Equatable, Hashable, Sendable, CaseIterable {
    case moveForward
    case moveBackward
    case moveLeft
    case moveRight
    case switchToWalkOrRun
    case normalAttack
    case elementalSkill
    case elementalBurst
    case sprintKeyboard
    case sprintMouse
    case switchAimingMode
    case jump
    case drop
    case pickUpOrInteract
    case quickUseGadget
    case interactionInSomeMode
    case questNavigation
    case abandonChallenge
    case switchMember1
    case switchMember2
    case switchMember3
    case switchMember4
    case switchMember5
    case shortcutWheel
    case openInventory
    case openCharacterScreen
    case openMap
    case openPaimonMenu
    case openAdventurerHandbook
    case openCoOpScreen
    case openWishScreen
    case openBattlePassScreen
    case openTheEventsMenu
    case openTheSettingsMenu
    case openTheFurnishingScreen
    case openStellarReunion
    case openQuestMenu
    case openNotificationDetails
    case openChatScreen
    case openSpecialEnvironmentInformation
    case checkTutorialDetails
    case elementalSight
    case showCursor
    case openPartySetupScreen
    case openFriendsScreen
    case hideUI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .moveForward: "向前移动"
        case .moveBackward: "向后移动"
        case .moveLeft: "向左移动"
        case .moveRight: "向右移动"
        case .switchToWalkOrRun: "切换走/跑"
        case .normalAttack: "普通攻击"
        case .elementalSkill: "元素战技"
        case .elementalBurst: "元素爆发"
        case .sprintKeyboard: "冲刺（键盘）"
        case .sprintMouse: "冲刺（鼠标）"
        case .switchAimingMode: "切换瞄准模式"
        case .jump: "跳跃"
        case .drop: "落下"
        case .pickUpOrInteract: "拾取/交互"
        case .quickUseGadget: "快捷使用小道具"
        case .interactionInSomeMode: "特定玩法交互"
        case .questNavigation: "开启任务追踪"
        case .abandonChallenge: "中断挑战"
        case .switchMember1: "切换队员1"
        case .switchMember2: "切换队员2"
        case .switchMember3: "切换队员3"
        case .switchMember4: "切换队员4"
        case .switchMember5: "切换队员5"
        case .shortcutWheel: "呼出快捷轮盘"
        case .openInventory: "打开背包"
        case .openCharacterScreen: "打开角色界面"
        case .openMap: "打开地图"
        case .openPaimonMenu: "打开派蒙界面"
        case .openAdventurerHandbook: "打开冒险之证"
        case .openCoOpScreen: "打开多人游戏"
        case .openWishScreen: "打开祈愿"
        case .openBattlePassScreen: "打开纪行"
        case .openTheEventsMenu: "打开活动面板"
        case .openTheSettingsMenu: "打开玩法系统"
        case .openTheFurnishingScreen: "打开摆设界面"
        case .openStellarReunion: "打开星之归还"
        case .openQuestMenu: "开关任务菜单"
        case .openNotificationDetails: "打开通知详情"
        case .openChatScreen: "打开聊天界面"
        case .openSpecialEnvironmentInformation: "打开特殊环境说明"
        case .checkTutorialDetails: "查看教程详情"
        case .elementalSight: "长按元素视野"
        case .showCursor: "呼出鼠标"
        case .openPartySetupScreen: "打开队伍配置"
        case .openFriendsScreen: "打开好友"
        case .hideUI: "隐藏主界面"
        }
    }
}

// MARK: - KeyID

/// Mirrors BetterGI `KeyId` for the key set currently required by the macOS input bridge.
enum KeyID: String, Identifiable, Equatable, Hashable, Sendable, CaseIterable {
    case none
    case unknown
    case mouseLeftButton
    case mouseRightButton
    case mouseMiddleButton
    case mouseSideButton1
    case mouseSideButton2
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    case escape
    case delete
    case home
    case end
    case pageUp
    case pageDown
    case backspace
    case tab
    case capsLock
    case enter
    case leftShift
    case leftCtrl
    case leftAlt
    case space
    case left
    case up
    case right
    case down
    case a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z
    case d0, d1, d2, d3, d4, d5, d6, d7, d8, d9
    case apostrophe
    case comma
    case minus
    case equal
    case period
    case slash
    case backslash
    case semicolon
    case leftSquareBracket
    case rightSquareBracket
    case tilde

    var id: String { rawValue }

    init?(windowsVirtualKey value: Int) {
        if (0x30...0x39).contains(value) {
            self.init(rawValue: "d\(value - 0x30)")
            return
        }
        if (0x41...0x5A).contains(value),
           let scalar = UnicodeScalar(value) {
            self.init(rawValue: String(Character(scalar)).lowercased())
            return
        }
        if (0x70...0x7B).contains(value) {
            self.init(rawValue: "f\(value - 0x6F)")
            return
        }
        let key: KeyID? = switch value {
        case 0x00: KeyID.none
        case 0x01: .mouseLeftButton
        case 0x02: .mouseRightButton
        case 0x04: .mouseMiddleButton
        case 0x05: .mouseSideButton1
        case 0x06: .mouseSideButton2
        case 0x08: .backspace
        case 0x09: .tab
        case 0x0D: .enter
        case 0x14: .capsLock
        case 0x1B: .escape
        case 0x20: .space
        case 0x21: .pageUp
        case 0x22: .pageDown
        case 0x23: .end
        case 0x24: .home
        case 0x25: .left
        case 0x26: .up
        case 0x27: .right
        case 0x28: .down
        case 0x2E: .delete
        case 0xA0: .leftShift
        case 0xA2: .leftCtrl
        case 0xA4: .leftAlt
        case 0xBA: .semicolon
        case 0xBB: .equal
        case 0xBC: .comma
        case 0xBD: .minus
        case 0xBE: .period
        case 0xBF: .slash
        case 0xC0: .tilde
        case 0xDB: .leftSquareBracket
        case 0xDC: .backslash
        case 0xDD: .rightSquareBracket
        case 0xDE: .apostrophe
        default: nil
        }
        guard let key else { return nil }
        self = key
    }

    var displayName: String {
        switch self {
        case .none: "<未指定>"
        case .unknown: "<未知>"
        case .mouseLeftButton: "鼠标左键"
        case .mouseRightButton: "鼠标右键"
        case .mouseMiddleButton: "鼠标中键"
        case .mouseSideButton1: "鼠标侧键1"
        case .mouseSideButton2: "鼠标侧键2"
        case .enter: "Enter"
        case .leftShift: "左Shift"
        case .leftCtrl: "左Ctrl"
        case .leftAlt: "左Alt"
        case .left: "←"
        case .up: "↑"
        case .right: "→"
        case .down: "↓"
        case .d0: "0"
        case .d1: "1"
        case .d2: "2"
        case .d3: "3"
        case .d4: "4"
        case .d5: "5"
        case .d6: "6"
        case .d7: "7"
        case .d8: "8"
        case .d9: "9"
        case .apostrophe: "'"
        case .comma: ","
        case .minus: "-"
        case .equal: "="
        case .period: "."
        case .slash: "/"
        case .backslash: "\\"
        case .semicolon: ";"
        case .leftSquareBracket: "["
        case .rightSquareBracket: "]"
        case .tilde: "`"
        default:
            rawValue.uppercased()
        }
    }

    var keyCode: KeyCode? {
        switch self {
        case .a: .a
        case .b: .b
        case .c: .c
        case .d: .d
        case .e: .e
        case .f: .f
        case .g: .g
        case .h: .h
        case .i: .i
        case .j: .j
        case .k: .k
        case .l: .l
        case .m: .m
        case .n: .n
        case .o: .o
        case .p: .p
        case .q: .q
        case .r: .r
        case .s: .s
        case .t: .t
        case .u: .u
        case .v: .v
        case .w: .w
        case .x: .x
        case .y: .y
        case .z: .z
        case .d0: .digit0
        case .d1: .digit1
        case .d2: .digit2
        case .d3: .digit3
        case .d4: .digit4
        case .d5: .digit5
        case .d6: .digit6
        case .d7: .digit7
        case .d8: .digit8
        case .d9: .digit9
        case .f1: .f1
        case .f2: .f2
        case .f3: .f3
        case .f4: .f4
        case .f5: .f5
        case .f6: .f6
        case .f7: .f7
        case .f8: .f8
        case .f9: .f9
        case .f10: .f10
        case .f11: .f11
        case .f12: .f12
        case .escape: .escape
        case .delete: .delete
        case .home: .home
        case .end: .end
        case .pageUp: .pageUp
        case .pageDown: .pageDown
        case .backspace: .backspace
        case .tab: .tab
        case .capsLock: .capsLock
        case .enter: .return
        case .leftShift: .leftShift
        case .leftCtrl: .leftControl
        case .leftAlt: .leftOption
        case .space: .space
        case .left: .leftArrow
        case .up: .upArrow
        case .right: .rightArrow
        case .down: .downArrow
        case .apostrophe: .apostrophe
        case .comma: .comma
        case .minus: .minus
        case .equal: .equal
        case .period: .period
        case .slash: .slash
        case .backslash: .backslash
        case .semicolon: .semicolon
        case .leftSquareBracket: .leftBracket
        case .rightSquareBracket: .rightBracket
        case .tilde: .grave
        case .none, .unknown, .mouseLeftButton, .mouseRightButton, .mouseMiddleButton, .mouseSideButton1, .mouseSideButton2:
            nil
        }
    }

    var mouseButton: InputMouseButton? {
        switch self {
        case .mouseLeftButton: .left
        case .mouseRightButton: .right
        case .mouseMiddleButton: .middle
        default: nil
        }
    }
}

// MARK: - KeyBindingsConfig

/// Mirrors BetterGI `KeyBindingsConfig` and `SimulateKeyHelper`.
struct KeyBindingsConfig: Equatable, Sendable {
    var globalKeyMappingEnabled = false
    var bindings: [GIAction: KeyID]

    static let bgiDefault = KeyBindingsConfig(
        globalKeyMappingEnabled: false,
        bindings: [
            .moveForward: .w,
            .moveBackward: .s,
            .moveLeft: .a,
            .moveRight: .d,
            .switchToWalkOrRun: .leftCtrl,
            .normalAttack: .mouseLeftButton,
            .elementalSkill: .e,
            .elementalBurst: .q,
            .sprintKeyboard: .leftShift,
            .sprintMouse: .mouseRightButton,
            .switchAimingMode: .r,
            .jump: .space,
            .drop: .x,
            .pickUpOrInteract: .f,
            .quickUseGadget: .z,
            .interactionInSomeMode: .t,
            .questNavigation: .v,
            .abandonChallenge: .p,
            .switchMember1: .d1,
            .switchMember2: .d2,
            .switchMember3: .d3,
            .switchMember4: .d4,
            .switchMember5: .d5,
            .shortcutWheel: .tab,
            .openInventory: .b,
            .openCharacterScreen: .c,
            .openMap: .m,
            .openPaimonMenu: .escape,
            .openAdventurerHandbook: .f1,
            .openCoOpScreen: .f2,
            .openWishScreen: .f3,
            .openBattlePassScreen: .f4,
            .openTheEventsMenu: .f5,
            .openTheSettingsMenu: .f6,
            .openTheFurnishingScreen: .f7,
            .openStellarReunion: .f8,
            .openQuestMenu: .j,
            .openNotificationDetails: .y,
            .openChatScreen: .enter,
            .openSpecialEnvironmentInformation: .u,
            .checkTutorialDetails: .g,
            .elementalSight: .mouseMiddleButton,
            .showCursor: .leftAlt,
            .openPartySetupScreen: .l,
            .openFriendsScreen: .o,
            .hideUI: .slash
        ]
    )

    func key(for action: GIAction) -> KeyID {
        bindings[action] ?? .unknown
    }

    func inputAction(for action: GIAction, type: GIKeyType = .keyPress) -> InputAction? {
        inputAction(for: key(for: action), type: type)
    }

    func inputAction(for key: KeyID, type: GIKeyType = .keyPress) -> InputAction? {
        if let mouseButton = key.mouseButton {
            switch type {
            case .keyPress:
                return .mouseClick(button: mouseButton)
            case .keyDown:
                return .mouseButtonDown(button: mouseButton)
            case .keyUp:
                return .mouseButtonUp(button: mouseButton)
            case .hold:
                return .mouseButtonHold(button: mouseButton, durationMs: 1000)
            }
        }

        guard let keyCode = key.keyCode else {
            return nil
        }
        switch type {
        case .keyPress:
            return .keyPress(key: keyCode)
        case .keyDown:
            return .keyDown(key: keyCode)
        case .keyUp:
            return .keyUp(key: keyCode)
        case .hold:
            return .keyHold(key: keyCode, durationMs: 1000)
        }
    }
}
