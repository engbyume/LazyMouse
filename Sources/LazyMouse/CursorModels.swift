import AppKit
import Foundation

struct CursorColor: Hashable, Identifiable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
        self.alpha = min(max(alpha, 0), 1)
    }

    init?(hex: String) {
        let normalized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard normalized.count == 6, let value = UInt32(normalized, radix: 16) else { return nil }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255
        )
    }

    init(nsColor: NSColor) {
        let color = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.init(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent, alpha: color.alphaComponent)
    }

    var id: String { hex }

    var hex: String {
        String(format: "%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }

    var nsColor: NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }

    static let red = CursorColor(red: 0.95, green: 0.08, blue: 0.12)
}

struct MouseDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let manufacturer: String?
    let transport: String?
    let vendorID: UInt32
    let productID: UInt32
}

struct CursorVisual: Identifiable {
    let id: String
    let color: CursorColor
    let scale: CGFloat
    let position: CGPoint
}

struct DisplayChoice: Identifiable, Hashable {
    let id: UInt32
    let name: String
    let frame: CGRect

    static func == (lhs: DisplayChoice, rhs: DisplayChoice) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.frame.origin == rhs.frame.origin && lhs.frame.size == rhs.frame.size
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(frame.origin.x)
        hasher.combine(frame.origin.y)
        hasher.combine(frame.size.width)
        hasher.combine(frame.size.height)
    }
}
