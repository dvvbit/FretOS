import XCTest
@testable import FretOSCore

// Clone Hero default key codes
let A: UInt16 = 0, H: UInt16 = 4, Z: UInt16 = 6, SEMI: UInt16 = 41, DOWN: UInt16 = 125

final class InputProcessorTests: XCTestCase {
    var p: InputProcessor!
    override func setUp() {
        p = InputProcessor(tuning: Tuning(), bindings: [
            .green: A, .strumDown: DOWN, .back: H, .tilt: H, .whammy: SEMI,
        ])
        _ = p.process(RawGuitarReport(), now: 0)  // calibrate at rest
    }
    func r(_ b: Set<GuitarInput> = [], whammy: Int16 = 0, tilt: Int16 = 0) -> RawGuitarReport {
        RawGuitarReport(buttons: b, whammy: whammy, tilt: tilt)
    }
    func down(_ k: UInt16) -> KeyEvent { KeyEvent(keyCode: k, down: true) }
    func up(_ k: UInt16) -> KeyEvent { KeyEvent(keyCode: k, down: false) }

    func testFretBeforeStrumInSameReport() {
        XCTAssertEqual(p.process(r([.strumDown, .green]), now: 1), [down(A), down(DOWN)])
    }

    func testStrumBounceIsOneStrum() {
        var events: [KeyEvent] = []
        events += p.process(r([.strumDown]), now: 1.000)
        events += p.process(r(), now: 1.003)
        events += p.process(r([.strumDown]), now: 1.006)
        events += p.process(r(), now: 1.060)
        events += p.process(nil, now: 1.085)
        XCTAssertEqual(events, [down(DOWN), up(DOWN)])
    }

    func testReleaseWaitsForDebounce() {
        _ = p.process(r([.green]), now: 0.9)
        XCTAssertEqual(p.process(r(), now: 1.0), [])
        XCTAssertTrue(p.hasPendingRelease)
        XCTAssertEqual(p.process(nil, now: 1.005), [])
        XCTAssertEqual(p.process(nil, now: 1.009), [up(A)])
        XCTAssertFalse(p.hasPendingRelease)
    }

    func testTiltHysteresis() {
        // hold time 50 ms before star power; release below 85% of the trigger (10200)
        XCTAssertEqual(p.process(r(tilt: 13000), now: 1.00), [])
        XCTAssertEqual(p.process(nil, now: 1.05), [down(H)])
        XCTAssertEqual(p.process(r(tilt: 11000), now: 1.06), [])     // above 10200: stays on
        XCTAssertEqual(p.process(r(tilt: 13000), now: 1.07), [])
        XCTAssertEqual(p.process(r(tilt: 9000), now: 1.08), [])      // below 10200: releasing
        XCTAssertEqual(p.process(nil, now: 1.09), [up(H)])
    }

    func testTiltBumpShorterThanHoldIsIgnored() {
        XCTAssertEqual(p.process(r(tilt: 20000), now: 1.00), [])
        XCTAssertEqual(p.process(r(tilt: 0), now: 1.03), [])
        XCTAssertEqual(p.process(nil, now: 1.10), [])
        XCTAssertFalse(p.active.contains(.tilt))
    }

    func testPendingTiltRequestsFastPolling() {
        _ = p.process(r(tilt: 20000), now: 1.0)
        XCTAssertTrue(p.hasPendingRelease)   // a pending tilt press also needs fast ticks
    }

    // Experimental whammy depth: the whammy key is pulsed, held longer the further you push.
    func pulseProcessor() -> InputProcessor {
        var t = Tuning(); t.whammyPulse = true
        let q = InputProcessor(tuning: t, bindings: [.whammy: SEMI])
        _ = q.process(r(), now: 0)
        return q
    }

    func countDowns(_ q: InputProcessor, whammy: Int16, from: Double, seconds: Double) -> (downs: Int, heldTicks: Int, ticks: Int) {
        var held = 0, ticks = 0
        var downs = q.process(r(whammy: whammy), now: from).filter(\.down).count
        var t = from
        while t < from + seconds {
            t += 0.002
            let ev = q.process(nil, now: t)
            downs += ev.filter(\.down).count
            ticks += 1
            if q.active.contains(.whammy) { held += 1 }
        }
        return (downs, held, ticks)
    }

    func testWhammyPulseOffByDefault() {
        XCTAssertFalse(Tuning().whammyPulse)
    }

    func testWhammyPulseRestSendsNothing() {
        let q = pulseProcessor()
        XCTAssertEqual(countDowns(q, whammy: 1000, from: 1, seconds: 0.5).downs, 0)
    }

    func testWhammyPulseHalfDepthTapsRepeatedly() {
        let q = pulseProcessor()
        let res = countDowns(q, whammy: 17000, from: 1, seconds: 0.6)   // ~half way
        XCTAssertGreaterThanOrEqual(res.downs, 4)
        let duty = Double(res.heldTicks) / Double(res.ticks)
        XCTAssertGreaterThan(duty, 0.3); XCTAssertLessThan(duty, 0.7)
        XCTAssertTrue(q.hasPendingRelease)   // keeps the USB loop ticking while pulsing
    }

    func testWhammyPulseFullDepthHolds() {
        let q = pulseProcessor()
        let res = countDowns(q, whammy: 32767, from: 1, seconds: 0.5)
        XCTAssertEqual(res.downs, 1)
    }

    func testSharedKeyHeldWhileEitherActive() {
        XCTAssertEqual(p.process(r(tilt: 20000), now: 0.9), [])
        XCTAssertEqual(p.process(r(tilt: 20000), now: 1.0), [down(H)])
        XCTAssertEqual(p.process(r([.back], tilt: 20000), now: 1.1), [])
        XCTAssertEqual(p.process(r([.back]), now: 1.2), [])
        XCTAssertEqual(p.process(nil, now: 1.3), [])
        XCTAssertEqual(p.process(r(), now: 1.4), [])
        XCTAssertEqual(p.process(nil, now: 1.5), [up(H)])
    }

    func testCalibratesFromFirstReport() {
        let q = InputProcessor(tuning: Tuning(), bindings: [.whammy: SEMI])
        XCTAssertEqual(q.process(r(whammy: -32768), now: 0), [])
        XCTAssertEqual(q.process(r(whammy: -20000), now: 1), [down(SEMI)])
    }

    func testRecalibrateResetsRest() {
        let q = InputProcessor(tuning: Tuning(), bindings: [.tilt: H])
        XCTAssertEqual(q.process(r(tilt: 20000), now: 0), [])   // plugged in tilted: rest = tilted
        // user levels the guitar and hits Recalibrate before it registers as a tilt
        q.recalibrate()
        XCTAssertEqual(q.process(r(tilt: 0), now: 1), [])       // new rest = level
        XCTAssertEqual(q.process(r(tilt: 0), now: 2), [])
        XCTAssertEqual(q.process(r(tilt: 20000), now: 3), [])
        XCTAssertEqual(q.process(nil, now: 3.1), [down(H)])  // real tilt works again
    }

    func testReleaseAllReturnsUpForEveryHeldKey() {
        _ = p.process(r([.green, .strumDown]), now: 1)
        XCTAssertEqual(Set(p.releaseAll().map(\.keyCode)), [A, DOWN])
        XCTAssertTrue(p.releaseAll().isEmpty)
        XCTAssertTrue(p.active.isEmpty)
    }

    func testRebindReleasesOldKey() {
        _ = p.process(r([.green]), now: 1)
        p.bindings[.green] = Z
        XCTAssertEqual(p.process(r([.green]), now: 1.01), [up(A), down(Z)])
    }

    func testUnboundInputSendsNothing() {
        XCTAssertEqual(p.process(r([.guide]), now: 1), [])
        XCTAssertTrue(p.active.contains(.guide))
    }
}
