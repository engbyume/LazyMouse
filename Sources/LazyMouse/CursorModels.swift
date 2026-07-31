import AppKit
import Foundation

struct MouseDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let vendorID: UInt32
    let productID: UInt32
}

struct CursorVisual: Identifiable {
    let id: String
    let label: String
    let colorIndex: Int
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
