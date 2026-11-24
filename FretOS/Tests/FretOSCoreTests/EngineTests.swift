import XCTest
@testable import FretOSCore

final class RecordingSink: KeySink {
    var events: [KeyEvent] = []
    func post(_ e: KeyEvent) { events.append(e) }
}

final class EngineTests: XCTestCase {
    var sink: RecordingSink!
    var core: EngineCore!
    override func setUp() {
        sink = RecordingSink()
        core = EngineCore(processor: InputProcessor(tuning: Tuning(), bindings: Preset.cloneHeroDefault.bindings), sink: sink)
        core.permission = true; core.gateOpen = true; core.enabled = true
        core.setConnected(true)
        core.handle(RawGuitarReport(), now: 0)
    }
    let A = KeyEvent(keyCode: 0, down: true), Aup = KeyEvent(keyCode: 0, down: false)

    func testNoPermissionBlocksOutput() {
        core.permission = false
        core.handle(RawGuitarReport(buttons: [.green]), now: 1)
        XCTAssertEqual(sink.events, [])
        XCTAssertEqual(core.status, .needsPermission)
        XCTAssertTrue(core.processor.active.contains(.green))   // live view still works
        core.permission = true
        core.handle(RawGuitarReport(buttons: [.green]), now: 2)
        XCTAssertEqual(sink.events, [A])
    }

    func testGateClosingReleasesHeldKeys() {
        core.handle(RawGuitarReport(buttons: [.green]), now: 1)
        core.gateOpen = false
        XCTAssertEqual(sink.events, [A, Aup])
        core.handle(RawGuitarReport(buttons: [.green, .red]), now: 2)
        XCTAssertEqual(sink.events, [A, Aup])
        core.gateOpen = true
        core.handle(RawGuitarReport(buttons: [.green]), now: 3)
        XCTAssertEqual(sink.events.last, A)
    }

    func testDisconnectReleasesHeldKeys() {
        core.handle(RawGuitarReport(buttons: [.green]), now: 1)
        core.setConnected(false)
        XCTAssertEqual(sink.events, [A, Aup])
        XCTAssertEqual(core.status, .noGuitar)
    }

    func testDisablingReleasesHeldKeys() {
        core.handle(RawGuitarReport(buttons: [.green]), now: 1)
        core.enabled = false
        XCTAssertEqual(sink.events, [A, Aup])
    }

    func testReconnectRecalibrates() {
        core.setConnected(false); core.setConnected(true)
        XCTAssertNil(core.processor.rest)
    }

    func testStatusPrecedence() {
        func status(connected: Bool, permission: Bool, enabled: Bool, gate: Bool, cloneHeroRunning: Bool) -> EngineStatus {
            core.setConnected(connected); core.permission = permission; core.enabled = enabled
            core.gateOpen = gate; core.cloneHeroRunning = cloneHeroRunning
            return core.status
        }
        XCTAssertEqual(status(connected: false, permission: false, enabled: true, gate: true, cloneHeroRunning: true), .noGuitar)
        XCTAssertEqual(status(connected: true, permission: false, enabled: true, gate: true, cloneHeroRunning: true), .needsPermission)
        XCTAssertEqual(status(connected: true, permission: true, enabled: true, gate: true, cloneHeroRunning: true), .playing)
        XCTAssertEqual(status(connected: true, permission: true, enabled: true, gate: false, cloneHeroRunning: true), .paused)
        XCTAssertEqual(status(connected: true, permission: true, enabled: true, gate: false, cloneHeroRunning: false), .ready)
        XCTAssertEqual(status(connected: true, permission: true, enabled: false, gate: true, cloneHeroRunning: true), .off)
    }

    func testStatusText() {
        XCTAssertEqual(EngineStatus.noGuitar.text, "PLUG IN YOUR GUITAR")
        XCTAssertEqual(EngineStatus.needsPermission.text, "ALLOW KEYSTROKES →")
        XCTAssertEqual(EngineStatus.ready.text, "READY — OPEN CLONE HERO")
        XCTAssertEqual(EngineStatus.playing.text, "PLAYING")
        XCTAssertEqual(EngineStatus.paused.text, "PAUSED (Clone Hero not in front)")
        XCTAssertEqual(EngineStatus.off.text, "OFF")
    }
}
