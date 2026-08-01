import AppKit
import CoreGraphics
import LazyMouseCore

final class VirtualMouseEventInjector {
    private struct ClickRecord {
        let time: TimeInterval
        let position: CGPoint
        let count: Int
    }

    private var clickRecords: [Int: ClickRecord] = [:]
    private let eventSource: CGEventSource?

    init() {
        eventSource = CGEventSource(stateID: .combinedSessionState)
        eventSource?.localEventsSuppressionInterval = 0
    }

    @discardableResult
    func postButton(button: Int, pressed: Bool, at position: CGPoint) -> Bool {
        guard CGPreflightPostEventAccess(), let mouseButton = mouseButton(for: button) else { return false }
        let quartzPosition = quartzPoint(from: position)
        let type: CGEventType
        switch (button, pressed) {
        case (1, true): type = .leftMouseDown
        case (1, false): type = .leftMouseUp
        case (2, true): type = .rightMouseDown
        case (2, false): type = .rightMouseUp
        default: type = pressed ? .otherMouseDown : .otherMouseUp
        }
        guard let event = CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: quartzPosition, mouseButton: mouseButton) else { return false }
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(mouseButton.rawValue))
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState(for: button, at: position, pressed: pressed)))
        return post(event)
    }

    @discardableResult
    func postDrag(button: Int, at position: CGPoint) -> Bool {
        guard CGPreflightPostEventAccess(), let mouseButton = mouseButton(for: button) else { return false }
        let quartzPosition = quartzPoint(from: position)
        let type: CGEventType
        switch button {
        case 1: type = .leftMouseDragged
        case 2: type = .rightMouseDragged
        default: type = .otherMouseDragged
        }
        guard let event = CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: quartzPosition, mouseButton: mouseButton) else { return false }
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(mouseButton.rawValue))
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState(for: button, at: position, pressed: false)))
        return post(event)
    }

    @discardableResult
    func postScroll(delta: CGFloat, at position: CGPoint) -> Bool {
        guard CGPreflightPostEventAccess(), delta.isFinite, delta != 0 else { return false }
        let boundedDelta = min(max(delta.rounded(), CGFloat(Int32.min)), CGFloat(Int32.max))
        guard let event = CGEvent(scrollWheelEvent2Source: eventSource, units: .line, wheelCount: 1, wheel1: Int32(boundedDelta), wheel2: 0, wheel3: 0) else { return false }
        event.location = quartzPoint(from: position)
        return post(event)
    }

    private func post(_ event: CGEvent) -> Bool {
        let restorePoint = CGEvent(source: nil)?.location
        event.post(tap: .cghidEventTap)
        // Quartz events update the system cursor even when their location is synthetic.
        // Restore the trackpad cursor so the two pointer positions remain independent.
        if let restorePoint {
            CGWarpMouseCursorPosition(restorePoint)
        }
        return true
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
        case 3: return .center
        case 4, 5: return CGMouseButton(rawValue: UInt32(button - 1))
        default: return nil
        }
    }

    private func clickState(for button: Int, at position: CGPoint, pressed: Bool) -> Int {
        guard pressed else { return clickRecords[button]?.count ?? 1 }

        let now = ProcessInfo.processInfo.systemUptime
        let previous = clickRecords[button]
        let isContinuation = previous.map {
            now - $0.time <= NSEvent.doubleClickInterval
                && hypot(position.x - $0.position.x, position.y - $0.position.y) <= 6
        } ?? false
        let count = isContinuation ? min((previous?.count ?? 1) + 1, 2) : 1
        clickRecords[button] = ClickRecord(time: now, position: position, count: count)
        return count
    }
}
