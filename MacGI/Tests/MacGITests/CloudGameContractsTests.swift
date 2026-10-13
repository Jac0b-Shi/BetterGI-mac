import CoreGraphics
import Foundation
@testable import MacGI
import Testing

@Suite("Hosted cloud game contracts")
struct CloudGameContractsTests {
    @Test("Video letterboxing has identical capture and normalized input geometry")
    func videoGeometry() throws {
        let frame = CGRect(x: 100, y: 200, width: 1200, height: 800)
        let viewport = try #require(CloudGameGeometry.videoRect(["x": 0.0, "y": 62.5, "width": 1200.0, "height": 675.0], in: frame))
        let window = WindowInfo(id: 7, ownerPID: 1, ownerName: "MacGI", title: "云原神", frame: frame,
                                layer: 0, isOnScreen: true, scaleFactor: 1.6,
                                contentRectOverride: viewport, isHostedCloud: true)
        #expect(window.capturePixelSize == CGSize(width: 1920, height: 1080))
        #expect(CloudGameGeometry.cropRect(imageSize: CGSize(width: 1920, height: 1280), window: window)
                == CGRect(x: 0, y: 100, width: 1920, height: 1080))
        #expect(try CloudGameGeometry.normalizedPoint(CGPoint(x: viewport.midX, y: viewport.midY), in: viewport)
                == CGPoint(x: 0.5, y: 0.5))
        #expect(CloudGameGeometry.videoRect(["x": -1.0, "y": 0.0, "width": 1200.0, "height": 675.0], in: frame) == nil)
    }

    @Test("Holds use cancellable waits and releases, with no opaque SDK delayed key-up")
    func holdSequence() throws {
        let commands = try CloudWebInputDispatcher.commands(for: .keyHold(key: .f, durationMs: 500), viewport: .zero)
        #expect(commands.map { $0["method"] as? String } == ["keyDown", "wait", "keyUp"])
        #expect((commands[0]["args"] as? [Any])?.first as? String == "KeyF")
        #expect(throws: (any Error).self) {
            try CloudWebInputDispatcher.commands(for: .mouseButtonHold(button: .left, durationMs: -1), viewport: .zero)
        }
    }

    @Test("Outside-video clicks and unsupported buttons cannot become SDK packets")
    func invalidInput() {
        #expect(throws: (any Error).self) {
            try CloudWebInputDispatcher.commands(for: .leftClick(at: CGPoint(x: 5, y: 5)),
                                                viewport: CGRect(x: 100, y: 100, width: 960, height: 540))
        }
        #expect(throws: (any Error).self) {
            try CloudWebInputDispatcher.commands(for: .mouseButtonDown(button: .side1), viewport: .zero)
        }
    }

    @Test("SDK origin is limited to the national official cloud page")
    func origin() {
        #expect(WKWebInputBridge.isGameOrigin(URL(string: "https://ys.mihoyo.com/cloud/?autobegin=1")))
        #expect(!WKWebInputBridge.isGameOrigin(URL(string: "https://ys.mihoyo.com.evil.test/cloud/")))
        #expect(!WKWebInputBridge.isGameOrigin(URL(string: "http://ys.mihoyo.com/cloud/")))
    }
    @MainActor
    @Test("Retired Core adapters cannot route callbacks into a newly selected host")
    func retiredCoreSession() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(resourceStore: BGIRuntimeResourceStore(rootURL: root), launchArguments: ["--dry-run"])
        let adapter = BetterGICorePlatformAdapter(appState: state)
        state.corePlatformGeneration &+= 1
        let rejected = await Task.detached {
            do { _ = try adapter.handle(method: "window.metrics", parameters: nil); return false }
            catch { return error.localizedDescription.contains("retired") }
        }.value
        #expect(rejected)
    }

    @MainActor
    @Test("game.close cannot terminate the BetterGI process through a native target")
    func closeHostProcessRejected() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(resourceStore: BGIRuntimeResourceStore(rootURL: root), launchArguments: ["--dry-run"])
        state.selectedWindow = WindowInfo(id: 7, ownerPID: ProcessInfo.processInfo.processIdentifier,
            ownerName: "MacGI", title: "Host", frame: CGRect(x: 0, y: 0, width: 960, height: 540),
            layer: 0, isOnScreen: true, scaleFactor: 1)
        let adapter = BetterGICorePlatformAdapter(appState: state)
        let rejected = await Task.detached {
            do { _ = try adapter.handle(method: "game.close", parameters: nil); return false }
            catch { return error.localizedDescription.contains("cannot terminate") }
        }.value
        #expect(rejected)
    }

}
