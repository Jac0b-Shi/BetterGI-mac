import Testing
@testable import MacGI

@Suite("HUD presentation policy")
struct HUDPresentationPolicyTests {
    @Test("HUD follows focus without changing user intent")
    func focusPolicy() {
        #expect(HUDPresentationPolicy.shouldPresent(
            hudRequested: true,
            runtimeLifecycle: .running,
            windowValid: true,
            hideWhenUnfocused: true,
            gameFrontmost: true,
            layoutEditing: false,
            macGIFrontmost: false))
        #expect(!HUDPresentationPolicy.shouldPresent(
            hudRequested: true,
            runtimeLifecycle: .running,
            windowValid: true,
            hideWhenUnfocused: true,
            gameFrontmost: false,
            layoutEditing: false,
            macGIFrontmost: true))
        #expect(!HUDPresentationPolicy.shouldPresent(
            hudRequested: false,
            runtimeLifecycle: .running,
            windowValid: true,
            hideWhenUnfocused: true,
            gameFrontmost: true,
            layoutEditing: false,
            macGIFrontmost: false))
    }

    @Test("Layout editing permits MacGI foreground only while runtime is active")
    func layoutEditingPolicy() {
        #expect(HUDPresentationPolicy.shouldPresent(
            hudRequested: true,
            runtimeLifecycle: .running,
            windowValid: true,
            hideWhenUnfocused: true,
            gameFrontmost: false,
            layoutEditing: true,
            macGIFrontmost: true))
        #expect(!HUDPresentationPolicy.shouldPresent(
            hudRequested: true,
            runtimeLifecycle: .stopped,
            windowValid: true,
            hideWhenUnfocused: true,
            gameFrontmost: false,
            layoutEditing: true,
            macGIFrontmost: true))
    }

    @Test("Focus hiding can be disabled without bypassing runtime safety")
    func focusHidingDisabled() {
        #expect(HUDPresentationPolicy.shouldPresent(
            hudRequested: true,
            runtimeLifecycle: .running,
            windowValid: true,
            hideWhenUnfocused: false,
            gameFrontmost: false,
            layoutEditing: false,
            macGIFrontmost: false))
        #expect(!HUDPresentationPolicy.shouldPresent(
            hudRequested: true,
            runtimeLifecycle: .stopped,
            windowValid: true,
            hideWhenUnfocused: false,
            gameFrontmost: false,
            layoutEditing: false,
            macGIFrontmost: false))
    }
}
