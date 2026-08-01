import SwiftUI
import AppKit
import OSLog

@main
struct LazyMouseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
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
    private var appState: AppState?
    private var statusItem: NSStatusItem?
    private var statusVisibilityTimer: Timer?
    private let popover = NSPopover()
    private let logger = Logger(subsystem: "com.engbyume.LazyMouse", category: "MenuBar")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if SignedInteractionSelfTest.isRequested {
            ProcessInfo.processInfo.disableAutomaticTermination("LazyMouse signed interaction self-test")
            SignedInteractionSelfTest.runIfRequested()
            return
        }
        ProcessInfo.processInfo.disableAutomaticTermination("LazyMouse menu bar service")

        let state = AppState()
        appState = state
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: MainMenuView().environmentObject(state)
        )

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "com.engbyume.LazyMouse.statusItem"
        item.behavior = []
        item.isVisible = true
        item.button?.image = LazyMouseBranding.menuBarImage
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "LazyMouse"
        item.button?.setAccessibilityLabel("LazyMouse")
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        statusItem = item
        statusVisibilityTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let item = self.statusItem else { return }
                if !item.isVisible {
                    item.isVisible = true
                }
            }
        }
        logger.notice("Status item installed; visible=\(item.isVisible); button=\(item.button != nil)")
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
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
