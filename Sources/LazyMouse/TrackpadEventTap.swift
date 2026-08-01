import CoreGraphics
import Foundation
import OSLog

final class TrackpadEventTap {
    typealias DeltaHandler = (CGPoint) -> Void
    typealias ButtonHandler = (Int, Bool) -> Void
    typealias ScrollHandler = (CGFloat) -> Void

    var onDelta: DeltaHandler?
    var onButton: ButtonHandler?
    var onScroll: ScrollHandler?
    private(set) var isActive = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let logger = Logger(subsystem: "com.engbyume.LazyMouse", category: "TrackpadTap")
    private var loggedFirstEvent = false

    deinit {
        stop()
    }

    @discardableResult
    func start() -> Bool {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            isActive = true
            return true
        }

        let eventTypes: [CGEventType] = [
            .mouseMoved,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .scrollWheel
        ]
        let mask = eventTypes.reduce(CGEventMask(0)) { result, type in
            result | (CGEventMask(1) << type.rawValue)
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: context
        ) else {
            isActive = false
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isActive = CGEvent.tapIsEnabled(tap: tap)
        logger.notice("Trackpad event tap started; enabled: \(self.isActive)")
        DispatchQueue.main.async { [weak self] in
            self?.postProbeEvent()
        }
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        isActive = false
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let tap = Unmanaged<TrackpadEventTap>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = tap.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                tap.isActive = true
            }
            return Unmanaged.passUnretained(event)
        }

        if SyntheticEventTag.contains(event) {
            return Unmanaged.passUnretained(event)
        }

        if !tap.loggedFirstEvent {
            tap.loggedFirstEvent = true
            tap.logger.notice("Trackpad event tap received its first untagged event: \(type.rawValue)")
        }

        tap.route(type: type, event: event)
        return nil
    }

    private func route(type: CGEventType, event: CGEvent) {
        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let deltaX = CGFloat(event.getIntegerValueField(.mouseEventDeltaX))
            let deltaY = CGFloat(event.getIntegerValueField(.mouseEventDeltaY))
            if deltaX != 0 || deltaY != 0 {
                onDelta?(CGPoint(x: deltaX, y: -deltaY))
            }
        case .leftMouseDown:
            onButton?(1, true)
        case .leftMouseUp:
            onButton?(1, false)
        case .rightMouseDown:
            onButton?(2, true)
        case .rightMouseUp:
            onButton?(2, false)
        case .otherMouseDown, .otherMouseUp:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
            onButton?(button, type == .otherMouseDown)
        case .scrollWheel:
            let pointDelta = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let lineDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let delta = pointDelta != 0 ? pointDelta : lineDelta
            if delta != 0 {
                onScroll?(CGFloat(delta))
            }
        default:
            break
        }
    }

    private func postProbeEvent() {
        guard CGPreflightPostEventAccess(), let location = CGEvent(source: nil)?.location,
              let event = CGEvent(
                mouseEventSource: CGEventSource(stateID: .privateState),
                mouseType: .mouseMoved,
                mouseCursorPosition: location,
                mouseButton: .left
              ) else { return }
        event.setIntegerValueField(.mouseEventDeltaX, value: 0)
        event.setIntegerValueField(.mouseEventDeltaY, value: 0)
        event.post(tap: .cghidEventTap)
    }
}
