import Foundation

public struct Tuning: Codable, Equatable, Sendable {
    public var tiltThreshold = 12000
    public var whammyThreshold = 10000
    /// Tilt/whammy release once they drop below this fraction of the trigger point.
    public var releaseRatio = 0.85
    public var strumDebounceMs = 20
    public var otherDebounceMs = 8
    /// Tilt must stay past the trigger this long before star power fires (filters bumps).
    public var tiltHoldMs = 50
    /// Experimental: pulse the whammy key, held longer the further the bar is pushed.
    public var whammyPulse = false
    public init() {}

    // Tolerant decoding: settings saved by older versions keep every value they have.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Tuning()
        tiltThreshold = try c.decodeIfPresent(Int.self, forKey: .tiltThreshold) ?? d.tiltThreshold
        whammyThreshold = try c.decodeIfPresent(Int.self, forKey: .whammyThreshold) ?? d.whammyThreshold
        releaseRatio = try c.decodeIfPresent(Double.self, forKey: .releaseRatio) ?? d.releaseRatio
        if releaseRatio < d.releaseRatio { releaseRatio = d.releaseRatio }  // v1.0.0's 0.6 felt sticky
        strumDebounceMs = try c.decodeIfPresent(Int.self, forKey: .strumDebounceMs) ?? d.strumDebounceMs
        otherDebounceMs = try c.decodeIfPresent(Int.self, forKey: .otherDebounceMs) ?? d.otherDebounceMs
        tiltHoldMs = try c.decodeIfPresent(Int.self, forKey: .tiltHoldMs) ?? d.tiltHoldMs
        whammyPulse = try c.decodeIfPresent(Bool.self, forKey: .whammyPulse) ?? d.whammyPulse
    }
}

public struct KeyEvent: Equatable, Sendable {
    public let keyCode: UInt16
    public let down: Bool
    public init(keyCode: UInt16, down: Bool) { self.keyCode = keyCode; self.down = down }
}

/// Turns raw guitar reports into clean key events:
/// - whammy/tilt measured from a resting position captured on the first report
/// - hysteresis on whammy/tilt so hovering at the threshold doesn't flicker
/// - presses sent instantly, releases only after the input stays released for the debounce time
/// - within one report, fret keys are sent before strum keys
/// - several inputs may share a key; the key is held while any of them is
public final class InputProcessor {
    public var tuning: Tuning
    public var bindings: [GuitarInput: UInt16]
    public private(set) var active: Set<GuitarInput> = []
    public private(set) var rest: (whammy: Int16, tilt: Int16)?
    public private(set) var lastReport = RawGuitarReport()

    private var held: Set<UInt16> = []
    private var releasedAt: [UInt16: TimeInterval] = [:]

    public init(tuning: Tuning, bindings: [GuitarInput: UInt16]) {
        self.tuning = tuning
        self.bindings = bindings
    }

    /// True while something is waiting on a timer (a debounced release or a tilt hold),
    /// so the USB loop should tick quickly.
    public var hasPendingRelease: Bool {
        !releasedAt.isEmpty || (tiltOverSince != nil && !active.contains(.tilt)) || isPulsing
    }

    // Whammy depth mode: 0…1 past a small dead zone; pulses on a fixed period.
    private var whammyDepth = 0.0
    private var pulseStart: TimeInterval?
    private static let pulsePeriod = 0.1
    private static let pulseDeadZone = 3000.0
    private var isPulsing: Bool { tuning.whammyPulse && whammyDepth > 0 && whammyDepth < 0.95 }

    private var tiltRaw = false
    private var tiltOverSince: TimeInterval?

    /// Next report re-captures the resting whammy/tilt position.
    public func recalibrate() { rest = nil; tiltRaw = false; tiltOverSince = nil; whammyDepth = 0; pulseStart = nil }

    /// Release every held key now (disconnect, focus lost, disabled).
    public func releaseAll() -> [KeyEvent] {
        let events = held.sorted().map { KeyEvent(keyCode: $0, down: false) }
        held.removeAll(); releasedAt.removeAll(); active.removeAll()
        tiltRaw = false; tiltOverSince = nil; whammyDepth = 0; pulseStart = nil
        return events
    }

    /// Release held keys but keep `active` (what the guitar is doing), so anything still
    /// held is pressed fresh on the next `process` call.
    public func releaseHeld() -> [KeyEvent] {
        let events = held.sorted().map { KeyEvent(keyCode: $0, down: false) }
        held.removeAll(); releasedAt.removeAll()
        return events
    }

    /// Feed a new report, or nil for a timer tick (flushes debounced releases).
    public func process(_ report: RawGuitarReport?, now: TimeInterval) -> [KeyEvent] {
        if let report { update(with: report, now: now) }
        updateTilt(now: now)
        updateWhammyPulse(now: now)
        var events: [KeyEvent] = []

        // Keys no input is bound to anymore (rebinding) are released immediately.
        let boundKeys = Set(bindings.values)
        for key in held.subtracting(boundKeys).sorted() {
            held.remove(key); releasedAt[key] = nil
            events.append(KeyEvent(keyCode: key, down: false))
        }

        for key in orderedKeys() {
            let wanted = bindings.contains { active.contains($0.key) && $0.value == key }
            if wanted {
                releasedAt[key] = nil
                if !held.contains(key) { held.insert(key); events.append(KeyEvent(keyCode: key, down: true)) }
            } else if held.contains(key) {
                let since = releasedAt[key] ?? now
                releasedAt[key] = since
                if now - since >= debounce(for: key) - 1e-9 {
                    held.remove(key); releasedAt[key] = nil
                    events.append(KeyEvent(keyCode: key, down: false))
                }
            }
        }
        return events
    }

    private func update(with report: RawGuitarReport, now: TimeInterval) {
        lastReport = report
        if rest == nil { rest = (report.whammy, report.tilt) }
        let base = rest!
        let tiltWasActive = active.contains(.tilt)
        var next = report.buttons
        let whammyDelta = Int(report.whammy) - Int(base.whammy)
        if tuning.whammyPulse {
            whammyDepth = min(1, max(0, (Double(abs(whammyDelta)) - Self.pulseDeadZone) / (32767 - Self.pulseDeadZone)))
            if active.contains(.whammy) { next.insert(.whammy) }   // updateWhammyPulse decides
        } else if analog(.whammy, whammyDelta, tuning.whammyThreshold) {
            next.insert(.whammy)
        }
        tiltRaw = analog(.tilt, Int(report.tilt) - Int(base.tilt), tuning.tiltThreshold)
        if tiltRaw { if tiltOverSince == nil { tiltOverSince = now } } else { tiltOverSince = nil }
        if tiltWasActive && tiltRaw { next.insert(.tilt) }
        active = next
    }

    private func updateWhammyPulse(now: TimeInterval) {
        guard tuning.whammyPulse else { return }
        if whammyDepth <= 0 { pulseStart = nil; active.remove(.whammy); return }
        if whammyDepth >= 0.95 { active.insert(.whammy); return }
        let start = pulseStart ?? now
        pulseStart = start
        let phase = (now - start).truncatingRemainder(dividingBy: Self.pulsePeriod)
        if phase < whammyDepth * Self.pulsePeriod { active.insert(.whammy) } else { active.remove(.whammy) }
    }

    /// Star power only once tilt has stayed past the trigger for `tiltHoldMs`.
    private func updateTilt(now: TimeInterval) {
        guard tiltRaw, let since = tiltOverSince else { active.remove(.tilt); return }
        if now - since >= Double(tuning.tiltHoldMs) / 1000 - 1e-9 { active.insert(.tilt) }
    }

    private func analog(_ input: GuitarInput, _ delta: Int, _ threshold: Int) -> Bool {
        let limit = active.contains(input) ? Double(threshold) * tuning.releaseRatio : Double(threshold)
        return Double(abs(delta)) > limit
    }

    private func isStrumKey(_ key: UInt16) -> Bool {
        bindings.contains { $0.key.isStrum && $0.value == key }
    }

    private func debounce(for key: UInt16) -> TimeInterval {
        Double(isStrumKey(key) ? tuning.strumDebounceMs : tuning.otherDebounceMs) / 1000
    }

    /// Non-strum keys first (in GuitarInput order), strum keys last.
    private func orderedKeys() -> [UInt16] {
        var seen = Set<UInt16>(), keys: [UInt16] = []
        for input in GuitarInput.allCases {
            if let k = bindings[input], seen.insert(k).inserted { keys.append(k) }
        }
        return keys.filter { !isStrumKey($0) } + keys.filter(isStrumKey)
    }
}
