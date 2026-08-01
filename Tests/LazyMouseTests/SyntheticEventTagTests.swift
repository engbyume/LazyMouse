import CoreGraphics
import XCTest
@testable import LazyMouse

final class SyntheticEventTagTests: XCTestCase {
    func testSyntheticEventsCanBeRecognizedByTheTrackpadTap() throws {
        let event = try XCTUnwrap(CGEvent(source: nil))

        XCTAssertFalse(SyntheticEventTag.contains(event))
        SyntheticEventTag.mark(event)
        XCTAssertTrue(SyntheticEventTag.contains(event))
    }
}
