import Foundation

public struct DesktopDisplay: Equatable, Sendable {
    public let id: UInt32
    public let name: String
    public let bounds: CGRect

    public init(id: UInt32, name: String, bounds: CGRect) {
        self.id = id
        self.name = name
        self.bounds = bounds
    }

    public static func == (lhs: DesktopDisplay, rhs: DesktopDisplay) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name &&
            lhs.bounds.origin.x == rhs.bounds.origin.x &&
            lhs.bounds.origin.y == rhs.bounds.origin.y &&
            lhs.bounds.size.width == rhs.bounds.size.width &&
            lhs.bounds.size.height == rhs.bounds.size.height
    }
}

public enum CursorBoundary: Equatable, Hashable, Sendable {
    case free
    case display(UInt32)
}

public enum CursorGeometry {
    public static func move(point: CGPoint, delta: CGPoint, boundary: CursorBoundary, displays: [DesktopDisplay]) -> CGPoint {
        let proposed = CGPoint(x: point.x + delta.x, y: point.y + delta.y)
        guard case let .display(displayID) = boundary else {
            return proposed
        }
        guard let display = displays.first(where: { $0.id == displayID }) else {
            return point
        }
        return clamp(proposed, to: display.bounds)
    }

    public static func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.origin.x), bounds.origin.x + bounds.size.width),
            y: min(max(point.y, bounds.origin.y), bounds.origin.y + bounds.size.height)
        )
    }
}
