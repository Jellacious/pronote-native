import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(nil)
            }
            sender.activate(ignoringOtherApps: true)
        }
        return true
    }
}

struct PronoteNativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var viewModel: AppViewModel

    init() {
        let appSettings = AppSettings()
        _settings = StateObject(wrappedValue: appSettings)
        _viewModel = StateObject(wrappedValue: AppViewModel(settings: appSettings))
        MainActor.assumeIsolated {
            NSWindow.allowsAutomaticWindowTabbing = false
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        Window("Pronote Native", id: "main") {
            Group {
                if viewModel.credentials != nil {
                    MainShellView(viewModel: viewModel)
                        .task {
                            await viewModel.autoLoginIfNeeded()
                        }
                } else {
                    LoginView(viewModel: viewModel)
                }
            }
            .environmentObject(settings)
            .preferredColorScheme(settings.colorScheme)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1160, height: 760)

        Settings {
            SettingsView(viewModel: viewModel)
                .environmentObject(settings)
                .preferredColorScheme(settings.colorScheme)
        }
    }
}
