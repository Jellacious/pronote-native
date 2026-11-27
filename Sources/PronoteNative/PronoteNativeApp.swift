import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var menuBarController: MenuBarController?
    private weak var viewModel: AppViewModel?
    private weak var settings: AppSettings?
    private weak var mainWindow: NSWindow?

    func configureMenuBar(viewModel: AppViewModel, settings: AppSettings) {
        self.viewModel = viewModel
        self.settings = settings
        if menuBarController == nil {
            menuBarController = MenuBarController(viewModel: viewModel, settings: settings) { [weak self] in
                self?.showMainWindow()
            }
            NotificationManager.shared.configure { [weak self] section in
                self?.viewModel?.selectedSection = section
                self?.showMainWindow()
            }
        }
    }

    func attachMainWindow(_ window: NSWindow) {
        if mainWindow !== window {
            mainWindow = window
            window.delegate = self
        }
    }

    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async { [weak self] in
            if let win = self?.mainWindow {
                win.makeKeyAndOrderFront(nil)
            } else {
                for window in NSApp.windows where !(window is NSPanel) && !window.className.contains("StatusBar") {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === mainWindow {
            sender.orderOut(nil)
            if settings?.menuBarEnabled == true && settings?.keepInDockWhenClosed == false {
                NSApp.setActivationPolicy(.accessory)
            }
            return false
        }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }
}

private struct MainWindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onWindow(window)
            }
        }
    }
}

private struct MainWindowRootView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettings
    let appDelegate: AppDelegate

    var body: some View {
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
        .background(
            MainWindowAccessor { window in
                appDelegate.attachMainWindow(window)
            }
        )
        .onAppear {
            appDelegate.configureMenuBar(viewModel: viewModel, settings: settings)
        }
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
            MainWindowRootView(
                viewModel: viewModel,
                settings: settings,
                appDelegate: appDelegate
            )
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
