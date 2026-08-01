import AppKit

enum LazyMouseBranding {
    static let appIconImage: NSImage = {
        let image = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            .flatMap(NSImage.init(contentsOf:))
            ?? (menuBarImage.copy() as? NSImage)
            ?? fallbackSymbol()
        image.size = NSSize(width: 24, height: 24)
        image.isTemplate = false
        return image
    }()

    static let menuBarImage: NSImage = {
        let image = Bundle.main.url(forResource: "AppIconMenu", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
            ?? Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
                .flatMap(NSImage.init(contentsOf:))
            ?? fallbackSymbol()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    private static func fallbackSymbol() -> NSImage {
        NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "LazyMouse")
            ?? NSImage(size: NSSize(width: 18, height: 18))
    }
}
