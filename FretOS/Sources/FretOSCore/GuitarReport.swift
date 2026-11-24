/// Every input FretOS understands. Declaration order is display order.
public enum GuitarInput: String, CaseIterable, Codable, Sendable {
    case green, red, yellow, blue, orange
    case strumUp, strumDown, start, back, tilt, whammy
    case guide, dpadLeft, dpadRight, rb, leftStickClick, rightStickClick

    /// Buttons not every guitar has; unbound by default.
    public static let extras: [GuitarInput] = [.guide, .dpadLeft, .dpadRight, .rb, .leftStickClick, .rightStickClick]

    public var isStrum: Bool { self == .strumUp || self == .strumDown }
}

/// USB devices FretOS talks to: the X-plorer by ID, plus any wired Xbox 360 device
/// that tags itself as a guitar in its XInput descriptor. Only the X-plorer is tested.
public enum SupportedDevices {
    public static let ids: [(vendor: UInt16, product: UInt16)] = [(0x1430, 0x4748)]

    /// XInput subtypes: 0x06 guitar (alternate), 0x07 guitar, 0x0B guitar bass.
    static let guitarSubtypes: Set<UInt8> = [0x06, 0x07, 0x0B]

    /// True for a wired XInput interface (class 0xFF, subclass 0x5D, protocol 0x01) whose
    /// 0x21 class descriptor reports a guitar subtype (byte 4).
    public static func isXInputGuitar(interfaceClass: UInt8, subClass: UInt8, protocol proto: UInt8, extra: [UInt8]) -> Bool {
        guard interfaceClass == 0xFF, subClass == 0x5D, proto == 0x01 else { return false }
        var i = 0
        while i + 1 < extra.count {
            let len = Int(extra[i])
            guard len >= 2, i + len <= extra.count else { return false }
            if extra[i + 1] == 0x21, len >= 5 { return guitarSubtypes.contains(extra[i + 4]) }
            i += len
        }
        return false
    }
}

/// One decoded Xbox 360 wired input report.
public struct RawGuitarReport: Equatable, Sendable {
    /// Digital buttons held. Never contains `.tilt` or `.whammy`.
    public var buttons: Set<GuitarInput>
    public var whammy: Int16
    public var tilt: Int16

    public init(buttons: Set<GuitarInput> = [], whammy: Int16 = 0, tilt: Int16 = 0) {
        self.buttons = buttons; self.whammy = whammy; self.tilt = tilt
    }

    private static let byte2: [(UInt8, GuitarInput)] = [
        (0x01, .strumUp), (0x02, .strumDown), (0x04, .dpadLeft), (0x08, .dpadRight),
        (0x10, .start), (0x20, .back), (0x40, .leftStickClick), (0x80, .rightStickClick),
    ]
    private static let byte3: [(UInt8, GuitarInput)] = [
        (0x01, .orange), (0x02, .rb), (0x04, .guide),
        (0x10, .green), (0x20, .red), (0x40, .blue), (0x80, .yellow),
    ]

    /// Returns nil for anything that isn't a 360 input report (LED/status messages, short reads).
    public static func parse(_ bytes: [UInt8]) -> RawGuitarReport? {
        guard bytes.count >= 14, bytes[0] == 0x00 else { return nil }
        var buttons = Set<GuitarInput>()
        for (bit, input) in byte2 where bytes[2] & bit != 0 { buttons.insert(input) }
        for (bit, input) in byte3 where bytes[3] & bit != 0 { buttons.insert(input) }
        func int16(_ i: Int) -> Int16 { Int16(bitPattern: UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8) }
        return RawGuitarReport(buttons: buttons, whammy: int16(10), tilt: int16(12))
    }
}
