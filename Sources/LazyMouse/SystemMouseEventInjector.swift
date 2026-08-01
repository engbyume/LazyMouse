import CoreGraphics

final class SystemMouseEventInjector {
    private let eventSource: CGEventSource?
    private var pressedButtons: Set<Int> = []

    init() {
        eventSource = CGEventSource(stateID: .combinedSessionState)
        eventSource?.localEventsSuppressionInterval = 0
    }

    @discardableResult
    func postMove(delta: CGPoint) -> Bool {
        guard CGPreflightPostEventAccess(), delta.x.isFinite, delta.y.isFinite,
              let current = CGEvent(source: nil)?.location else { return false }
        let destination = CGPoint(x: current.x + delta.x, y: current.y - delta.y)
        let button = mouseButton(for: pressedButtons.min() ?? 1) ?? .left
        let type = dragType(for: pressedButtons.min())
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: type,
            mouseCursorPosition: destination,
            mouseButton: button
        ) else { return false }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(delta.x.rounded()))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64((-delta.y).rounded()))
        SyntheticEventTag.mark(event)
        event.post(tap: .cghidEventTap)
        return true
    }

    @discardableResult
    func postButton(button: Int, pressed: Bool) -> Bool {
        guard CGPreflightPostEventAccess(), let current = CGEvent(source: nil)?.location,
              let mouseButton = mouseButton(for: button) else { return false }
        let type: CGEventType
        switch (button, pressed) {
        case (1, true): type = .leftMouseDown
        case (1, false): type = .leftMouseUp
        case (2, true): type = .rightMouseDown
        case (2, false): type = .rightMouseUp
        default: type = pressed ? .otherMouseDown : .otherMouseUp
        }
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: type,
            mouseCursorPosition: current,
            mouseButton: mouseButton
        ) else { return false }
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(mouseButton.rawValue))
        SyntheticEventTag.mark(event)
        if pressed {
            pressedButtons.insert(button)
        } else {
            pressedButtons.remove(button)
        }
        event.post(tap: .cghidEventTap)
        return true
    }

    @discardableResult
    func postScroll(_ input: ScrollInput) -> Bool {
        guard CGPreflightPostEventAccess(), !input.isZero,
              input.x.isFinite, input.y.isFinite,
              let current = CGEvent(source: nil)?.location else { return false }
        let unit: CGScrollEventUnit = input.unit == .pixel ? .pixel : .line
        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: unit,
            wheelCount: 2,
            wheel1: boundedInt32(input.y),
            wheel2: boundedInt32(input.x),
            wheel3: 0
        ) else { return false }
        event.location = current
        SyntheticEventTag.mark(event)
        event.post(tap: .cghidEventTap)
        return true
    }

    private func boundedInt32(_ value: CGFloat) -> Int32 {
        Int32(min(max(value.rounded(), CGFloat(Int32.min)), CGFloat(Int32.max)))
    }

    func releasePressedButtons() {
        for button in pressedButtons.sorted() {
            _ = postButton(button: button, pressed: false)
        }
        pressedButtons.removeAll()
    }

    private func dragType(for button: Int?) -> CGEventType {
        switch button {
        case 1: return .leftMouseDragged
        case 2: return .rightMouseDragged
        case .some: return .otherMouseDragged
        case nil: return .mouseMoved
        }
    }

    private func mouseButton(for button: Int) -> CGMouseButton? {
        switch button {
        case 1: return .left
        case 2: return .right
        case 3: return .center
        case 4, 5: return CGMouseButton(rawValue: UInt32(button - 1))
        default: return nil
        }
    }
}
