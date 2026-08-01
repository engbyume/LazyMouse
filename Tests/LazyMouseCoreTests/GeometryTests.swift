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

    func testTwoFreeCursorsCanShareOneDisplay() {
        let first = CursorGeometry.move(
            point: CGPoint(x: 400, y: 300),
            delta: CGPoint(x: 40, y: 20),
            boundary: .free,
            displays: [display]
        )
        let second = CursorGeometry.move(
            point: CGPoint(x: 400, y: 300),
            delta: CGPoint(x: -40, y: -20),
            boundary: .free,
            displays: [display]
        )
        XCTAssertEqual(first, CGPoint(x: 440, y: 320))
        XCTAssertEqual(second, CGPoint(x: 360, y: 280))
        XCTAssertNotEqual(first, second)
    }

    func testQuartzPointFlipsAppKitYCoordinate() {
        let result = MouseEventGeometry.quartzPoint(
            from: CGPoint(x: 120, y: 100),
            appKitPrimaryFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            quartzPrimaryBounds: CGRect(x: 0, y: 0, width: 1512, height: 982)
        )
        XCTAssertEqual(result, CGPoint(x: 120, y: 882))
    }

    func testQuartzPointPreservesDisplayOffsets() {
        let result = MouseEventGeometry.quartzPoint(
            from: CGPoint(x: -40, y: 1100),
            appKitPrimaryFrame: CGRect(x: 10, y: 20, width: 1512, height: 982),
            quartzPrimaryBounds: CGRect(x: 5, y: 0, width: 1512, height: 982)
        )
        XCTAssertEqual(result, CGPoint(x: -45, y: -98))
    }
}
