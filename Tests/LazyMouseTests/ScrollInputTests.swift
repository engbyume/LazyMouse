import CoreGraphics
import XCTest
@testable import LazyMouse

final class ScrollInputTests: XCTestCase {
    func testContinuousTrackpadScrollPreservesBothPixelAxes() throws {
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: -12,
            wheel2: 7,
            wheel3: 0
        ))

        XCTAssertEqual(
            ScrollInput.from(event: event),
            ScrollInput(x: 7, y: -12, unit: .pixel)
        )
    }

    func testMouseWheelScrollFallsBackToLineUnits() throws {
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 3,
            wheel2: -1,
            wheel3: 0
        ))

        XCTAssertEqual(
            ScrollInput.from(event: event),
            ScrollInput(x: -1, y: 3, unit: .line)
        )
    }
}
