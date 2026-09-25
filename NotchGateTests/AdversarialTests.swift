import XCTest
@testable import NotchGate

@MainActor
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

final class SandboxEntitlementTests: XCTestCase {
    func testBundleIdentityIsStable() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "NotchLens.NotchGate")
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "LSUIElement"))
    }
}

@MainActor
final class UtilityWindowPresentationTests: XCTestCase {
    func testStoreKitWindowsStayAvailableAcrossAppsAndSpaces() {
        let behavior = UtilityWindows.utilityCollectionBehavior
        XCTAssertTrue(behavior.contains(.canJoinAllApplications))
        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(behavior.contains(.ignoresCycle))
        XCTAssertGreaterThan(UtilityWindows.windowLevel.rawValue, OverlayChrome.standardLevel.rawValue)
    }

    func testPopupChoosesAQuadrantWithoutOverlappingExistingUtilityWindow() {
        let screen = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = NSSize(width: 420, height: 300)
        let first = UtilityWindows.popupFrame(screen: screen, size: size, occupied: []).frame
        let second = UtilityWindows.popupFrame(screen: screen, size: size, occupied: [first]).frame
        XCTAssertFalse(first.intersects(second))
        XCTAssertTrue(screen.contains(second))
    }

    func testPopupStaysInsideSmallScreenAndUsesOneOfFourQuadrants() {
        let screen = NSRect(x: 0, y: 0, width: 800, height: 600)
        let result = UtilityWindows.popupFrame(
            screen: screen, size: NSSize(width: 360, height: 260), occupied: []
        )
        XCTAssertTrue(screen.contains(result.frame))
        XCTAssertTrue(PopupQuadrantNames.all.contains(result.quadrant))
    }
}

private enum PopupQuadrantNames {
    static let all: [UtilityWindows.PopupQuadrant] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}
