import CoreGraphics
import Foundation

enum ScreenCaptureAuthorizationState: Equatable, Sendable {
    case checking
    case notRequested
    case requesting
    case settingsRequired
    case restartRequired
    case granted

    var permitsCapture: Bool {
        self == .granted
    }
}

@MainActor
final class ScreenCapturePermissionCoordinator {
    private let preflight: () -> Bool
    private let requestAccess: () -> Bool
    private let grantedAtLaunch: Bool
    private var requestAttemptedThisLaunch = false
    private var requestInFlight = false

    private(set) var state: ScreenCaptureAuthorizationState = .checking

    init(
        preflight: @escaping () -> Bool = CGPreflightScreenCaptureAccess,
        requestAccess: @escaping () -> Bool = CGRequestScreenCaptureAccess
    ) {
        self.preflight = preflight
        self.requestAccess = requestAccess
        grantedAtLaunch = preflight()
        state = grantedAtLaunch ? .granted : .notRequested
    }

    @discardableResult
    func refresh() -> ScreenCaptureAuthorizationState {
        if preflight() {
            state = grantedAtLaunch ? .granted : .restartRequired
        } else {
            state = requestAttemptedThisLaunch ? .settingsRequired : .notRequested
        }
        return state
    }

    @discardableResult
    func requestOnce(source: StaticString = #function) -> ScreenCaptureAuthorizationState {
        NSLog("Screen capture permission request source=%@", "\(source)")

        if preflight() {
            return refresh()
        }
        guard !requestInFlight else {
            return state
        }
        guard !requestAttemptedThisLaunch else {
            return refresh()
        }

        requestInFlight = true
        requestAttemptedThisLaunch = true
        state = .requesting
        let grantedImmediately = requestAccess()
        requestInFlight = false

        state = grantedImmediately || preflight() ? .restartRequired : .settingsRequired
        return state
    }
}
