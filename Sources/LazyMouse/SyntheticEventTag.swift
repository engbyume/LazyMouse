import CoreGraphics

enum SyntheticEventTag {
    static let value: Int64 = 0x4C617A794D6F7573

    static func mark(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: value)
    }

    static func contains(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == value
    }
}
