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
        if SignedInteractionSelfTest.isRequested {
            ProcessInfo.processInfo.disableAutomaticTermination("LazyMouse signed interaction self-test")
        }
        SignedInteractionSelfTest.runIfRequested()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if SignedInteractionSelfTest.isRequested && !SignedInteractionSelfTest.allowsTermination {
            return .terminateCancel
        }
        return .terminateNow
    }
}
