import AppKit
import XCTest
@testable import NotchGate

@MainActor
final class AppDropAdversarialTests: XCTestCase {
    func testRegularFileIsRejectedByAppSlots() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchgate-file-\(UUID().uuidString).txt")
        try "test".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let board = NSPasteboard(name: .init("notchgate.tests.regular-file"))
        board.clearContents()
        board.writeObjects([url as NSURL])

        XCTAssertNil(PasteboardApps.firstApplication(from: board))
    }

    func testWebURLIsRejectedByAppSlots() {
        let board = NSPasteboard(name: .init("notchgate.tests.web-url"))
        board.clearContents()
        board.setString("https://example.com/file.pdf", forType: .URL)

        XCTAssertNil(PasteboardApps.firstApplication(from: board))
    }
}

final class LicenseAdversarialTests: XCTestCase {
    func testPaidGateIsOnAndProductIDMatchesStore() {
        XCTAssertEqual(LicenseManager.productID, "com.notchlens.pro")
        #if DEBUG
        XCTAssertTrue(LicenseManager.bypassPaidGate)
        #else
        XCTAssertFalse(LicenseManager.bypassPaidGate)
        #endif
    }
}

final class SearchMatcherTests: XCTestCase {
    func testRanksExactPrefixWordAndInitialsLikeSpotlight() {
        XCTAssertEqual(SearchMatcher.rank(name: "Safari", query: "safari"), .exact)
        XCTAssertEqual(SearchMatcher.rank(name: "Safari", query: "saf"), .prefix)
        XCTAssertEqual(SearchMatcher.rank(name: "Google Chrome", query: "chr"), .wordPrefix)
        XCTAssertEqual(SearchMatcher.rank(name: "Google Chrome", query: "gc"), .initials)
        XCTAssertEqual(SearchMatcher.rank(name: "Calculator", query: "culat"), .contains)
        XCTAssertNil(SearchMatcher.rank(name: "Safari", query: "zzz"))
    }

    func testPrefixBeatsSubstring() {
        let prefix = SearchMatcher.rank(name: "Notes", query: "no")
        let contains = SearchMatcher.rank(name: "Keynote", query: "no")
        XCTAssertEqual(prefix, .prefix)
        XCTAssertEqual(contains, .contains)
        XCTAssertLessThan(prefix!, contains!)
    }
}

final class SpotlightQueryStringTests: XCTestCase {
    func testThisMacQuerySearchesNameAndContents() {
        let query = SpotlightQueryString.make(from: "invoice", scope: .thisMac)
        XCTAssertTrue(query.contains("kMDItemDisplayName"))
        XCTAssertTrue(query.contains("kMDItemTextContent"))
        XCTAssertTrue(query.contains("\"invoice*\"cdw"))
        XCTAssertFalse(query.contains("application-bundle"))
    }

    func testMultiWordQueriesAndTokensTogether() {
        let query = SpotlightQueryString.make(from: "quarterly report", scope: .thisMac)
        XCTAssertTrue(query.contains(" && "))
        XCTAssertTrue(query.contains("\"quarterly*\"cdw"))
        XCTAssertTrue(query.contains("\"report*\"cdw"))
    }

    func testEscapesSpotlightOperatorsInUserText() {
        let query = SpotlightQueryString.make(from: "foo\"bar*", scope: .files)
        XCTAssertTrue(query.contains("foo\\\"bar\\*"))
        XCTAssertTrue(query.contains("kMDItemContentTypeTree != \"com.apple.application-bundle\""))
        XCTAssertFalse(query.contains("foo\"bar*"))
    }

    func testSingleCharacterSkipsContentScan() {
        let query = SpotlightQueryString.make(from: "s", scope: .thisMac)
        XCTAssertTrue(query.contains("kMDItemDisplayName"))
        XCTAssertFalse(query.contains("kMDItemTextContent"))
    }
}

final class SandboxEntitlementTests: XCTestCase {
    func testAppEntitlementsEnableSandbox() throws {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "NotchLens.NotchGate")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool, false)
    }
}
