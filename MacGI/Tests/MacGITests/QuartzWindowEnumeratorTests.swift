import CoreGraphics
import AppKit
@testable import MacGI
import Testing

@Suite("Quartz window selection")
struct QuartzWindowEnumeratorTests {
    @Test("Generic YAAGL launcher title is not treated as the game")
    func genericYaaglLauncherTitleIsNotGame() throws {
        let launcher = makeWindow(
            id: 1,
            ownerName: "Yaagl OS",
            title: "Yet Another Anime Game Launcher",
            frame: CGRect(x: 320, y: 89, width: 1280, height: 730)
        )

        #expect(!launcher.isLikelyGameWindow)
        #expect(launcher.gameWindowSelectionPriority == 0)
    }

    @Test("Wine Genshin window is preferred over a larger YAAGL launcher")
    func wineGenshinWindowPreferredOverLauncher() throws {
        let launcher = makeWindow(
            id: 1,
            ownerName: "Yaagl OS",
            title: "Genshin Impact Launcher",
            frame: CGRect(x: 320, y: 89, width: 1280, height: 730)
        )
        let game = makeWindow(
            id: 2,
            ownerName: "wine",
            title: "原神",
            frame: CGRect(x: 18, y: 82, width: 960, height: 572)
        )

        #expect(launcher.isLikelyGameWindow)
        #expect(game.isLikelyGameWindow)
        #expect(game.gameWindowSelectionPriority > launcher.gameWindowSelectionPriority)
        #expect(QuartzWindowEnumerator.bestGameWindow(from: [launcher, game]) == game)
    }

    @Test("Wine utility windows remain below titled game windows")
    func wineUtilityWindowStaysBelowGameWindow() throws {
        let utility = makeWindow(
            id: 3,
            ownerName: "wine",
            title: "",
            frame: CGRect(x: 0, y: 580, width: 500, height: 500)
        )
        let game = makeWindow(
            id: 4,
            ownerName: "wine",
            title: "Genshin Impact",
            frame: CGRect(x: 18, y: 82, width: 960, height: 572)
        )

        #expect(!utility.isLikelyGameWindow)
        #expect(game.isLikelyGameWindow)
        #expect(QuartzWindowEnumerator.bestGameWindow(from: [utility, game]) == game)
    }

    @Test("Ordinary full-screen windows are never selected as the game")
    func ordinaryFullScreenWindowIsNotSelected() {
        let ordinaryWindow = makeWindow(
            id: 5,
            ownerName: "Finder",
            title: "Desktop",
            frame: CGRect(x: 0, y: 0, width: 2560, height: 1440)
        )

        #expect(QuartzWindowEnumerator.bestGameWindow(from: [ordinaryWindow]) == nil)
    }

    @Test("HUD frame follows Quartz window geometry")
    @MainActor
    func hudFrameFollowsQuartzWindowGeometry() {
        let frame = HUDPanelController.appKitFrame(
            forQuartzFrame: CGRect(x: 160, y: 90, width: 1280, height: 720),
            referenceMaxY: 1080
        )

        #expect(frame == CGRect(x: 160, y: 270, width: 1280, height: 720))
    }

    @Test("Wine title bar is excluded from the game client geometry")
    func wineTitleBarIsExcludedFromCaptureRect() {
        let game = WindowInfo(
            id: 551, ownerPID: 7960, ownerName: "wine", title: "原神",
            frame: CGRect(x: 633, y: 131, width: 1280, height: 752),
            layer: 0, isOnScreen: true, scaleFactor: 2
        )

        #expect(game.captureRect == CGRect(x: 633, y: 163, width: 1280, height: 720))
        #expect(game.capturePixelSize == CGSize(width: 2560, height: 1440))
    }

    @Test("HUD follows the Wine game client instead of its title bar")
    @MainActor
    func hudFrameFollowsWineGameClient() {
        let game = WindowInfo(
            id: 551, ownerPID: 7960, ownerName: "wine", title: "原神",
            frame: CGRect(x: 633, y: 131, width: 1280, height: 752),
            layer: 0, isOnScreen: true, scaleFactor: 2
        )
        let frame = HUDPanelController.appKitFrame(
            forQuartzFrame: game.captureRect, referenceMaxY: 1080
        )

        #expect(frame == CGRect(x: 633, y: 197, width: 1280, height: 720))
    }

    @Test("Map picker captures only its control area")
    @MainActor
    func mapPickerUsesBoundedInteractiveFrames() {
        let gameFrame = CGRect(x: 100, y: 80, width: 1920, height: 1080)
        let collapsed = MapMaskPickerPanelController.panelFrame(in: gameFrame, expanded: false)
        let expanded = MapMaskPickerPanelController.panelFrame(in: gameFrame, expanded: true)

        #expect(collapsed == CGRect(x: 208, y: 102, width: 70, height: 70))
        #expect(expanded.minX == collapsed.minX)
        #expect(expanded.minY == collapsed.minY)
        #expect(expanded.width < gameFrame.width / 2)
        #expect(expanded.height < gameFrame.height)
    }

    private func makeWindow(
        id: CGWindowID,
        ownerName: String,
        title: String,
        frame: CGRect
    ) -> WindowInfo {
        WindowInfo(
            id: id,
            ownerPID: 1000 + pid_t(id),
            ownerName: ownerName,
            title: title,
            frame: frame,
            layer: 0,
            isOnScreen: true,
            scaleFactor: 1,
            isSynthetic: false
        )
    }
}
