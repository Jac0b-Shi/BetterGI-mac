import CoreGraphics
import Testing
@testable import MacGI

@Suite("macOS hotkey signature")
struct MacHotKeySignatureTests {
    @Test("Parses and emits the upstream WPF hotkey format")
    func upstreamFormatRoundTrip() {
        let keyboard = MacHotKeySignature.parse("Ctrl + Shift + F11")
        #expect(keyboard?.key == .f11)
        #expect(keyboard?.modifiers == [.control, .shift])
        #expect(keyboard?.upstreamValue == "Ctrl + Shift + F11")

        let digit = MacHotKeySignature.parse("D3")
        #expect(digit?.key == .digit3)
        #expect(digit?.upstreamValue == "D3")

        let punctuation = MacHotKeySignature.parse("Alt + OemQuestion")
        #expect(punctuation?.key == .slash)
        #expect(punctuation?.upstreamValue == "Alt + OemQuestion")

        let mouse = MacHotKeySignature.parse("XButton1")
        #expect(mouse?.mouseButton?.rawValue == 3)
        #expect(mouse?.upstreamValue == "XButton1")
    }

    @Test("Preserves upstream global and monitor restrictions")
    func validation() {
        #expect(
            MacHotKeySignature.parse("A")?
                .validationMessage(for: "GlobalRegister") != nil)
        #expect(
            MacHotKeySignature.parse("Shift + A")?
                .validationMessage(for: "GlobalRegister") != nil)
        #expect(
            MacHotKeySignature.parse("Ctrl + A")?
                .validationMessage(for: "GlobalRegister") == nil)
        #expect(
            MacHotKeySignature.parse("F11")?
                .validationMessage(for: "GlobalRegister") == nil)
        #expect(
            MacHotKeySignature.parse("Ctrl + F11")?
                .validationMessage(for: "KeyboardMonitor") != nil)
        #expect(
            MacHotKeySignature.parse("XButton2")?
                .validationMessage(for: "KeyboardMonitor") == nil)
    }

    @Test("Matches both edges of a recorded keyboard hotkey")
    func recordingEdges() throws {
        let keyCode = try #require(KeyCode.f11.cgKeyCode)
        let down = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: true))
        let up = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: false))

        #expect(
            MacHotKeySignature.from(type: .keyDown, event: down) ==
                MacHotKeySignature.parse("F11"))
        #expect(
            MacHotKeySignature.from(type: .keyUp, event: up) ==
                MacHotKeySignature.parse("F11"))
    }
}
