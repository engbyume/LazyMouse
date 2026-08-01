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

@MainActor
enum AppTermination {
    private(set) static var requested = false

    static func request() {
        requested = true
        NSApp.terminate(nil)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if SignedInteractionSelfTest.isRequested {
            ProcessInfo.processInfo.disableAutomaticTermination("LazyMouse signed interaction self-test")
        } else {
            ProcessInfo.processInfo.disableAutomaticTermination("LazyMouse menu bar service")
        }
        SignedInteractionSelfTest.runIfRequested()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if SignedInteractionSelfTest.isRequested && !SignedInteractionSelfTest.allowsTermination {
            return .terminateCancel
        }
        return AppTermination.requested || SignedInteractionSelfTest.allowsTermination
            ? .terminateNow
            : .terminateCancel
    }
}
