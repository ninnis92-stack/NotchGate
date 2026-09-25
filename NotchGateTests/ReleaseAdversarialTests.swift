import Foundation
import XCTest
@testable import NotchGate

@MainActor
final class ReleaseConfigurationAdversarialTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testStoreKitConfigurationHasOnlyTheExpectedNonConsumable() throws {
        let url = projectRoot.appendingPathComponent("NotchGate/Products.storekit")
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let products = try XCTUnwrap(object["products"] as? [[String: Any]])
        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(products.first?["productID"] as? String, LicenseManager.productID)
        XCTAssertEqual(products.first?["type"] as? String, "NonConsumable")
    }

    func testPrivacyManifestDeclaresRequiredReasonAPIsAndNoTracking() throws {
        let url = projectRoot.appendingPathComponent("NotchGate/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: url)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["NSPrivacyTracking"] as? Bool, false)
        let apiTypes = try XCTUnwrap(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let categories = Set(apiTypes.compactMap { $0["NSPrivacyAccessedAPIType"] as? String })
        XCTAssertTrue(categories.contains("NSPrivacyAccessedAPICategoryUserDefaults"))
        XCTAssertTrue(categories.contains("NSPrivacyAccessedAPICategoryFileTimestamp"))
        XCTAssertTrue(categories.contains("NSPrivacyAccessedAPICategoryDiskSpace"))
        XCTAssertTrue(categories.contains("NSPrivacyAccessedAPICategorySystemBootTime"))
    }

    func testReleaseEntitlementsKeepAutomationAndUserSelectedFilesScoped() throws {
        let url = projectRoot.appendingPathComponent("NotchGate/NotchGate.entitlements")
        let data = try Data(contentsOf: url)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(plist["com.apple.security.automation.apple-events"] as? Bool, true)
        XCTAssertEqual(plist["com.apple.security.files.user-selected.read-write"] as? Bool, true)
        XCTAssertNil(plist["com.apple.security.files.downloads.read-write"])
        XCTAssertNil(plist["com.apple.security.files.all"])
    }

    func testMediaControlsKeepPreviousPlayNextOrderAndExplicitOpenMenu() throws {
        let url = projectRoot.appendingPathComponent("NotchGate/MediaWidgets.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let previous = try XCTUnwrap(source.range(of: "service.previous()"))
        let play = try XCTUnwrap(source.range(of: "service.togglePlayPause()"))
        let next = try XCTUnwrap(source.range(of: "service.next()"))
        XCTAssertLessThan(previous.lowerBound, play.lowerBound)
        XCTAssertLessThan(play.lowerBound, next.lowerBound)
        XCTAssertTrue(source.contains("Button(\"Open Music\")"))
        XCTAssertTrue(source.contains("Button(\"Open Spotify\")"))
    }

    func testExpandedMusicControlsDoNotInheritFlyoutTapGesture() throws {
        let url = projectRoot.appendingPathComponent("NotchGate/ContentView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let musicSection = try XCTUnwrap(source.range(of: "if layout.showMusic {"))
        let remainder = source[musicSection.upperBound...]
        let sectionEnd = remainder.firstIndex(of: "}") ?? remainder.endIndex
        let section = remainder[..<sectionEnd]
        XCTAssertTrue(section.contains("MusicWidget(service: MusicService.shared"))
        XCTAssertFalse(section.contains("FlyoutAnchor(kind: .music"))
    }

    func testWeatherPermissionIsDeclaredAndPromptedWhenWeatherIsEnabled() throws {
        let infoURL = projectRoot.appendingPathComponent("NotchGate/Info.plist")
        let infoData = try Data(contentsOf: infoURL)
        let info = try XCTUnwrap(PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any])
        XCTAssertNotNil(info["NSLocationWhenInUseUsageDescription"] as? String)

        let content = try String(contentsOf: projectRoot.appendingPathComponent("NotchGate/ContentView.swift"), encoding: .utf8)
        XCTAssertTrue(content.contains("weather.start(promptForPermission: true)"))
        let weather = try String(contentsOf: projectRoot.appendingPathComponent("NotchGate/WeatherWidget.swift"), encoding: .utf8)
        XCTAssertTrue(weather.contains("func start(promptForPermission: Bool = false)"))
        XCTAssertTrue(weather.contains("requestAccessFromUser()"))
    }

    func testWeatherRowLeavesTapToItsFlyoutAnchor() throws {
        let content = try String(contentsOf: projectRoot.appendingPathComponent("NotchGate/ContentView.swift"), encoding: .utf8)
        let weather = try String(contentsOf: projectRoot.appendingPathComponent("NotchGate/WeatherWidget.swift"), encoding: .utf8)
        XCTAssertTrue(content.contains("flyout.toggle(.weather)"))
        XCTAssertTrue(content.contains(".accessibilityHint(\"Open the weather forecast\")"))
        XCTAssertFalse(weather.contains(".onTapGesture"))
        XCTAssertFalse(weather.contains("Button {\n                    layout.temperatureUnit.toggle()"))
    }

    func testQuickActionCellsKeepPointerAndDropHighlightsAndUseFullCellHitTesting() throws {
        let source = try String(contentsOf: projectRoot.appendingPathComponent("NotchGate/QuickActionsWidget.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("isPointerHighlighted || isDropHighlighted"))
        XCTAssertTrue(source.contains("func setDropHighlighted"))
        XCTAssertTrue(source.contains("bounds.contains(point) ? self : nil"))
        XCTAssertTrue(source.contains("for cell in cells.reversed() where hitFrame(for: cell).contains(local)"))
    }

    func testInvalidSecurityScopedBookmarksFailClosed() {
        XCTAssertNil(SecurityScoped.resolve(Data([0, 1, 2, 3])))
        let item = FileShelfItem(id: UUID(), name: "missing", bookmark: Data([9, 8, 7]), isDirectory: false)
        XCTAssertNil(item.resolvedURL())
    }

    func testFreeAndProFeatureBoundariesAreExplicit() throws {
        let customization = try String(contentsOf: projectRoot.appendingPathComponent("NotchGate/NotchCustomization.swift"), encoding: .utf8)
        let shelf = try String(contentsOf: projectRoot.appendingPathComponent("NotchGate/MediaWidgets.swift"), encoding: .utf8)
        let settings = try String(contentsOf: projectRoot.appendingPathComponent("NotchGate/SettingsView.swift"), encoding: .utf8)
        XCTAssertTrue(customization.contains("var autoHide"))
        XCTAssertTrue(customization.contains("isPro || !FileShelfStore.shared.items.isEmpty"))
        XCTAssertTrue(shelf.contains("guard requirePro() else { return }"))
        XCTAssertTrue(shelf.contains("func remove(_ item: FileShelfItem)"))
        XCTAssertTrue(settings.contains("Auto-hide NotchGate"))
    }

    func testBrightnessUsesTheSharedInlineHUDAndClampsSlider() throws {
        let source = try String(contentsOf: projectRoot.appendingPathComponent("NotchGate/SystemHUD.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("present(.brightness, value: value, symbol: \"sun.max.fill\")"))
        XCTAssertTrue(source.contains("min(max(next, 0), 1)"))
        XCTAssertTrue(source.contains("kind == .brightness"))
        XCTAssertTrue(source.contains("pollBrightness()"))
        XCTAssertTrue(source.contains("0.15"))
    }

    func testAutoHideRevealHasAContinuousPointerFallback() throws {
        let source = try String(contentsOf: projectRoot.appendingPathComponent("NotchGate/NotchGateApp.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("topBarRevealZone.contains(point)"))
        XCTAssertTrue(source.contains("NSEvent.mouseLocation"))
        XCTAssertTrue(source.contains("selector: #selector(pollPointer)"))
        XCTAssertTrue(source.contains("timeInterval: 0.08"))
    }
}

@MainActor
final class MediaPermissionTimingAdversarialTests: XCTestCase {
    func testMusicServiceDoesNotProbeExternalPlayersAtStartup() {
        let service = MusicService()
        service.start()
        XCTAssertFalse(service.hasTrack)
        XCTAssertNil(service.automationIssue)
    }
}

final class PlaybackSelectionTests: XCTestCase {
    func testPlayingSourceWinsOverPausedCurrentAndForeground() {
        XCTAssertEqual(PlaybackSelection.choose(available: ["music", "spotify"], playing: ["spotify"], current: "music", frontmost: "music"), "spotify")
    }
    func testBothPlayingOrPausedKeepCurrentRegardlessOfForeground() {
        for playing in [["music", "spotify"], []] {
            XCTAssertEqual(PlaybackSelection.choose(available: ["music", "spotify"], playing: playing, current: "spotify", frontmost: "music"), "spotify")
        }
    }
    func testClosedPlayerFallsBackAndNoPlayersClearsSelection() {
        XCTAssertEqual(PlaybackSelection.choose(available: ["music"], playing: [], current: "spotify", frontmost: nil), "music")
        XCTAssertNil(PlaybackSelection.choose(available: [], playing: [], current: "spotify", frontmost: nil))
    }
}

final class CalendarSelectionTests: XCTestCase {
    func testNextEventUsesChronologicalOrderIncludingAllDayEvents() {
        let now = Date(timeIntervalSince1970: 1_000)
        let allDay = UpcomingEvent(id: "all-day", title: "Today", start: Date(timeIntervalSince1970: 900), end: Date(timeIntervalSince1970: 86_000), location: nil, isAllDay: true, calendarColor: .blue)
        let laterTimed = UpcomingEvent(id: "later", title: "Tomorrow", start: Date(timeIntervalSince1970: 2_000), end: Date(timeIntervalSince1970: 2_600), location: nil, isAllDay: false, calendarColor: .red)
        XCTAssertEqual(CalendarSelection.nextEvent(from: [allDay, laterTimed], now: now)?.id, "all-day")
    }

    func testExpiredEventsFallBackToFirstVisibleEvent() {
        let now = Date(timeIntervalSince1970: 1_000)
        let expired = UpcomingEvent(id: "expired", title: "Past", start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 200), location: nil, isAllDay: false, calendarColor: .blue)
        XCTAssertEqual(CalendarSelection.nextEvent(from: [expired], now: now)?.id, "expired")
        XCTAssertNil(CalendarSelection.nextEvent(from: [], now: now))
    }
}

final class AutoHideBehaviorTests: XCTestCase {
    func testRevealZoneRejectsMenuBarOutsideIslandAcrossDisplays() {
        let screens = [
            NSRect(x: 0, y: 0, width: 1512, height: 982),
            NSRect(x: -1920, y: -240, width: 1920, height: 1080),
            NSRect(x: 1512, y: 982, width: 2560, height: 1440)
        ]
        for screen in screens {
            for hasNotch in [false, true] {
                for scale in [1.0, 2.0] {
                    let geometry = NotchGeometry(
                        screenFrame: screen, notchMinX: screen.midX - 90,
                        notchWidth: 180, notchHeight: hasNotch ? 32 : 24,
                        hasNotch: hasNotch, hidesCollapsedShoulders: false,
                        isImmersive: true, isMenuBarHidden: true, backingScale: scale
                    )
                    let zone = geometry.topBarRevealZone
                    XCTAssertEqual(zone, geometry.closestActivationZone)
                    XCTAssertLessThan(zone.width, screen.width)
                    let y = screen.maxY - 1
                    for x in [zone.minX + 1, zone.midX, zone.maxX - 1] {
                        XCTAssertTrue(zone.contains(NSPoint(x: x, y: y)))
                    }
                    for x in [screen.minX + 1, zone.minX - 0.5, zone.maxX + 0.5, screen.maxX - 1] {
                        XCTAssertFalse(zone.contains(NSPoint(x: x, y: y)))
                    }
                    XCTAssertFalse(zone.contains(NSPoint(x: zone.midX, y: zone.minY - 0.5)))
                    XCTAssertFalse(zone.contains(NSPoint(x: zone.midX, y: screen.maxY + 0.5)))
                    // Sweep the entire menu bar: only the island may reveal.
                    for x in stride(from: screen.minX, to: screen.maxX, by: 2) {
                        let inside = zone.contains(NSPoint(x: x, y: y))
                        XCTAssertEqual(inside, x >= zone.minX && x < zone.maxX)
                        XCTAssertEqual(AutoHidePolicy.shouldHide(enabled: true, expanded: false,
                            flyoutVisible: false, utilityBlocking: false,
                            pointerInRevealZone: inside), !inside)
                    }
                }
            }
        }
    }

    func testAutoHideExpandsOnlyInsideTheCameraActivationZone() {
        XCTAssertFalse(AutoHidePolicy.shouldExpandOnIslandHover(
            enabled: true, style: .open, pointerInExpansionZone: false
        ))
        XCTAssertTrue(AutoHidePolicy.shouldExpandOnIslandHover(
            enabled: true, style: .open, pointerInExpansionZone: true
        ))
        XCTAssertFalse(AutoHidePolicy.shouldExpandOnIslandHover(
            enabled: true, style: .closed, pointerInExpansionZone: true
        ))
        XCTAssertTrue(AutoHidePolicy.shouldExpandOnIslandHover(
            enabled: false, style: .closed, pointerInExpansionZone: true
        ))
    }

    func testAutoHideExpansionZoneIsNarrowerThanTheCollapsedShoulders() {
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let geometry = NotchGeometry(
            screenFrame: screen, notchMinX: screen.midX - 90,
            notchWidth: 180, notchHeight: 32, hasNotch: true,
            hidesCollapsedShoulders: false, isImmersive: true,
            isMenuBarHidden: true, backingScale: 2
        )
        XCTAssertLessThan(geometry.autoHideExpansionZone.width, geometry.topBarRevealZone.width)
        XCTAssertTrue(geometry.autoHideExpansionZone.contains(
            NSPoint(x: geometry.notchRect.midX, y: screen.maxY - 2)
        ))
        XCTAssertFalse(geometry.autoHideExpansionZone.contains(
            NSPoint(x: geometry.topBarRevealZone.minX + 4, y: screen.maxY - 2)
        ))
    }

    func testExpandControlAppearsOnlyForClosedAutoHideMode() {
        XCTAssertTrue(AutoHidePolicy.showsExpandControl(enabled: true, style: .closed, expanded: false))
        XCTAssertFalse(AutoHidePolicy.showsExpandControl(enabled: false, style: .closed, expanded: false))
        XCTAssertFalse(AutoHidePolicy.showsExpandControl(enabled: true, style: .open, expanded: false))
        XCTAssertFalse(AutoHidePolicy.showsExpandControl(enabled: true, style: .closed, expanded: true))
    }

    func testExpandControlIsNamedAndHasAnAdequateClickTarget() {
        let button = ExpandControlView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        XCTAssertEqual(button.toolTip, "Open NotchGate panel")
        XCTAssertEqual(button.accessibilityLabel(), "Open NotchGate panel")
        XCTAssertGreaterThanOrEqual(button.frame.width, 24)
        XCTAssertGreaterThanOrEqual(button.frame.height, 24)
    }

    func testOnlyIdlePointerAwayFromTopCanHide() {
        XCTAssertTrue(AutoHidePolicy.shouldHide(
            enabled: true, expanded: false, flyoutVisible: false,
            utilityBlocking: false, pointerInRevealZone: false
        ))

        let blockingStates: [(Bool, Bool, Bool, Bool, Bool)] = [
            (false, false, false, false, false), // preference disabled
            (true, true, false, false, false),  // expanded panel
            (true, false, true, false, false),  // open flyout
            (true, false, false, true, false),  // settings or paywall
            (true, false, false, false, true)   // pointer still at top edge
        ]
        for (enabled, expanded, flyout, utility, topEdge) in blockingStates {
            XCTAssertFalse(AutoHidePolicy.shouldHide(
                enabled: enabled, expanded: expanded, flyoutVisible: flyout,
                utilityBlocking: utility, pointerInRevealZone: topEdge
            ))
        }
    }
}

final class BrightnessBehaviorTests: XCTestCase {
    func testStartupAndTinyReadNoiseDoNotPresentHUD() {
        XCTAssertFalse(BrightnessHUDPolicy.changed(from: nil, to: 0.5))
        XCTAssertFalse(BrightnessHUDPolicy.changed(from: 0.5, to: 0.5))
        XCTAssertFalse(BrightnessHUDPolicy.changed(from: 0.5, to: 0.5005))
        XCTAssertFalse(BrightnessHUDPolicy.changed(from: 0.5, to: .nan))
    }

    func testHardwareBrightnessChangesAndSliderBounds() {
        XCTAssertTrue(BrightnessHUDPolicy.changed(from: 0.5, to: 0.55))
        XCTAssertTrue(BrightnessHUDPolicy.changed(from: 0.5, to: 0.45))
        XCTAssertEqual(BrightnessHUDPolicy.clamped(-0.2), 0)
        XCTAssertEqual(BrightnessHUDPolicy.clamped(1.2), 1)
        XCTAssertEqual(BrightnessHUDPolicy.clamped(0.45), 0.45)
    }
}
