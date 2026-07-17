import CoreGraphics
import Foundation
@testable import MacGI
import Testing

@Suite("BetterGI key-mouse macro executor")
struct BGIKeyMouseMacroExecutorTests {
    @Test("decodes upstream recorder camelCase JSON")
    func decodesUpstreamRecorderCamelCaseJSON() throws {
        let json = #"""
        {
          "macroEvents": [
            { "type": "KeyDown", "keyCode": 70, "time": 0 },
            { "type": "MouseWheel", "mouseY": -240, "time": 50 }
          ],
          "info": {
            "name": "demo",
            "x": 100,
            "y": 200,
            "width": 1920,
            "height": 1080,
            "recordDpi": 1.5
          }
        }
        """#

        let script = try JSONDecoder().decode(BGIKeyMouseScript.self, from: Data(json.utf8))

        #expect(script.info?.name == "demo")
        #expect(script.macroEvents.map(\.type) == [
            BGIKeyMouseMacroEventType.keyDown,
            BGIKeyMouseMacroEventType.mouseWheel
        ])
        #expect(script.macroEvents[0].keyCode == 70)
        #expect(script.macroEvents[1].mouseY == -240)
    }

    @Test("maps Windows virtual keys used by BetterGI recorder")
    func mapsWindowsVirtualKeys() {
        #expect(BGIKeyMouseMacroExecutor.keyCodeFromWindowsVirtualKey(0x46) == .f)
        #expect(BGIKeyMouseMacroExecutor.keyCodeFromWindowsVirtualKey(0x31) == .digit1)
        #expect(BGIKeyMouseMacroExecutor.keyCodeFromWindowsVirtualKey(0x70) == .f1)
        #expect(BGIKeyMouseMacroExecutor.keyCodeFromWindowsVirtualKey(0x1B) == .escape)
        #expect(BGIKeyMouseMacroExecutor.keyCodeFromWindowsVirtualKey(0x20) == .space)
        #expect(BGIKeyMouseMacroExecutor.keyCodeFromWindowsVirtualKey(0x25) == .leftArrow)
    }

    @Test("adapts recorded coordinates and DPI like BetterGI KeyMouseScript.Adapt")
    func adaptsRecordedCoordinatesAndDPI() {
        let targetWindow = WindowInfo(
            id: 1,
            ownerPID: 42,
            ownerName: "YAAGL",
            title: "Genshin Impact",
            frame: CGRect(x: 10, y: 20, width: 960, height: 540),
            layer: 0,
            isOnScreen: true,
            scaleFactor: 2,
            isMock: true
        )
        let script = BGIKeyMouseScript(
            macroEvents: [
                BGIKeyMouseMacroEvent(type: .mouseMoveTo, mouseX: 1060, mouseY: 740, time: 100),
                BGIKeyMouseMacroEvent(type: .mouseMoveBy, mouseX: 6, mouseY: -3, time: 120),
                BGIKeyMouseMacroEvent(type: .mouseDown, mouseX: 1060, mouseY: 740, mouseButton: "Left", time: 130),
                BGIKeyMouseMacroEvent(type: .mouseUp, mouseX: 1060, mouseY: 740, mouseButton: "Left", time: 140)
            ],
            info: BGIKeyMouseScriptInfo(x: 100, y: 200, width: 1920, height: 1080, recordDpi: 1.5)
        )

        let actions = BGIKeyMouseMacroExecutor.actions(
            for: script,
            targetWindow: targetWindow,
            initialMousePoint: CGPoint(x: 20, y: 30)
        )

        #expect(actions.map(\.eventTimeMs) == [100, 120, 130, 140])
        #expect(actions.map(\.action) == [
            .mouseMove(to: CGPoint(x: 490, y: 290)),
            .mouseMove(to: CGPoint(x: 498, y: 286)),
            .mouseButtonDown(button: .left, at: CGPoint(x: 490, y: 290)),
            .mouseButtonUp(button: .left, at: CGPoint(x: 490, y: 290))
        ])
    }

    @Test("converts wheel and skips unsupported events")
    func convertsWheelAndSkipsUnsupportedEvents() {
        let script = BGIKeyMouseScript(
            macroEvents: [
                BGIKeyMouseMacroEvent(type: .mouseWheel, mouseY: -240, time: 20),
                BGIKeyMouseMacroEvent(type: .keyDown, keyCode: 0xFF, time: 30)
            ],
            info: nil
        )

        let actions = BGIKeyMouseMacroExecutor.actions(for: script, targetWindow: .mock())

        #expect(actions.map(\.action) == [.verticalScroll(clicks: -2)])
    }
}
