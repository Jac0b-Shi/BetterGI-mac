import CoreGraphics
@testable import MacGI
import Testing

@Suite("BetterGI Core input key mapper")
struct BetterGICoreInputKeyMapperTests {
    @Test("Maps configured keyboard hotkeys without changing BetterGI names")
    func mapsKeyboardHotkeys() {
        #expect(BetterGICoreInputKeyMapper.keyCode(from: "F6") == .f6)
        #expect(BetterGICoreInputKeyMapper.keyCode(from: "VK_SPACE") == .space)
    }

    @Test("Maps Windows mouse hotkey names to Quartz buttons")
    func mapsMouseHotkeys() {
        #expect(BetterGICoreInputKeyMapper.mouseButton(from: "Middle") == .center)
        #expect(BetterGICoreInputKeyMapper.mouseButton(from: "XButton1") == CGMouseButton(rawValue: 3))
        #expect(BetterGICoreInputKeyMapper.mouseButton(from: "XButton2") == CGMouseButton(rawValue: 4))
    }
}
