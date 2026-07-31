import AppKit

@MainActor
final class ShutdownCoordinator {
    private weak var state: AppState?

    init(state: AppState) {
        self.state = state
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func applicationWillTerminate() {
        state?.shutdown()
    }
}
