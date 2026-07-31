import AppKit

@MainActor
final class CursorOverlayController {
    private var windows: [UInt32: NSWindow] = [:]
    private var views: [UInt32: CursorOverlayView] = [:]

    func refreshScreens() {
        let screens = NSScreen.screens
        let currentIDs = Set(screens.compactMap { displayID(for: $0) })
        for id in Set(windows.keys).subtracting(currentIDs) {
            windows[id]?.orderOut(nil)
            windows.removeValue(forKey: id)
            views.removeValue(forKey: id)
        }
        for screen in screens {
            guard let id = displayID(for: screen) else { continue }
            if let window = windows[id] {
                window.setFrame(screen.frame, display: true)
                continue
            }
            let view = CursorOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), globalOrigin: screen.frame.origin)
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.contentView = view
            window.orderFrontRegardless()
            windows[id] = window
            views[id] = view
        }
    }

    func update(cursors: [CursorVisual]) {
        refreshScreens()
        for (id, view) in views {
            view.cursors = cursors.filter { cursor in
                guard let screen = NSScreen.screens.first(where: { displayID(for: $0) == id }) else { return false }
                return screen.frame.insetBy(dx: -80, dy: -80).contains(cursor.position)
            }
            view.needsDisplay = true
        }
    }

    func close() {
        windows.values.forEach { $0.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
    }

    private func displayID(for screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

final class CursorOverlayView: NSView {
    var cursors: [CursorVisual] = []
    private let globalOrigin: CGPoint

    init(frame: NSRect, globalOrigin: CGPoint) {
        self.globalOrigin = globalOrigin
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        globalOrigin = .zero
        super.init(coder: coder)
    }

    override func draw(_ dirtyRect: NSRect) {
        for cursor in cursors {
            let point = CGPoint(x: cursor.position.x - globalOrigin.x, y: cursor.position.y - globalOrigin.y)
            let color = NSColor(hue: CGFloat(cursor.colorIndex % 8) / 8.0, saturation: 0.85, brightness: 0.95, alpha: 0.95)
            let arrow = NSBezierPath()
            arrow.move(to: point)
            arrow.line(to: CGPoint(x: point.x + 3, y: point.y - 23))
            arrow.line(to: CGPoint(x: point.x + 9, y: point.y - 15))
            arrow.line(to: CGPoint(x: point.x + 17, y: point.y - 18))
            arrow.close()
            color.setFill()
            arrow.fill()
            NSColor.white.setStroke()
            arrow.lineWidth = 1.5
            arrow.stroke()

            let text = NSString(string: cursor.label)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.white,
                .backgroundColor: color.withAlphaComponent(0.85)
            ]
            text.draw(at: CGPoint(x: point.x + 18, y: point.y - 19), withAttributes: attributes)
        }
    }
}
