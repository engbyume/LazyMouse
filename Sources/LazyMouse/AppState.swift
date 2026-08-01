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
    @Published private(set) var dualCursorActive = false

    private let hid: HIDInputManager
    private let trackpadTap = TrackpadEventTap()
    private let overlay = CursorOverlayController()
    private let eventInjector = VirtualMouseEventInjector()
    private let catalog = DisplayCatalog()
    private let logger = Logger(subsystem: "com.engbyume.LazyMouse", category: "State")
    private var boundaries: [String: CursorBoundary] = [:]
    private var pressedButtons: [String: Set<Int>] = [:]
    private var regularCursorPosition = NSScreen.main?.frame.midPoint ?? CGPoint(x: 300, y: 300)
    private var regularPressedButtons: Set<Int> = []
    private var activeCursorDestination = CursorDestination.system
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
        overlayInputSource = preferredSource
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
        hid.onScroll = { [weak self] deviceID, input in
            DispatchQueue.main.async { self?.externalScroll(deviceID: deviceID, input: input) }
        }
        trackpadTap.onDelta = { [weak self] delta in
            DispatchQueue.main.async { self?.trackpadMove(delta: delta) }
        }
        trackpadTap.onButton = { [weak self] button, pressed in
            DispatchQueue.main.async { self?.trackpadButton(button: button, pressed: pressed) }
        }
        trackpadTap.onScroll = { [weak self] input in
            DispatchQueue.main.async { self?.trackpadScroll(input) }
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
        }
        shutdownCoordinator = ShutdownCoordinator(state: self)
        logger.notice("Overlay interaction access available: \(self.postEventsAvailable)")
        overlay.refreshScreens()
        synchronizeCursorRuntime()
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
                self.synchronizeCursorRuntime()
                self.overlay.update(cursors: self.cursorVisuals)
            }
        }
    }

    func shutdown() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        releasePressedButtons()
        restoreRegularSystemCursor()
        trackpadTap.stop()
        hid.stop()
        overlay.close()
        shutdownCoordinator = nil
    }

    var cursorVisuals: [CursorVisual] {
        guard separateCursorEnabled else { return [] }
        guard let device = devices.first, let redPosition = cursors[device.id] else { return [] }
        if dualCursorActive && activeCursorDestination == .overlay {
            return [
                CursorVisual(
                    id: "red-cursor-accent",
                    color: cursorColor,
                    scale: 1,
                    position: redPosition,
                    drawsAccentRing: true
                ),
                CursorVisual(
                    id: "regular-cursor",
                    color: CursorColor(red: 1, green: 1, blue: 1),
                    scale: 1,
                    position: regularCursorPosition,
                    usesSystemAppearance: true
                )
            ]
        }
        return [CursorVisual(
            id: device.id,
            color: cursorColor,
            scale: 1.25,
            position: redPosition
        )]
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
            hid.rescan()
            synchronizeCursorRuntime()
            return
        }

        releasePressedButtons()
        restoreRegularSystemCursor()
        trackpadTap.stop()
        hid.stop()
        devices = []
        cursors = [:]
        boundaries = [:]
        hidAvailable = false
        hidExclusive = false
        trackpadIsolationActive = false
        dualCursorActive = false
        externalMouseAvailable = hid.hasExternalMouse
        overlay.update(cursors: [])
    }

    func swapCursorAssignments() {
        guard separateCursorEnabled else { return }
        guard overlayInputSource == .builtInTrackpad || hid.hasExternalMouse else { return }
        releasePressedButtons()
        let newSource = overlayInputSource.other
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
        synchronizeCursorRuntime()
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
        regularCursorPosition = CursorGeometry.move(
            point: regularCursorPosition,
            delta: .zero,
            boundary: .free,
            displays: catalog.coreDisplays()
        )
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
        synchronizeCursorRuntime()
        overlay.update(cursors: cursorVisuals)
    }

    private func move(deviceID: String, delta: CGPoint) {
        guard dualCursorActive else { return }
        guard let point = cursors[deviceID] else { return }
        let destination = CursorGeometry.move(
            point: point,
            delta: delta,
            boundary: boundary(forID: deviceID),
            displays: catalog.coreDisplays()
        )
        cursors[deviceID] = destination
        activeCursorDestination = .overlay
        let buttons = pressedButtons[deviceID] ?? []
        if postMotion(at: destination, pressedButtons: buttons), buttons.isEmpty, !loggedOverlayMotion {
            loggedOverlayMotion = true
            logger.notice("Overlay hover movement posted from \(self.overlayInputSource.displayName, privacy: .public)")
        }
        if !buttons.isEmpty && !loggedOverlayDrag {
            loggedOverlayDrag = true
            logger.notice("Overlay drag event posted")
        }
        overlay.update(cursors: cursorVisuals)
    }

    private func moveRegularCursor(delta: CGPoint) {
        guard dualCursorActive else { return }
        regularCursorPosition = CursorGeometry.move(
            point: regularCursorPosition,
            delta: delta,
            boundary: .free,
            displays: catalog.coreDisplays()
        )
        activeCursorDestination = .system
        if postMotion(at: regularCursorPosition, pressedButtons: regularPressedButtons),
           regularPressedButtons.isEmpty, !loggedSystemMotion {
            loggedSystemMotion = true
            logger.notice("Regular cursor hover movement posted")
        }
        overlay.update(cursors: cursorVisuals)
    }

    @discardableResult
    private func postMotion(at position: CGPoint, pressedButtons: Set<Int>) -> Bool {
        if pressedButtons.isEmpty {
            return eventInjector.postMove(at: position)
        }
        return pressedButtons
            .sorted()
            .map { eventInjector.postDrag(button: $0, at: position) }
            .allSatisfy { $0 }
    }

    private func externalMove(deviceID: String, delta: CGPoint) {
        guard dualCursorActive else { return }
        if overlayInputSource.destination(for: .externalMouse) == .overlay {
            move(deviceID: deviceID, delta: delta)
        } else {
            moveRegularCursor(delta: delta)
        }
    }

    private func externalButton(deviceID: String, button: Int, pressed: Bool) {
        guard dualCursorActive else { return }
        if overlayInputSource.destination(for: .externalMouse) == .overlay {
            self.button(deviceID: deviceID, button: button, pressed: pressed)
        } else {
            regularButton(button: button, pressed: pressed)
        }
    }

    private func externalScroll(deviceID: String, input: ScrollInput) {
        guard dualCursorActive else { return }
        if overlayInputSource.destination(for: .externalMouse) == .overlay {
            scroll(deviceID: deviceID, input: input)
        } else {
            regularScroll(input)
        }
    }

    private func trackpadMove(delta: CGPoint) {
        guard dualCursorActive else { return }
        if overlayInputSource.destination(for: .builtInTrackpad) == .overlay {
            guard let deviceID = devices.first?.id else { return }
            move(deviceID: deviceID, delta: delta)
        } else {
            moveRegularCursor(delta: delta)
        }
    }

    private func trackpadButton(button: Int, pressed: Bool) {
        guard dualCursorActive else { return }
        if overlayInputSource.destination(for: .builtInTrackpad) == .overlay {
            guard let deviceID = devices.first?.id else { return }
            self.button(deviceID: deviceID, button: button, pressed: pressed)
        } else {
            regularButton(button: button, pressed: pressed)
        }
    }

    private func trackpadScroll(_ input: ScrollInput) {
        guard dualCursorActive else { return }
        if overlayInputSource.destination(for: .builtInTrackpad) == .overlay {
            guard let deviceID = devices.first?.id else { return }
            scroll(deviceID: deviceID, input: input)
        } else {
            regularScroll(input)
        }
    }

    private func button(deviceID: String, button: Int, pressed: Bool) {
        guard dualCursorActive else { return }
        guard let point = cursors[deviceID] else { return }
        activeCursorDestination = .overlay
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
        overlay.update(cursors: cursorVisuals)
    }

    private func scroll(deviceID: String, input: ScrollInput) {
        guard dualCursorActive else { return }
        guard let point = cursors[deviceID] else { return }
        activeCursorDestination = .overlay
        if eventInjector.postScroll(input, at: point), !loggedOverlayScroll {
            loggedOverlayScroll = true
            logger.notice("Overlay scroll event posted")
        }
        refreshPostEventsAvailability()
        overlay.update(cursors: cursorVisuals)
    }

    private func regularButton(button: Int, pressed: Bool) {
        guard dualCursorActive else { return }
        activeCursorDestination = .system
        if pressed {
            regularPressedButtons.insert(button)
        } else {
            regularPressedButtons.remove(button)
        }
        if eventInjector.postButton(button: button, pressed: pressed, at: regularCursorPosition),
           !loggedSystemButton {
            loggedSystemButton = true
            logger.notice("Regular cursor button event posted")
        }
        refreshPostEventsAvailability()
        overlay.update(cursors: cursorVisuals)
    }

    private func regularScroll(_ input: ScrollInput) {
        guard dualCursorActive else { return }
        activeCursorDestination = .system
        if eventInjector.postScroll(input, at: regularCursorPosition), !loggedSystemScroll {
            loggedSystemScroll = true
            logger.notice("Regular cursor scroll event posted")
        }
        refreshPostEventsAvailability()
        overlay.update(cursors: cursorVisuals)
    }

    private func releasePressedButtons() {
        for (deviceID, buttons) in pressedButtons {
            guard let point = cursors[deviceID] else { continue }
            for button in buttons {
                eventInjector.postButton(button: button, pressed: false, at: point)
            }
        }
        pressedButtons.removeAll()
        for button in regularPressedButtons.sorted() {
            eventInjector.postButton(button: button, pressed: false, at: regularCursorPosition)
        }
        regularPressedButtons.removeAll()
    }

    private func refreshPostEventsAvailability() {
        let available = CGPreflightPostEventAccess()
        if postEventsAvailable != available {
            postEventsAvailable = available
        }
    }

    private func synchronizeCursorRuntime() {
        let shouldActivate = separateCursorEnabled
            && hid.isExclusive
            && hid.hasExternalMouse
            && !devices.isEmpty
            && postEventsAvailable

        if shouldActivate {
            if !dualCursorActive {
                regularCursorPosition = currentSystemCursorPosition() ?? regularCursorPosition
            }
            let tapStarted = trackpadTap.start()
            trackpadIsolationActive = trackpadTap.isActive
            dualCursorActive = tapStarted && trackpadTap.isActive
        } else {
            if dualCursorActive {
                releasePressedButtons()
                restoreRegularSystemCursor()
            }
            trackpadTap.stop()
            trackpadIsolationActive = false
            dualCursorActive = false
        }
    }

    private func restoreRegularSystemCursor() {
        guard dualCursorActive, activeCursorDestination == .overlay else { return }
        activeCursorDestination = .system
        _ = eventInjector.postMove(at: regularCursorPosition)
    }

    private func currentSystemCursorPosition() -> CGPoint? {
        guard let quartzPosition = CGEvent(source: nil)?.location else { return nil }
        let quartzBounds = CGDisplayBounds(CGMainDisplayID())
        let appKitFrame = NSScreen.screens.first {
            guard let number = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return number.uint32Value == CGMainDisplayID()
        }?.frame ?? CGRect(origin: .zero, size: quartzBounds.size)
        return MouseEventGeometry.appKitPoint(
            from: quartzPosition,
            appKitPrimaryFrame: appKitFrame,
            quartzPrimaryBounds: quartzBounds
        )
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
