import AppKit

final class InteractionProbeView: NSView {
    private static let expected = [
        "leftDown", "leftDrag", "leftUp", "rightDown", "rightUp", "scroll",
        "leftDown", "leftDrag", "leftUp", "rightDown", "rightUp", "scroll"
    ]

    private var events: [String] = []

    var recordedEvents: [String] { events }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseMoved(with event: NSEvent) { record("move") }
    override func mouseDown(with event: NSEvent) { record("leftDown") }
    override func mouseDragged(with event: NSEvent) { record("leftDrag") }
    override func mouseUp(with event: NSEvent) { record("leftUp") }
    override func rightMouseDown(with event: NSEvent) { record("rightDown") }
    override func rightMouseUp(with event: NSEvent) { record("rightUp") }
    override func scrollWheel(with event: NSEvent) { record("scroll") }

    private func record(_ event: String) {
        events.append(event)
        guard events.count == Self.expected.count else { return }
        let passed = events == Self.expected
        let result = "INTERACTION_PROBE \(passed ? "PASS" : "FAIL") events=\(events.joined(separator: ","))\n"
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
