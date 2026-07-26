import Testing
@testable import MacGI

@Suite("Screen capture permission coordinator")
struct ScreenCapturePermissionCoordinatorTests {
    @MainActor
    @Test("Requests screen capture access at most once per launch")
    func requestIsDeduplicated() {
        var requestCount = 0
        let coordinator = ScreenCapturePermissionCoordinator(
            preflight: { false },
            requestAccess: {
                requestCount += 1
                return false
            })

        #expect(coordinator.state == .notRequested)
        #expect(coordinator.requestOnce() == .settingsRequired)
        #expect(coordinator.requestOnce() == .settingsRequired)
        #expect(requestCount == 1)
    }

    @MainActor
    @Test("Permission granted after launch requires reopening")
    func newlyGrantedPermissionRequiresRestart() {
        var granted = false
        let coordinator = ScreenCapturePermissionCoordinator(
            preflight: { granted },
            requestAccess: {
                granted = true
                return true
            })

        #expect(coordinator.requestOnce() == .restartRequired)
        #expect(!coordinator.state.permitsCapture)
        #expect(coordinator.refresh() == .restartRequired)
    }

    @MainActor
    @Test("Permission granted at launch permits capture")
    func existingPermissionPermitsCapture() {
        var requestCount = 0
        let coordinator = ScreenCapturePermissionCoordinator(
            preflight: { true },
            requestAccess: {
                requestCount += 1
                return true
            })

        #expect(coordinator.state == .granted)
        #expect(coordinator.requestOnce() == .granted)
        #expect(coordinator.state.permitsCapture)
        #expect(requestCount == 0)
    }
}
