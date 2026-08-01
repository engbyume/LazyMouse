import AppKit
import XCTest
@testable import LazyMouse

final class CursorColorTests: XCTestCase {
    func testNSColorRoundTripsThroughSRGB() {
        let original = NSColor(srgbRed: 0.18, green: 0.47, blue: 0.83, alpha: 1)
        let color = CursorColor(nsColor: original)

        XCTAssertEqual(color.red, 0.18, accuracy: 0.0001)
        XCTAssertEqual(color.green, 0.47, accuracy: 0.0001)
        XCTAssertEqual(color.blue, 0.83, accuracy: 0.0001)
        XCTAssertEqual(color.alpha, 1, accuracy: 0.0001)
        XCTAssertEqual(color.nsColor.colorSpace, NSColorSpace.sRGB)
    }

    func testHexRoundTripPreservesRoundedChannels() {
        let color = CursorColor(red: 0.5 / 255, green: 128 / 255, blue: 200.5 / 255)

        XCTAssertEqual(color.hex, "0180C9")
        XCTAssertEqual(CursorColor(hex: color.hex)?.hex, color.hex)
    }
}
