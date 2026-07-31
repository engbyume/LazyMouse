import XCTest
@testable import LazyMouseCore

final class GeometryTests: XCTestCase {
    private let display = DesktopDisplay(
        id: 42,
        name: "External",
        bounds: CGRect(x: 100, y: 50, width: 800, height: 600)
    )

    func testFreeCursorCanLeaveDisplayBounds() {
        let result = CursorGeometry.move(
            point: CGPoint(x: 120, y: 100),
            delta: CGPoint(x: -500, y: 900),
            boundary: .free,
            displays: [display]
        )
        XCTAssertEqual(result, CGPoint(x: -380, y: 1000))
    }

    func testLockedCursorClampsToSelectedDisplay() {
        let result = CursorGeometry.move(
            point: CGPoint(x: 120, y: 100),
            delta: CGPoint(x: -500, y: 900),
            boundary: .display(42),
            displays: [display]
        )
        XCTAssertEqual(result, CGPoint(x: 100, y: 650))
    }

    func testUnknownDisplayKeepsCursorStationary() {
        let result = CursorGeometry.move(
            point: CGPoint(x: 120, y: 100),
            delta: CGPoint(x: 5, y: -7),
            boundary: .display(999),
            displays: [display]
        )
        XCTAssertEqual(result, CGPoint(x: 120, y: 100))
    }
}
