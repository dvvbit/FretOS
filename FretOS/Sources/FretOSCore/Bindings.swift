import Foundation

public struct Preset: Sendable {
    public let name: String
    public let bindings: [GuitarInput: UInt16]

    /// Clone Hero's default keyboard layout. Back (the X-plorer's star power button) and tilt share H.
    public static let cloneHeroDefault = Preset(name: "Clone Hero Default", bindings: [
        .green: 0, .red: 1, .yellow: 2, .blue: 3, .orange: 5,   // A S D F G
        .strumUp: 126, .strumDown: 125,                          // ↑ ↓
        .start: 36,                                              // Return
        .back: 4, .tilt: 4,                                      // H (Select / Star Power)
        .whammy: 41,                                             // ; (Keyboard Whammy)
    ])
}

public enum CaptureResult: Equatable, Sendable {
    case bind(UInt16), cancel, rejected(String)
}

public enum Bindings {
    /// What happens when the user presses a key while a keycap is waiting for one.
    public static func capture(keyCode: UInt16, modifiersOnly: Bool) -> CaptureResult {
        if modifiersOnly { return .rejected("Pick a regular key, not ⌘ ⇧ ⌥ ⌃") }
        if keyCode == 53 { return .cancel }   // Esc
        return .bind(keyCode)
    }

    /// Keys bound to two or more inputs.
    public static func duplicates(_ b: [GuitarInput: UInt16]) -> [UInt16: [GuitarInput]] {
        var byKey: [UInt16: [GuitarInput]] = [:]
        for input in GuitarInput.allCases { if let k = b[input] { byKey[k, default: []].append(input) } }
        return byKey.filter { $0.value.count > 1 }
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var bindings: [GuitarInput: UInt16] = Preset.cloneHeroDefault.bindings
    public var tuning = Tuning()
    public var onlyWhenCloneHeroFront = true
    public var launchAtLogin = false
    public var onboarded = false
    public init() {}

    // Tolerant decoding: a missing or unreadable field falls back to its default instead
    // of wiping every setting (and re-running setup) after an update.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        bindings = (try? c.decodeIfPresent([GuitarInput: UInt16].self, forKey: .bindings)) ?? nil ?? d.bindings
        tuning = (try? c.decodeIfPresent(Tuning.self, forKey: .tuning)) ?? nil ?? d.tuning
        onlyWhenCloneHeroFront = (try? c.decodeIfPresent(Bool.self, forKey: .onlyWhenCloneHeroFront)) ?? nil ?? d.onlyWhenCloneHeroFront
        launchAtLogin = (try? c.decodeIfPresent(Bool.self, forKey: .launchAtLogin)) ?? nil ?? d.launchAtLogin
        onboarded = (try? c.decodeIfPresent(Bool.self, forKey: .onboarded)) ?? nil ?? d.onboarded
    }

    public var presetName: String {
        bindings == Preset.cloneHeroDefault.bindings ? Preset.cloneHeroDefault.name : "Custom"
    }
}

public final class SettingsStore {
    public static let key = "fretos.settings.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var settings: Settings {
        get {
            guard let data = defaults.data(forKey: Self.key),
                  let s = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
            return s
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.key) }
    }
}
