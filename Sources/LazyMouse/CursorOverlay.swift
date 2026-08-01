import AppKit

@MainActor
final class CursorOverlayController {
    private var windows: [UInt32: NSWindow] = [:]
    private var views: [UInt32: CursorOverlayView] = [:]
    private var screenFrames: [UInt32: CGRect] = [:]

    func refreshScreens() {
        let screens = NSScreen.screens
        let currentIDs = Set(screens.compactMap { displayID(for: $0) })
        screenFrames = [:]
        for id in Set(windows.keys).subtracting(currentIDs) {
            windows[id]?.orderOut(nil)
            windows.removeValue(forKey: id)
            views.removeValue(forKey: id)
        }
        for screen in screens {
            guard let id = displayID(for: screen) else { continue }
            screenFrames[id] = screen.frame
            if let window = windows[id] {
                window.setFrame(screen.frame, display: true)
                views[id]?.setGlobalOrigin(screen.frame.origin)
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
        for (id, view) in views {
            view.cursors = cursors.filter { cursor in
                screenFrames[id]?.insetBy(dx: -80, dy: -80).contains(cursor.position) == true
            }
            view.needsDisplay = true
        }
    }

    func close() {
        windows.values.forEach { $0.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        screenFrames.removeAll()
    }

    private func displayID(for screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

final class CursorOverlayView: NSView {
    var cursors: [CursorVisual] = []
    private var globalOrigin: CGPoint
    private var tintedImages: [String: NSImage] = [:]

    init(frame: NSRect, globalOrigin: CGPoint) {
        self.globalOrigin = globalOrigin
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        globalOrigin = .zero
        super.init(coder: coder)
    }

    func setGlobalOrigin(_ origin: CGPoint) {
        globalOrigin = origin
    }

    override func draw(_ dirtyRect: NSRect) {
        for cursor in cursors {
            let point = CGPoint(x: cursor.position.x - globalOrigin.x, y: cursor.position.y - globalOrigin.y)
            drawCursor(cursor, at: point)
        }
    }

    private func drawCursor(_ cursor: CursorVisual, at point: CGPoint) {
        let arrow = NSCursor.arrow
        let image = arrow.image
        let hotSpot = arrow.hotSpot
        let scale = max(cursor.scale, 1.0)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(
            x: point.x - hotSpot.x * scale,
            y: point.y - (image.size.height - hotSpot.y) * scale
        )
        let rect = NSRect(origin: origin, size: size)

        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
        shadow.shadowBlurRadius = 2.5
        shadow.shadowOffset = NSSize(width: 1, height: -1)
        shadow.set()
        tintedImage(for: cursor, source: image, size: size).draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private func tintedImage(for cursor: CursorVisual, source: NSImage, size: NSSize) -> NSImage {
        let key = "\(cursor.color.hex)-\(cursor.color.alpha)-\(cursor.scale)-\(size.width)-\(size.height)"
        if let cached = tintedImages[key] {
            return cached
        }

        let image = NSImage(size: size)
        image.lockFocus()
        let localRect = NSRect(origin: .zero, size: size)
        source.draw(in: localRect, from: .zero, operation: .sourceOver, fraction: 1)
        cursor.color.nsColor.set()
        localRect.fill(using: .sourceIn)
        image.unlockFocus()
        tintedImages[key] = image
        return image
    }
}
