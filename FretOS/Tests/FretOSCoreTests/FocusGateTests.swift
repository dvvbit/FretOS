import XCTest
@testable import FretOSCore

final class FocusGateTests: XCTestCase {
    func testMatchesCloneHero() {
        XCTAssertTrue(FocusGate.allows(frontmostAppName: "Clone Hero", bundleID: nil, onlyWhenCloneHeroFront: true))
        XCTAssertTrue(FocusGate.allows(frontmostAppName: "Clone Hero v1.1.0", bundleID: nil, onlyWhenCloneHeroFront: true))
        XCTAssertTrue(FocusGate.allows(frontmostAppName: "x", bundleID: "com.srylain.CloneHero", onlyWhenCloneHeroFront: true))
    }
    func testBlocksOtherApps() {
        XCTAssertFalse(FocusGate.allows(frontmostAppName: "Messages", bundleID: "com.apple.MobileSMS", onlyWhenCloneHeroFront: true))
        XCTAssertFalse(FocusGate.allows(frontmostAppName: nil, bundleID: nil, onlyWhenCloneHeroFront: true))
    }
    func testToggleOffAllowsEverything() {
        XCTAssertTrue(FocusGate.allows(frontmostAppName: "Messages", bundleID: nil, onlyWhenCloneHeroFront: false))
    }
}
