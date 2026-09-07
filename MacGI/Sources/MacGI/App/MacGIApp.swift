import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI

@MainActor
final class MacGIApplicationDelegate: NSObject, NSApplicationDelegate {
    var terminationHandler: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationWillTerminate(_ notification: Notification) {
        terminationHandler?()
    }
}

enum MacGIPermissionRequester {
    enum RequestResult {
        case alreadyGranted
        case requestSubmitted
    }

    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() -> RequestResult {
        guard !accessibilityGranted else { return .alreadyGranted }
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        return .requestSubmitted
    }
}

@main
struct MacGIApp: App {
    @NSApplicationDelegateAdaptor(MacGIApplicationDelegate.self) private var applicationDelegate
    @StateObject private var appState = AppState()
    @StateObject private var coordinator = AppCoordinator()

    init() {
        FontRegistry.registerBundledFonts()
    }

    var body: some Scene {
        Window("betterGI-mac", id: "main") {
            MainWindowView()
                .environmentObject(appState)
                .environmentObject(coordinator)
                .environment(\.locale, selectedLocale)
                .frame(minWidth: 1080, minHeight: 720)
                .onAppear {
                    applicationDelegate.terminationHandler = {
                        appState.shutdownInputBackend()
                    }
                    coordinator.configure(appState: appState)
                    appState.beginCoreStartup()
                }
        }
        .defaultSize(width: 1180, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands {
            MacGICommands(appState: appState, coordinator: coordinator)
        }

        MenuBarExtra("betterGI-mac", systemImage: "scope") {
            MenuBarControls()
                .environmentObject(appState)
                .environmentObject(coordinator)
                .environment(\.locale, selectedLocale)
        }
        .menuBarExtraStyle(.menu)
    }

    private var selectedLocale: Locale {
        Locale(identifier: appState.commonSettings?.uiCultureInfoName ?? "zh-Hans")
    }
}

struct MacGICommands: Commands {
    @ObservedObject var appState: AppState
    let coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("betterGI-mac Control") {
            Button("Open betterGI-mac") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("0", modifiers: [.command])

            Divider()

            Button(appState.runtimeLifecycle == .running ? "Stop Runtime" : "Start Runtime") {
                appState.toggleRuntime()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(appState.runtimeLifecycle.isTransitioning)

            Button(appState.isHUDVisible ? "Hide HUD" : "Show HUD") {
                appState.toggleHUD()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Button("Add Test Log") {
                appState.addTestLog()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}

struct MenuBarControls: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open betterGI-mac") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(appState.runtimeLifecycle == .running ? "Stop Runtime" : "Start Runtime") {
            appState.toggleRuntime()
        }
        .disabled(appState.runtimeLifecycle.isTransitioning)
        Button(appState.isHUDVisible ? "Hide HUD" : "Show HUD") {
            appState.toggleHUD()
        }
        Button("Add Test Log") {
            appState.addTestLog()
        }
        Divider()
        Button("Quit") {
            coordinator.quit()
        }
    }
}
