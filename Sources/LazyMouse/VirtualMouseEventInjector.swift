import AppKit
import CoreGraphics
import LazyMouseCore

final class VirtualMouseEventInjector {
    func postButton(button: Int, pressed: Bool, at position: CGPoint) {
        guard CGPreflightPostEventAccess(), let mouseButton = mouseButton(for: button) else { return }
        let quartzPosition = quartzPoint(from: position)
        let type: CGEventType
        switch (button, pressed) {
        case (1, true): type = .leftMouseDown
        case (1, false): type = .leftMouseUp
        case (2, true): type = .rightMouseDown
        case (2, false): type = .rightMouseUp
        default: type = pressed ? .otherMouseDown : .otherMouseUp
        }
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: quartzPosition, mouseButton: mouseButton) else { return }
        post(event)
    }

    func postDrag(button: Int, at position: CGPoint) {
        guard CGPreflightPostEventAccess(), let mouseButton = mouseButton(for: button) else { return }
        let quartzPosition = quartzPoint(from: position)
        let type: CGEventType
        switch button {
        case 1: type = .leftMouseDragged
        case 2: type = .rightMouseDragged
        default: type = .otherMouseDragged
        }
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: quartzPosition, mouseButton: mouseButton) else { return }
        post(event)
    }

    func postScroll(delta: CGFloat, at position: CGPoint) {
        guard CGPreflightPostEventAccess(), delta != 0,
              let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(delta), wheel2: 0, wheel3: 0) else { return }
        event.location = quartzPoint(from: position)
        post(event)
    }

    private func post(_ event: CGEvent) {
        let restorePoint = CGEvent(source: nil)?.location
        event.post(tap: .cghidEventTap)
        // Quartz events update the system cursor even when their location is synthetic.
        // Restore the trackpad cursor so the two pointer positions remain independent.
        if let restorePoint {
            CGWarpMouseCursorPosition(restorePoint)
        }
    }

    private func quartzPoint(from appKitPoint: CGPoint) -> CGPoint {
        let quartzPrimaryBounds = CGDisplayBounds(CGMainDisplayID())
        let appKitPrimaryFrame = NSScreen.screens.first {
            guard let number = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return number.uint32Value == CGMainDisplayID()
        }?.frame ?? CGRect(origin: .zero, size: quartzPrimaryBounds.size)
        return MouseEventGeometry.quartzPoint(
            from: appKitPoint,
            appKitPrimaryFrame: appKitPrimaryFrame,
            quartzPrimaryBounds: quartzPrimaryBounds
        )
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
