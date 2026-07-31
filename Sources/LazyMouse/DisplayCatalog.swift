import AppKit
import LazyMouseCore

@MainActor
final class DisplayCatalog: ObservableObject {
    @Published private(set) var displays: [DisplayChoice] = []

    init() {
        refresh()
    }

    func refresh() {
        displays = NSScreen.screens.enumerated().map { index, screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? UInt32(index)
            let name = screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName
            return DisplayChoice(id: id, name: name, frame: screen.frame)
        }
    }

    func coreDisplays() -> [DesktopDisplay] {
        displays.map { DesktopDisplay(id: $0.id, name: $0.name, bounds: $0.frame) }
    }

    func frame(for id: UInt32) -> CGRect? {
        displays.first(where: { $0.id == id })?.frame
    }
}
