import AppKit

final class InteractionProbeView: NSView {
    private static let expected = [
        "move", "leftDown", "leftDrag", "leftUp", "rightDown", "rightUp", "scroll",
        "move", "leftDown", "leftDrag", "leftUp", "rightDown", "rightUp", "scroll"
    ]

    private var events: [String] = []
    private var locations: [CGPoint] = []

    var recordedEvents: [String] { events }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseMoved(with event: NSEvent) { record("move", event: event) }
    override func mouseDown(with event: NSEvent) { record("leftDown", event: event) }
    override func mouseDragged(with event: NSEvent) { record("leftDrag", event: event) }
    override func mouseUp(with event: NSEvent) { record("leftUp", event: event) }
    override func rightMouseDown(with event: NSEvent) { record("rightDown", event: event) }
    override func rightMouseUp(with event: NSEvent) { record("rightUp", event: event) }
    override func scrollWheel(with event: NSEvent) { record("scroll", event: event) }

    private func record(_ name: String, event: NSEvent) {
        events.append(name)
        locations.append(event.locationInWindow)
        guard events.count == Self.expected.count else { return }
        let separatePositions = locations[0].x + 30 < locations[7].x
        let passed = events == Self.expected && separatePositions
        let result = "INTERACTION_PROBE \(passed ? "PASS" : "FAIL") separatePositions=\(separatePositions) events=\(events.joined(separator: ","))\n"
        try? Data(result.utf8).write(
            to: URL(fileURLWithPath: "/tmp/lazymouse-interaction-probe.txt"),
            options: .atomic
        )
        NSApp.terminate(nil)
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.regular)
let view = InteractionProbeView(frame: CGRect(x: 0, y: 0, width: 180, height: 140))
let window = NSWindow(
    contentRect: CGRect(x: 120, y: 120, width: 180, height: 140),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
window.contentView = view
window.acceptsMouseMovedEvents = true
window.makeKeyAndOrderFront(nil)
window.makeFirstResponder(view)
application.activate(ignoringOtherApps: true)
DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
    let events = view.recordedEvents.joined(separator: ",")
    try? Data("INTERACTION_PROBE FAIL timeout events=\(events)\n".utf8).write(
        to: URL(fileURLWithPath: "/tmp/lazymouse-interaction-probe.txt"),
        options: .atomic
    )
    NSApp.terminate(nil)
}
application.run()
