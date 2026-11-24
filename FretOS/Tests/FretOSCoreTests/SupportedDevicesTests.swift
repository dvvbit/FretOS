import XCTest
@testable import FretOSCore

final class SupportedDevicesTests: XCTestCase {
    // Real descriptor read from a wired X-plorer (interface 0).
    let xplorer: [UInt8] = [0x11, 0x21, 0x10, 0x01, 0x07, 0x25, 0x81, 0x14, 0x03, 0x03, 0x03, 0x04, 0x13, 0x02, 0x08, 0x03, 0x03]

    func testXplorerIsGuitar() {
        XCTAssertTrue(SupportedDevices.isXInputGuitar(interfaceClass: 0xFF, subClass: 0x5D, protocol: 0x01, extra: xplorer))
    }

    func testGuitarSubtypesAccepted() {
        for subtype: UInt8 in [0x06, 0x07, 0x0B] {
            var d = xplorer; d[4] = subtype
            XCTAssertTrue(SupportedDevices.isXInputGuitar(interfaceClass: 0xFF, subClass: 0x5D, protocol: 0x01, extra: d))
        }
    }

    func testGamepadDrumsAndWheelRejected() {
        for subtype: UInt8 in [0x01, 0x02, 0x08] {
            var d = xplorer; d[4] = subtype
            XCTAssertFalse(SupportedDevices.isXInputGuitar(interfaceClass: 0xFF, subClass: 0x5D, protocol: 0x01, extra: d))
        }
    }

    func testWrongInterfaceRejected() {
        XCTAssertFalse(SupportedDevices.isXInputGuitar(interfaceClass: 0xFF, subClass: 0x5D, protocol: 0x03, extra: xplorer))
        XCTAssertFalse(SupportedDevices.isXInputGuitar(interfaceClass: 0x03, subClass: 0x00, protocol: 0x00, extra: xplorer))
    }

    func testMissingOrShortDescriptorRejected() {
        XCTAssertFalse(SupportedDevices.isXInputGuitar(interfaceClass: 0xFF, subClass: 0x5D, protocol: 0x01, extra: []))
        XCTAssertFalse(SupportedDevices.isXInputGuitar(interfaceClass: 0xFF, subClass: 0x5D, protocol: 0x01, extra: [0x04, 0x21, 0x10, 0x01]))
    }

    func testFindsTagAfterAnotherDescriptor() {
        let other: [UInt8] = [0x03, 0x05, 0x00]
        XCTAssertTrue(SupportedDevices.isXInputGuitar(interfaceClass: 0xFF, subClass: 0x5D, protocol: 0x01, extra: other + xplorer))
    }
}
