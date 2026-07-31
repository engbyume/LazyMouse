import AppKit
import ApplicationServices
import LazyMouseCore

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var devices: [MouseDevice] = []
    @Published private(set) var cursors: [String: CGPoint] = [:]
    @Published private(set) var independentMode = false
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()
    @Published private(set) var displays: [DisplayChoice] = []

    private let hid = HIDInputManager()
    private let eventTap = MouseMovementTap()
    private let overlay = CursorOverlayController()
    private let catalog = DisplayCatalog()
    private var boundaries: [String: CursorBoundary] = [:]
    private var refreshTimer: Timer?
    private var shutdownCoordinator: ShutdownCoordinator?

    init() {
        refreshDisplays()
        hid.onDevicesChanged = { [weak self] devices in
            DispatchQueue.main.async { self?.setDevices(devices) }
        }
        hid.onDelta = { [weak self] deviceID, delta in
            DispatchQueue.main.async { self?.move(deviceID: deviceID, delta: delta) }
        }
        hid.start()
        shutdownCoordinator = ShutdownCoordinator(state: self)
        overlay.refreshScreens()
        if UserDefaults.standard.bool(forKey: "independentMode") {
            setIndependentMode(true)
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.accessibilityTrusted = AXIsProcessTrusted()
                self.refreshDisplays()
                self.overlay.update(cursors: self.cursorVisuals)
            }
        }
    }

    func shutdown() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        hid.stop()
        eventTap.stop()
        overlay.close()
        shutdownCoordinator = nil
    }

    var cursorVisuals: [CursorVisual] {
        devices.enumerated().compactMap { index, device in
            guard let position = cursors[device.id] else { return nil }
            return CursorVisual(id: device.id, label: device.name, colorIndex: index, position: position)
        }
    }

    func boundary(for device: MouseDevice) -> CursorBoundary {
        boundaries[device.id] ?? loadBoundary(for: device.id)
    }

    func setBoundary(_ boundary: CursorBoundary, for device: MouseDevice) {
        boundaries[device.id] = boundary
        switch boundary {
        case .free:
            UserDefaults.standard.set("free", forKey: key(for: device.id))
        case let .display(id):
            UserDefaults.standard.set(id, forKey: key(for: device.id))
        }
        if let position = cursors[device.id], case let .display(id) = boundary, let frame = catalog.frame(for: id) {
            cursors[device.id] = CursorGeometry.clamp(position, to: frame)
            overlay.update(cursors: cursorVisuals)
        }
    }

    func refreshDisplays() {
        catalog.refresh()
        displays = catalog.displays
        for device in devices {
            guard case let .display(displayID) = boundary(for: device),
                  let frame = catalog.frame(for: displayID),
                  let position = cursors[device.id] else { continue }
            cursors[device.id] = CursorGeometry.clamp(position, to: frame)
        }
        overlay.refreshScreens()
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func setIndependentMode(_ enabled: Bool) {
        if enabled {
            guard eventTap.start() else {
                independentMode = false
                UserDefaults.standard.set(false, forKey: "independentMode")
                accessibilityTrusted = AXIsProcessTrusted()
                return
            }
        } else {
            eventTap.stop()
        }
        independentMode = enabled
        UserDefaults.standard.set(enabled, forKey: "independentMode")
    }

    private func setDevices(_ devices: [MouseDevice]) {
        self.devices = devices
        let defaultPoint = NSScreen.main?.frame.midPoint ?? CGPoint(x: 300, y: 300)
        for device in devices where cursors[device.id] == nil {
            cursors[device.id] = defaultPoint
        }
        for id in cursors.keys where !devices.contains(where: { $0.id == id }) {
            cursors.removeValue(forKey: id)
            boundaries.removeValue(forKey: id)
        }
        overlay.update(cursors: cursorVisuals)
    }

    private func move(deviceID: String, delta: CGPoint) {
        guard let point = cursors[deviceID] else { return }
        cursors[deviceID] = CursorGeometry.move(
            point: point,
            delta: delta,
            boundary: boundary(forID: deviceID),
            displays: catalog.coreDisplays()
        )
        overlay.update(cursors: cursorVisuals)
    }

    private func boundary(forID id: String) -> CursorBoundary {
        if let boundary = boundaries[id] { return boundary }
        let boundary = loadBoundary(for: id)
        boundaries[id] = boundary
        return boundary
    }

    private func loadBoundary(for id: String) -> CursorBoundary {
        guard let value = UserDefaults.standard.object(forKey: key(for: id)) else { return .free }
        if let string = value as? String, string == "free" { return .free }
        if let number = value as? NSNumber { return .display(number.uint32Value) }
        return .free
    }

    private func key(for id: String) -> String { "boundary.\(id)" }

    private func updateEventTap() {
        if independentMode {
            if !eventTap.isRunning, !eventTap.start() {
                accessibilityTrusted = AXIsProcessTrusted()
            }
        } else {
            eventTap.stop()
        }
    }
}

private extension CGRect {
    var midPoint: CGPoint { CGPoint(x: midX, y: midY) }
}
