import XCTest
@testable import FretOSCore

final class BindingsTests: XCTestCase {
    func testCloneHeroDefaultValues() {
        let b = Preset.cloneHeroDefault.bindings
        XCTAssertEqual(b[.green], 0); XCTAssertEqual(b[.red], 1); XCTAssertEqual(b[.yellow], 2)
        XCTAssertEqual(b[.blue], 3); XCTAssertEqual(b[.orange], 5)
        XCTAssertEqual(b[.strumUp], 126); XCTAssertEqual(b[.strumDown], 125)
        XCTAssertEqual(b[.start], 36); XCTAssertEqual(b[.back], 4); XCTAssertEqual(b[.tilt], 4)
        XCTAssertEqual(b[.whammy], 41)
        for extra in GuitarInput.extras { XCTAssertNil(b[extra]) }
        XCTAssertEqual(Preset.cloneHeroDefault.name, "Clone Hero Default")
    }

    func testKeyLabels() {
        XCTAssertEqual(KeyNames.label(0), "A")
        XCTAssertEqual(KeyNames.label(126), "↑")
        XCTAssertEqual(KeyNames.label(36), "⏎")
        XCTAssertEqual(KeyNames.label(41), ";")
        XCTAssertEqual(KeyNames.label(49), "SPACE")
        XCTAssertEqual(KeyNames.label(18), "1")
        XCTAssertEqual(KeyNames.label(122), "F1")
        XCTAssertEqual(KeyNames.label(999), "KEY 999")
    }

    func testCaptureRejectsModifiersAndEscCancels() {
        XCTAssertEqual(Bindings.capture(keyCode: 53, modifiersOnly: false), .cancel)
        XCTAssertEqual(Bindings.capture(keyCode: 56, modifiersOnly: true),
                       .rejected("Pick a regular key, not ⌘ ⇧ ⌥ ⌃"))
        XCTAssertEqual(Bindings.capture(keyCode: 6, modifiersOnly: false), .bind(6))
    }

    func testDuplicatesFindsTiltAndBackOnH() {
        let d = Bindings.duplicates(Preset.cloneHeroDefault.bindings)
        XCTAssertEqual(d.count, 1)
        XCTAssertEqual(Set(d[4] ?? []), [.back, .tilt])
    }

    func testSettingsRoundTripAndCorruptFallsBack() {
        let defaults = UserDefaults(suiteName: "fretos.test.\(UUID())")!
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings, Settings())
        var s = Settings(); s.bindings[.green] = 6; s.tuning.strumDebounceMs = 30; s.onboarded = true
        store.settings = s
        XCTAssertEqual(SettingsStore(defaults: defaults).settings, s)
        defaults.set(Data("garbage".utf8), forKey: SettingsStore.key)
        XCTAssertEqual(SettingsStore(defaults: defaults).settings, Settings())
    }

    func testOldSettingsMissingNewFieldsKeepUserChoices() {
        // settings saved by v1.0.0 have no tiltHoldMs — must not wipe bindings/onboarding
        let defaults = UserDefaults(suiteName: "fretos.test.\(UUID())")!
        let old = #"{"onboarded":true,"launchAtLogin":false,"onlyWhenCloneHeroFront":true,"bindings":["green",6],"tuning":{"tiltThreshold":15000,"whammyThreshold":10000,"releaseRatio":0.6,"strumDebounceMs":25,"otherDebounceMs":8}}"#
        defaults.set(Data(old.utf8), forKey: SettingsStore.key)
        let s = SettingsStore(defaults: defaults).settings
        XCTAssertTrue(s.onboarded)
        XCTAssertEqual(s.bindings[.green], 6)
        XCTAssertEqual(s.tuning.tiltThreshold, 15000)
        XCTAssertEqual(s.tuning.strumDebounceMs, 25)
        XCTAssertEqual(s.tuning.tiltHoldMs, 50)
        XCTAssertEqual(s.tuning.releaseRatio, 0.85)   // old 0.6 default migrated
    }

    func testPresetNameSwitchesToCustom() {
        var s = Settings()
        XCTAssertEqual(s.presetName, "Clone Hero Default")
        s.bindings[.green] = 6
        XCTAssertEqual(s.presetName, "Custom")
    }
}
