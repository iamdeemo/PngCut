import Foundation

enum GIFFrameRate: Equatable, Sendable {
    case preset(Int)
    case custom(Int)

    static let presetValues = [20, 25, 30]

    var value: Int {
        switch self {
        case let .preset(value), let .custom(value):
            value
        }
    }

    static func custom(validating value: Int) -> GIFFrameRate? {
        guard (1...50).contains(value) else {
            return nil
        }
        return .custom(value)
    }
}

enum GIFLoop: String, Equatable, Sendable {
    case forever
    case once

    var gifskiRepeatArgument: Int {
        switch self {
        case .forever: 0
        case .once: -1
        }
    }
}

struct GIFSettings: Equatable, Sendable {
    var isPNGSequenceConversionEnabled: Bool
    var frameRate: GIFFrameRate
    var loop: GIFLoop

    init(
        isPNGSequenceConversionEnabled: Bool = false,
        frameRate: GIFFrameRate = .preset(30),
        loop: GIFLoop = .forever
    ) {
        self.isPNGSequenceConversionEnabled = isPNGSequenceConversionEnabled
        self.frameRate = frameRate
        self.loop = loop
    }
}
