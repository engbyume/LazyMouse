import SwiftUI
import AppKit

@main
struct LazyMouseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MainMenuView()
                .environmentObject(appState)
        } label: {
            Image(nsImage: LazyMouseBranding.menuBarImage)
                .renderingMode(.original)
                .help("LazyMouse")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
