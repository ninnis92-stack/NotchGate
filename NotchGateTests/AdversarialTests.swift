import XCTest
@testable import NotchGate

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
