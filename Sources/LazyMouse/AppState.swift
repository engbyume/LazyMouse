import AppKit
import CoreGraphics
import LazyMouseCore

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var devices: [MouseDevice] = []
    @Published private(set) var cursors: [String: CGPoint] = [:]
    @Published private(set) var displays: [DisplayChoice] = []
    @Published private(set) var hidAvailable = false
    @Published private(set) var hidExclusive = false
    @Published private(set) var postEventsAvailable = CGPreflightPostEventAccess()
    @Published private(set) var separateCursorEnabled = UserDefaults.standard.object(forKey: "separateCursorEnabled") as? Bool ?? true
    @Published private(set) var cursorColor = CursorColor(hex: UserDefaults.standard.string(forKey: "cursorColor") ?? "") ?? .red

    private let hid = HIDInputManager()
    private let overlay = CursorOverlayController()
    private let eventInjector = VirtualMouseEventInjector()
    private let catalog = DisplayCatalog()
    private var boundaries: [String: CursorBoundary] = [:]
    private var pressedButtons: [String: Set<Int>] = [:]
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
        hid.onButton = { [weak self] deviceID, button, pressed in
            DispatchQueue.main.async { self?.button(deviceID: deviceID, button: button, pressed: pressed) }
        }
        hid.onScroll = { [weak self] deviceID, delta in
            DispatchQueue.main.async { self?.scroll(deviceID: deviceID, delta: delta) }
        }
        if separateCursorEnabled && !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
        if separateCursorEnabled {
            hid.start()
            hidAvailable = hid.isAvailable
            hidExclusive = hid.isExclusive
        }
        shutdownCoordinator = ShutdownCoordinator(state: self)
        overlay.refreshScreens()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshDisplays()
                self.overlay.update(cursors: self.cursorVisuals)
            }
        }
    }

    func shutdown() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        hid.stop()
        overlay.close()
        shutdownCoordinator = nil
    }

    var cursorVisuals: [CursorVisual] {
        guard separateCursorEnabled else { return [] }
        return devices.compactMap { device in
            guard let position = cursors[device.id] else { return nil }
            return CursorVisual(id: device.id, color: cursorColor, scale: 1.25, position: position)
        }
    }

    func setCursorColor(_ color: NSColor) {
        let normalized = CursorColor(nsColor: color)
        guard normalized != cursorColor else { return }
        cursorColor = normalized
        UserDefaults.standard.set(normalized.hex, forKey: "cursorColor")
        overlay.update(cursors: cursorVisuals)
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

    func rescanDevices() {
        guard separateCursorEnabled else { return }
        if !hid.isAvailable {
            hid.start()
        } else {
            hid.retryExclusiveCapture()
        }
        hid.rescan()
        hidAvailable = hid.isAvailable
        hidExclusive = hid.isExclusive
    }

    func setSeparateCursorEnabled(_ enabled: Bool) {
        guard enabled != separateCursorEnabled else { return }
        separateCursorEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "separateCursorEnabled")

        if enabled {
            hid.start()
            hidAvailable = hid.isAvailable
            hidExclusive = hid.isExclusive
            hid.rescan()
            return
        }

        for (deviceID, buttons) in pressedButtons {
            guard let point = cursors[deviceID] else { continue }
            for button in buttons {
                eventInjector.postButton(button: button, pressed: false, at: point)
            }
        }
        pressedButtons.removeAll()
        hid.stop()
        devices = []
        cursors = [:]
        boundaries = [:]
        hidAvailable = false
        hidExclusive = false
        overlay.update(cursors: [])
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

    func openInputMonitoringSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    func requestClickAccess() {
        postEventsAvailable = CGPreflightPostEventAccess() || CGRequestPostEventAccess()
        if !postEventsAvailable {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    func requestInputMonitoringAccess() {
        let granted = CGPreflightListenEventAccess() || CGRequestListenEventAccess()
        if granted {
            rescanDevices()
        }
    }

    private func setDevices(_ devices: [MouseDevice]) {
        let selectedDevices = Array(devices.prefix(1))
        self.devices = selectedDevices
        let defaultPoint = NSScreen.main?.frame.midPoint ?? CGPoint(x: 300, y: 300)
        for device in selectedDevices where cursors[device.id] == nil {
            cursors[device.id] = defaultPoint
        }
        for id in cursors.keys where !selectedDevices.contains(where: { $0.id == id }) {
            cursors.removeValue(forKey: id)
            boundaries.removeValue(forKey: id)
            pressedButtons.removeValue(forKey: id)
        }
        overlay.update(cursors: cursorVisuals)
    }

    private func move(deviceID: String, delta: CGPoint) {
        guard separateCursorEnabled else { return }
        guard let point = cursors[deviceID] else { return }
        cursors[deviceID] = CursorGeometry.move(
            point: point,
            delta: delta,
            boundary: boundary(forID: deviceID),
            displays: catalog.coreDisplays()
        )
        for button in pressedButtons[deviceID] ?? [] {
            eventInjector.postDrag(button: button, at: cursors[deviceID] ?? point)
        }
        overlay.update(cursors: cursorVisuals)
    }

    private func button(deviceID: String, button: Int, pressed: Bool) {
        guard separateCursorEnabled else { return }
        guard let point = cursors[deviceID] else { return }
        if pressed {
            pressedButtons[deviceID, default: []].insert(button)
        } else {
            pressedButtons[deviceID, default: []].remove(button)
        }
        eventInjector.postButton(button: button, pressed: pressed, at: point)
        postEventsAvailable = CGPreflightPostEventAccess()
    }

    private func scroll(deviceID: String, delta: CGFloat) {
        guard separateCursorEnabled else { return }
        guard let point = cursors[deviceID] else { return }
        eventInjector.postScroll(delta: delta, at: point)
        postEventsAvailable = CGPreflightPostEventAccess()
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

}

private extension CGRect {
    var midPoint: CGPoint { CGPoint(x: midX, y: midY) }
}
