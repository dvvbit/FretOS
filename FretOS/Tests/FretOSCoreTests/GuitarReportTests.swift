import XCTest
@testable import FretOSCore

func report(b2: UInt8 = 0, b3: UInt8 = 0, whammy: Int16 = 0, tilt: Int16 = 0) -> [UInt8] {
    var r = [UInt8](repeating: 0, count: 20)
    r[1] = 0x14; r[2] = b2; r[3] = b3
    let w = UInt16(bitPattern: whammy), t = UInt16(bitPattern: tilt)
    r[10] = UInt8(w & 0xFF); r[11] = UInt8(w >> 8)
    r[12] = UInt8(t & 0xFF); r[13] = UInt8(t >> 8)
    return r
}

final class GuitarReportTests: XCTestCase {
    func testParsesFretsAndStrum() {
        let r = RawGuitarReport.parse(report(b2: 0x02, b3: 0x10 | 0x01))
        XCTAssertEqual(r?.buttons, [.strumDown, .green, .orange])
    }

    func testParsesAllBits() {
        let b2: [(UInt8, GuitarInput)] = [(0x01, .strumUp), (0x02, .strumDown), (0x04, .dpadLeft), (0x08, .dpadRight),
                                          (0x10, .start), (0x20, .back), (0x40, .leftStickClick), (0x80, .rightStickClick)]
        let b3: [(UInt8, GuitarInput)] = [(0x01, .orange), (0x02, .rb), (0x04, .guide), (0x10, .green),
                                          (0x20, .red), (0x40, .blue), (0x80, .yellow)]
        for (bit, input) in b2 { XCTAssertEqual(RawGuitarReport.parse(report(b2: bit))?.buttons, [input], "b2 \(bit)") }
        for (bit, input) in b3 { XCTAssertEqual(RawGuitarReport.parse(report(b3: bit))?.buttons, [input], "b3 \(bit)") }
        XCTAssertEqual(RawGuitarReport.parse(report(b3: 0x08))?.buttons, [])
    }

    func testParsesAxesLittleEndian() {
        var bytes = report()
        bytes[10] = 0x20; bytes[11] = 0x4E; bytes[12] = 0x30; bytes[13] = 0xF8
        let r = RawGuitarReport.parse(bytes)
        XCTAssertEqual(r?.whammy, 20000)
        XCTAssertEqual(r?.tilt, -2000)
    }

    func testRejectsShortOrNonInput() {
        XCTAssertNil(RawGuitarReport.parse(Array(report().prefix(13))))
        var b = report(); b[0] = 0x01
        XCTAssertNil(RawGuitarReport.parse(b))
    }

    func testExtrasList() {
        XCTAssertEqual(GuitarInput.extras, [.guide, .dpadLeft, .dpadRight, .rb, .leftStickClick, .rightStickClick])
    }
}
