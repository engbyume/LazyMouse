import CoreGraphics

final class VirtualMouseEventInjector {
    func postButton(button: Int, pressed: Bool, at position: CGPoint) {
        guard CGPreflightPostEventAccess(), let mouseButton = mouseButton(for: button) else { return }
        let type: CGEventType
        switch (button, pressed) {
        case (1, true): type = .leftMouseDown
        case (1, false): type = .leftMouseUp
        case (2, true): type = .rightMouseDown
        case (2, false): type = .rightMouseUp
        default: type = pressed ? .otherMouseDown : .otherMouseUp
        }
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: position, mouseButton: mouseButton)?.post(tap: .cghidEventTap)
    }

    func postDrag(button: Int, at position: CGPoint) {
        guard CGPreflightPostEventAccess(), let mouseButton = mouseButton(for: button) else { return }
        let type: CGEventType
        switch button {
        case 1: type = .leftMouseDragged
        case 2: type = .rightMouseDragged
        default: type = .otherMouseDragged
        }
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: position, mouseButton: mouseButton)?.post(tap: .cghidEventTap)
    }

    func postScroll(delta: CGFloat, at position: CGPoint) {
        guard CGPreflightPostEventAccess(), delta != 0,
              let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(delta), wheel2: 0, wheel3: 0) else { return }
        event.location = position
        event.post(tap: .cghidEventTap)
    }

    private func mouseButton(for button: Int) -> CGMouseButton? {
        switch button {
        case 1: return .left
        case 2: return .right
        case 3, 4, 5: return .center
        default: return nil
        }
    }
}
