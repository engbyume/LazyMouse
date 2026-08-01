import AppKit
import CoreGraphics
import OSLog

@MainActor
final class SignedInteractionSelfTest {
    private static var activeTest: SignedInteractionSelfTest?
    private(set) static var allowsTermination = false

    private let logger = Logger(subsystem: "com.engbyume.LazyMouse", category: "SelfTest")
    private var cursorBefore = CGPoint.zero
    private var postResults: [Bool] = []
    private var trackpadTap: TrackpadEventTap?
    private var trackpadMoveWorked = false
    private var trackpadButtonEvents = 0
    private var trackpadScrollWorked = false

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--interaction-self-test")
    }

    static func runIfRequested() {
        guard isRequested else { return }
        let test = SignedInteractionSelfTest()
        allowsTermination = false
        activeTest = test
        test.start()
    }

    private func start() {
        cursorBefore = CGEvent(source: nil)?.location ?? .zero
        let tap = TrackpadEventTap()
        tap.onDelta = { [weak self] delta in
            if delta.x == 5 && delta.y == 3 { self?.trackpadMoveWorked = true }
        }
        tap.onButton = { [weak self] button, _ in
            if button == 1 { self?.trackpadButtonEvents += 1 }
        }
        tap.onScroll = { [weak self] input in
            if input.y == -4 { self?.trackpadScrollWorked = true }
        }
        trackpadTap = tap
        guard tap.start() else {
            finish()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.postTrackpadTapEvents()
        }
    }

    private func postTrackpadTapEvents() {
        let source = CGEventSource(stateID: .privateState)
        let location = CGEvent(source: nil)?.location ?? .zero
        if let move = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: location,
            mouseButton: .left
        ) {
            move.setIntegerValueField(.mouseEventDeltaX, value: 5)
            move.setIntegerValueField(.mouseEventDeltaY, value: -3)
            move.post(tap: .cghidEventTap)
        }
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(
                mouseEventSource: source,
                mouseType: type,
                mouseCursorPosition: location,
                mouseButton: .left
            )?.post(tap: .cghidEventTap)
        }
        CGEvent(
            scrollWheelEvent2Source: source,
            units: .line,
            wheelCount: 1,
            wheel1: -4,
            wheel2: 0,
            wheel3: 0
        )?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.trackpadTap?.stop()
            self?.trackpadTap = nil
            self?.postEvents()
        }
    }

    private func postEvents() {
        let injector = VirtualMouseEventInjector()
        let firstStart = CGPoint(x: 170, y: 170)
        let firstDrag = CGPoint(x: 190, y: 180)
        let secondStart = CGPoint(x: 230, y: 210)
        let secondDrag = CGPoint(x: 250, y: 220)
        postRoute(injector: injector, start: firstStart, drag: firstDrag) { [weak self] in
            guard let self else { return }
            self.postRoute(injector: injector, start: secondStart, drag: secondDrag) { [weak self] in
                guard let self else { return }
                CGWarpMouseCursorPosition(self.cursorBefore)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.finish()
                }
            }
        }
    }

    private func postRoute(
        injector: VirtualMouseEventInjector,
        start: CGPoint,
        drag: CGPoint,
        completion: @escaping () -> Void
    ) {
        postResults.append(injector.postMove(at: start))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.postResults.append(contentsOf: [
                injector.postButton(button: 1, pressed: true, at: start),
                injector.postDrag(button: 1, at: drag),
                injector.postButton(button: 1, pressed: false, at: drag),
                injector.postButton(button: 2, pressed: true, at: start),
                injector.postButton(button: 2, pressed: false, at: start),
                injector.postScroll(ScrollInput(x: 4, y: -8, unit: .pixel), at: start)
            ])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: completion)
        }
    }

    private func finish() {
        let cursorAfter = CGEvent(source: nil)?.location ?? .zero
        let cursorStable = hypot(cursorAfter.x - cursorBefore.x, cursorAfter.y - cursorBefore.y) <= 0.5
        let passed = CGPreflightPostEventAccess()
            && cursorStable
            && trackpadMoveWorked
            && trackpadButtonEvents == 2
            && trackpadScrollWorked
            && !postResults.contains(false)
        let result = "SIGNED_INTERACTION_SELF_TEST \(passed ? "PASS" : "FAIL") postAccess=\(CGPreflightPostEventAccess()) cursorStable=\(cursorStable) trackpadMove=\(trackpadMoveWorked) trackpadButtons=\(trackpadButtonEvents) trackpadScroll=\(trackpadScrollWorked) dualCursorPosts=\(postResults)"
        try? Data("\(result)\n".utf8).write(
            to: URL(fileURLWithPath: "/tmp/lazymouse-signed-self-test.txt"),
            options: .atomic
        )
        if passed {
            logger.notice("SIGNED_INTERACTION_SELF_TEST PASS")
        } else {
            logger.error("SIGNED_INTERACTION_SELF_TEST FAIL cursorStable=\(cursorStable)")
        }
        Self.activeTest = nil
        Self.allowsTermination = true
        ProcessInfo.processInfo.enableAutomaticTermination("LazyMouse signed interaction self-test")
        NSApp.terminate(nil)
    }
}
