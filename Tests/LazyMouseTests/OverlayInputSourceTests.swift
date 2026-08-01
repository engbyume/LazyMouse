import XCTest
@testable import LazyMouse

final class OverlayInputSourceTests: XCTestCase {
    func testExternalMouseSwapsToBuiltInTrackpad() {
        XCTAssertEqual(OverlayInputSource.externalMouse.other, .builtInTrackpad)
    }

    func testBuiltInTrackpadSwapsToExternalMouse() {
        XCTAssertEqual(OverlayInputSource.builtInTrackpad.other, .externalMouse)
    }

    func testRawValuesRoundTripForPersistence() {
        for source in OverlayInputSource.allCases {
            XCTAssertEqual(OverlayInputSource(rawValue: source.rawValue), source)
        }
    }
}
