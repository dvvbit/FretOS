import XCTest
@testable import FretOSCore

final class UpdatesTests: XCTestCase {
    func testNewerVersions() {
        XCTAssertTrue(AppVersion.isNewer("v1.2.0", than: "1.1.1"))
        XCTAssertTrue(AppVersion.isNewer("1.1.2", than: "1.1.1"))
        XCTAssertTrue(AppVersion.isNewer("v2.0", than: "1.9.9"))
        XCTAssertTrue(AppVersion.isNewer("1.10.0", than: "1.9.0"))   // numeric, not alphabetical
    }

    func testSameOrOlderIsNotNewer() {
        XCTAssertFalse(AppVersion.isNewer("v1.1.1", than: "1.1.1"))
        XCTAssertFalse(AppVersion.isNewer("1.1", than: "1.1.0"))
        XCTAssertFalse(AppVersion.isNewer("v1.0.9", than: "1.1.0"))
    }

    func testGarbageIsNeverNewer() {
        XCTAssertFalse(AppVersion.isNewer("", than: "1.0.0"))
        XCTAssertFalse(AppVersion.isNewer("latest", than: "1.0.0"))
        XCTAssertFalse(AppVersion.isNewer("v1.x", than: "1.0.0"))
    }

    func testChecksAtMostOncePerDay() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(UpdateCheck.isDue(lastCheck: nil, now: now))
        XCTAssertFalse(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-3600), now: now))
        XCTAssertTrue(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-86_401), now: now))
    }

    func testReadsTagFromGitHubReleaseJSON() {
        let json = #"{"tag_name":"v1.3.0","html_url":"https://evil.example/x","draft":false}"#.data(using: .utf8)!
        XCTAssertEqual(UpdateCheck.latestTag(fromReleaseJSON: json), "v1.3.0")
        XCTAssertNil(UpdateCheck.latestTag(fromReleaseJSON: Data("nope".utf8)))
    }

    func testDownloadLinkIsAlwaysOurReleasesPage() {
        XCTAssertEqual(UpdateCheck.downloadPage.absoluteString, "https://github.com/dvvbit/FretOS/releases/latest")
    }

    func testProblemReportURL() {
        let url = ProblemReport.url(appVersion: "1.2.0", macOS: "15.1", arch: "arm64",
                                    guitar: "Guitar Hero X-plorer (1430:4748)", status: "PLAYING")
        let c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(c.host, "github.com")
        XCTAssertEqual(c.path, "/dvvbit/FretOS/issues/new")
        let body = c.queryItems?.first { $0.name == "body" }?.value ?? ""
        for s in ["1.2.0", "15.1", "arm64", "X-plorer (1430:4748)", "PLAYING", "What happened"] {
            XCTAssertTrue(body.contains(s), s)
        }
        XCTAssertNotNil(c.queryItems?.first { $0.name == "title" })
    }

    func testProblemReportWithoutGuitar() {
        let url = ProblemReport.url(appVersion: "1.2.0", macOS: "14.0", arch: "x86_64", guitar: nil, status: "PLUG IN")
        let body = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "body" }!.value!
        XCTAssertTrue(body.contains("none detected"))
    }

    func testOldSettingsGetUpdateChecksOn() throws {
        let old = #"{"onboarded":true,"onlyWhenCloneHeroFront":true,"launchAtLogin":false}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(Settings.self, from: old)
        XCTAssertTrue(s.checkForUpdates)
        XCTAssertNil(s.skippedVersion)
        XCTAssertTrue(s.onboarded)
    }
}
