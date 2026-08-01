import CoreGraphics

enum ScrollUnit: Equatable {
    case line
    case pixel
}

struct ScrollInput: Equatable {
    let x: CGFloat
    let y: CGFloat
    let unit: ScrollUnit

    var isZero: Bool {
        x == 0 && y == 0
    }

    static func from(event: CGEvent) -> ScrollInput {
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        if !isContinuous {
            let lineX = CGFloat(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
            let lineY = CGFloat(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            if lineX != 0 || lineY != 0 {
                return ScrollInput(x: lineX, y: lineY, unit: .line)
            }
        }

        let pointX = CGFloat(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
        let pointY = CGFloat(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        if pointX != 0 || pointY != 0 {
            return ScrollInput(x: pointX, y: pointY, unit: .pixel)
        }

        let fixedX = CGFloat(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2))
        let fixedY = CGFloat(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))
        if fixedX != 0 || fixedY != 0 {
            return ScrollInput(x: fixedX, y: fixedY, unit: .pixel)
        }

        return ScrollInput(
            x: CGFloat(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
            y: CGFloat(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
            unit: .line
        )
    }
}
