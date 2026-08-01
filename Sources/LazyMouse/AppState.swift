import AppKit
import CoreGraphics
import LazyMouseCore
import OSLog

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
    @Published private(set) var overlayInputSource = OverlayInputSource.externalMouse
    @Published private(set) var externalMouseAvailable = false
    @Published private(set) var trackpadIsolationActive = false

    private let hid: HIDInputManager
    private let trackpadTap = TrackpadEventTap()
    private let overlay = CursorOverlayController()
    private let eventInjector = VirtualMouseEventInjector()
    private let systemEventInjector = SystemMouseEventInjector()
    private let catalog = DisplayCatalog()
    private let logger = Logger(subsystem: "com.engbyume.LazyMouse", category: "State")
    private var boundaries: [String: CursorBoundary] = [:]
    private var pressedButtons: [String: Set<Int>] = [:]
    private var loggedOverlayMotion = false
    private var loggedOverlayButton = false
    private var loggedOverlayDrag = false
    private var loggedOverlayScroll = false
    private var loggedSystemMotion = false
    private var loggedSystemButton = false
    private var loggedSystemScroll = false
    private var refreshTimer: Timer?
    private var shutdownCoordinator: ShutdownCoordinator?

    init() {
        let preferredSource = UserDefaults.standard.string(forKey: "overlayInputSource")
            .flatMap(OverlayInputSource.init(rawValue:)) ?? .externalMouse
        hid = HIDInputManager(captureSource: .externalMouse)
        refreshDisplays()
        hid.onDevicesChanged = { [weak self] devices in
            DispatchQueue.main.async { self?.setDevices(devices) }
        }
        hid.onDelta = { [weak self] deviceID, delta in
            DispatchQueue.main.async { self?.externalMove(deviceID: deviceID, delta: delta) }
        }
        hid.onButton = { [weak self] deviceID, button, pressed in
            DispatchQueue.main.async { self?.externalButton(deviceID: deviceID, button: button, pressed: pressed) }
        }
        hid.onScroll = { [weak self] deviceID, delta in
            DispatchQueue.main.async { self?.externalScroll(deviceID: deviceID, delta: delta) }
        }
        trackpadTap.onDelta = { [weak self] delta in
            DispatchQueue.main.async { self?.trackpadMove(delta: delta) }
        }
        trackpadTap.onButton = { [weak self] button, pressed in
            DispatchQueue.main.async { self?.trackpadButton(button: button, pressed: pressed) }
        }
        trackpadTap.onScroll = { [weak self] delta in
            DispatchQueue.main.async { self?.trackpadScroll(delta: delta) }
        }
        if separateCursorEnabled && !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
        if separateCursorEnabled && !postEventsAvailable {
            postEventsAvailable = CGRequestPostEventAccess()
        }
        if separateCursorEnabled {
            hid.start()
            hidAvailable = hid.isAvailable
            hidExclusive = hid.isExclusive
            externalMouseAvailable = hid.hasExternalMouse
            logger.notice("Startup overlay preference: \(preferredSource.displayName, privacy: .public); external mouse available: \(self.externalMouseAvailable)")
            if preferredSource == .builtInTrackpad && externalMouseAvailable {
                swapCursorAssignments()
            } else if preferredSource == .builtInTrackpad {
                UserDefaults.standard.set(OverlayInputSource.externalMouse.rawValue, forKey: "overlayInputSource")
            }
        }
        shutdownCoordinator = ShutdownCoordinator(state: self)
        logger.notice("Overlay interaction access available: \(self.postEventsAvailable)")
        overlay.refreshScreens()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshDisplays()
                self.hid.retryExclusiveCapture()
                self.hidAvailable = self.hid.isAvailable
                self.hidExclusive = self.hid.isExclusive
                self.externalMouseAvailable = self.hid.hasExternalMouse
                self.trackpadIsolationActive = self.trackpadTap.isActive
                self.refreshPostEventsAvailability()
                if self.overlayInputSource == .builtInTrackpad && !self.externalMouseAvailable {
                    self.swapCursorAssignments()
                }
                self.overlay.update(cursors: self.cursorVisuals)
            }
        }
    }

    func shutdown() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        releasePressedButtons()
        systemEventInjector.releasePressedButtons()
        trackpadTap.stop()
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
            externalMouseAvailable = hid.hasExternalMouse
            if overlayInputSource == .builtInTrackpad {
                trackpadIsolationActive = trackpadTap.start()
            }
            hid.rescan()
            return
        }

        releasePressedButtons()
        systemEventInjector.releasePressedButtons()
        trackpadTap.stop()
        hid.stop()
        devices = []
        cursors = [:]
        boundaries = [:]
        hidAvailable = false
        hidExclusive = false
        trackpadIsolationActive = false
        externalMouseAvailable = hid.hasExternalMouse
        overlay.update(cursors: [])
    }

    func swapCursorAssignments() {
        guard separateCursorEnabled else { return }
        guard overlayInputSource == .builtInTrackpad || hid.hasExternalMouse else { return }
        releasePressedButtons()
        systemEventInjector.releasePressedButtons()
        let newSource = overlayInputSource.other
        if newSource == .builtInTrackpad {
            guard trackpadTap.start() else {
                trackpadIsolationActive = false
                logger.error("Unable to isolate trackpad events for swapped cursor mode")
                return
            }
        } else {
            trackpadTap.stop()
        }
        overlayInputSource = newSource
        UserDefaults.standard.set(overlayInputSource.rawValue, forKey: "overlayInputSource")
        loggedOverlayMotion = false
        loggedOverlayButton = false
        loggedOverlayDrag = false
        loggedOverlayScroll = false
        loggedSystemMotion = false
        loggedSystemButton = false
        loggedSystemScroll = false
        hidAvailable = hid.isAvailable
        hidExclusive = hid.isExclusive
        externalMouseAvailable = hid.hasExternalMouse
        trackpadIsolationActive = trackpadTap.isActive
        hid.rescan()
        overlay.update(cursors: cursorVisuals)
        logger.notice("Overlay input changed to \(self.overlayInputSource.displayName, privacy: .public); external capture: \(self.hidExclusive); trackpad isolation: \(self.trackpadIsolationActive)")
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
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }

    func requestClickAccess() {
        postEventsAvailable = CGPreflightPostEventAccess() || CGRequestPostEventAccess()
        if !postEventsAvailable {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
            NSWorkspace.shared.open(url)
        }
    }

    func requestInputMonitoringAccess() {
        let preflightGranted = CGPreflightListenEventAccess()
        let requested = CGRequestListenEventAccess()
        rescanDevices()
        if !preflightGranted || !requested || !hid.isExclusive {
            openInputMonitoringSettings()
        }
    }

    private func setDevices(_ devices: [MouseDevice]) {
        let selectedDevices = Array(devices.prefix(1))
        self.devices = selectedDevices
        hidAvailable = hid.isAvailable
        hidExclusive = hid.isExclusive
        externalMouseAvailable = hid.hasExternalMouse
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
        if !loggedOverlayMotion {
            loggedOverlayMotion = true
            logger.notice("Overlay movement received from \(self.overlayInputSource.displayName, privacy: .public)")
        }
        for button in pressedButtons[deviceID] ?? [] {
            if eventInjector.postDrag(button: button, at: cursors[deviceID] ?? point), !loggedOverlayDrag {
                loggedOverlayDrag = true
                logger.notice("Overlay drag event posted")
            }
        }
        overlay.update(cursors: cursorVisuals)
    }

    private func externalMove(deviceID: String, delta: CGPoint) {
        guard separateCursorEnabled else { return }
        if overlayInputSource == .externalMouse {
            move(deviceID: deviceID, delta: delta)
        } else {
            if systemEventInjector.postMove(delta: delta), !loggedSystemMotion {
                loggedSystemMotion = true
                logger.notice("External mouse movement posted to the normal cursor")
            }
        }
    }

    private func externalButton(deviceID: String, button: Int, pressed: Bool) {
        guard separateCursorEnabled else { return }
        if overlayInputSource == .externalMouse {
            self.button(deviceID: deviceID, button: button, pressed: pressed)
        } else {
            if systemEventInjector.postButton(button: button, pressed: pressed), !loggedSystemButton {
                loggedSystemButton = true
                logger.notice("External mouse button event posted to the normal cursor")
            }
        }
    }

    private func externalScroll(deviceID: String, delta: CGFloat) {
        guard separateCursorEnabled else { return }
        if overlayInputSource == .externalMouse {
            scroll(deviceID: deviceID, delta: delta)
        } else {
            if systemEventInjector.postScroll(delta: delta), !loggedSystemScroll {
                loggedSystemScroll = true
                logger.notice("External mouse scroll event posted to the normal cursor")
            }
        }
    }

    private func trackpadMove(delta: CGPoint) {
        guard overlayInputSource == .builtInTrackpad, let deviceID = devices.first?.id else { return }
        move(deviceID: deviceID, delta: delta)
    }

    private func trackpadButton(button: Int, pressed: Bool) {
        guard overlayInputSource == .builtInTrackpad, let deviceID = devices.first?.id else { return }
        self.button(deviceID: deviceID, button: button, pressed: pressed)
    }

    private func trackpadScroll(delta: CGFloat) {
        guard overlayInputSource == .builtInTrackpad, let deviceID = devices.first?.id else { return }
        scroll(deviceID: deviceID, delta: delta)
    }

    private func button(deviceID: String, button: Int, pressed: Bool) {
        guard separateCursorEnabled else { return }
        guard let point = cursors[deviceID] else { return }
        if pressed {
            pressedButtons[deviceID, default: []].insert(button)
        } else {
            pressedButtons[deviceID, default: []].remove(button)
        }
        if eventInjector.postButton(button: button, pressed: pressed, at: point), !loggedOverlayButton {
            loggedOverlayButton = true
            logger.notice("Overlay button event posted")
        }
        refreshPostEventsAvailability()
    }

    private func scroll(deviceID: String, delta: CGFloat) {
        guard separateCursorEnabled else { return }
        guard let point = cursors[deviceID] else { return }
        if eventInjector.postScroll(delta: delta, at: point), !loggedOverlayScroll {
            loggedOverlayScroll = true
            logger.notice("Overlay scroll event posted")
        }
        refreshPostEventsAvailability()
    }

    private func releasePressedButtons() {
        for (deviceID, buttons) in pressedButtons {
            guard let point = cursors[deviceID] else { continue }
            for button in buttons {
                eventInjector.postButton(button: button, pressed: false, at: point)
            }
        }
        pressedButtons.removeAll()
    }

    private func refreshPostEventsAvailability() {
        let available = CGPreflightPostEventAccess()
        if postEventsAvailable != available {
            postEventsAvailable = available
        }
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
