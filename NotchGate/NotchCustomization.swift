import AppKit
import Foundation
import SwiftUI

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .celsius: return "Celsius"
        case .fahrenheit: return "Fahrenheit"
        }
    }

    var suffix: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }

    func convert(fromCelsius value: Double) -> Double {
        switch self {
        case .celsius: return value
        case .fahrenheit: return value * 9 / 5 + 32
        }
    }

    func formatted(_ celsius: Double) -> String {
        "\(Int(convert(fromCelsius: celsius).rounded()))\(suffix)"
    }

    mutating func toggle() {
        self = self == .celsius ? .fahrenheit : .celsius
    }

    static var localeDefault: TemperatureUnit {
        Locale.current.measurementSystem == .metric ? .celsius : .fahrenheit
    }
}

enum AppSlotStyle: String, CaseIterable, Identifiable {
    case grid
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: return "Grid"
        case .list: return "List"
        }
    }

    static let capacity = 6
    var columns: Int { self == .list ? 2 : Self.capacity }
    var rows: Int { AppSlotStyle.capacity / columns }
}

enum NotchOverlayLevel: String, CaseIterable, Identifiable {
    case menuBar
    case popUpMenu
    case screenSaver

    var id: String { rawValue }

    var title: String {
        switch self {
        case .menuBar: return "Menu bar"
        case .popUpMenu: return "Pop-up menu"
        case .screenSaver: return "Screen saver (highest)"
        }
    }

    var detail: String {
        switch self {
        case .menuBar: return "Same height as the system menu bar."
        case .popUpMenu: return "Above full-screen apps; below the lock screen."
        case .screenSaver: return "Above almost everything. Can break hover."
        }
    }

    var nsLevel: NSWindow.Level {
        switch self {
        case .menuBar:
            return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        case .popUpMenu: return .popUpMenu
        case .screenSaver: return .screenSaver
        }
    }

    static func stored(_ raw: String?) -> NotchOverlayLevel {
        switch raw {
        case "floating", "menuBar": return .menuBar
        case "screenSaver": return .screenSaver
        default: return .popUpMenu
        }
    }
}

enum NotchShoulder: String, CaseIterable, Identifiable {
    case load
    case clock
    case status
    case network
    case pomodoro
    case empty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .load: return "CPU / Memory"
        case .clock: return "Clock"
        case .status: return "Status chips"
        case .network: return "Network"
        case .pomodoro: return "Pomodoro"
        case .empty: return "Nothing"
        }
    }

    var symbol: String {
        switch self {
        case .load: return "cpu"
        case .clock: return "clock"
        case .status: return "switch.2"
        case .network: return "arrow.up.arrow.down"
        case .pomodoro: return "timer"
        case .empty: return "minus"
        }
    }
}

@Observable
final class NotchCustomization {
    static let shared = NotchCustomization()
    static let layoutChanged = Notification.Name("notchgate.layoutChanged")

    var leftShoulder: NotchShoulder {
        didSet { persist("leftShoulder", leftShoulder.rawValue) }
    }
    var rightShoulder: NotchShoulder {
        didSet { persist("rightShoulder", rightShoulder.rawValue) }
    }
    /// When on, shoulder widgets stay visible in Full Screen even if the menu bar is hidden.
    var showFullscreenShoulders: Bool { didSet { persist("alwaysShowShoulderWidgets", showFullscreenShoulders) } }
    /// When on, the island stays on Full Screen spaces at the chosen overlay level.
    var alwaysShowInFullScreen: Bool { didSet { persist("keepIslandInFullScreen", alwaysShowInFullScreen) } }
    var overlayLevel: NotchOverlayLevel { didSet { persist("overlayLevel", overlayLevel.rawValue) } }
    /// When off, Settings and Pro stay above the island and its dropdown.
    var overlaySettingsWindows: Bool { didSet { persist("overlaySettingsWindows", overlaySettingsWindows) } }


    var showMonitoring: Bool { didSet { persist("showMonitoring", showMonitoring) } }
    var showAppSlots: Bool { didSet { persist("showAppSlots", showAppSlots) } }
    var showStatusStrip: Bool { didSet { persist("showStatusStrip", showStatusStrip) } }
    var showCalendar: Bool { didSet { persist("showCalendar", showCalendar) } }
    var showWeather: Bool { didSet { persist("showWeather", showWeather) } }
    var showNowPlaying: Bool { didSet { persist("showNowPlaying", showNowPlaying) } }
    var showPomodoro: Bool { didSet { persist("showPomodoro", showPomodoro) } }
    var pomodoroDuration: TimeInterval { didSet { persist("pomodoroDuration", pomodoroDuration) } }
    var rememberPosition: Bool { didSet { persist("rememberPosition", rememberPosition) } }
    var showCPUStat: Bool { didSet { persist("showCPUStat", showCPUStat) } }
    var showMemoryStat: Bool { didSet { persist("showMemoryStat", showMemoryStat) } }
    var showDiskStat: Bool { didSet { persist("showDiskStat", showDiskStat) } }
    var showNetwork: Bool { didSet { persist("showNetwork", showNetwork) } }
    var showProcesses: Bool { didSet { persist("showProcesses", showProcesses) } }
    var showDevices: Bool { didSet { persist("showDevices", showDevices) } }
    var appSlotStyle: AppSlotStyle {
        didSet { persist("appSlotStyle", appSlotStyle.rawValue) }
    }
    /// Reserved for a later preview pass. Icon-only launch is the default.
    var showAppPreviews: Bool { didSet { persist("showAppPreviews", showAppPreviews) } }
    var showAppLabels: Bool { didSet { persist("showAppLabels", showAppLabels) } }
    var showScreenshots: Bool { didSet { persist("showScreenshots", showScreenshots) } }
    var screenshotShowPreview: Bool { didSet { persist("screenshotShowPreview", screenshotShowPreview) } }
    var screenshotIncludeCursor: Bool { didSet { persist("screenshotIncludeCursor", screenshotIncludeCursor) } }
    var screenshotWindowShadows: Bool { didSet { persist("screenshotWindowShadows", screenshotWindowShadows) } }
    var screenshotSaveLocation: ScreenshotSaveLocation {
        didSet { persist("screenshotSaveLocation", screenshotSaveLocation.rawValue) }
    }
    var screenshotFormat: ScreenshotImageFormat {
        didSet { persist("screenshotFormat", screenshotFormat.rawValue) }
    }
    var showSearch: Bool { didSet { persist("showSearch", showSearch) } }
    var searchShowHistory: Bool { didSet { persist("searchShowHistory", searchShowHistory) } }
    var searchRememberHistory: Bool { didSet { persist("searchRememberHistory", searchRememberHistory) } }
    var searchTrigger: SearchTrigger {
        didSet { persist("searchTrigger", searchTrigger.rawValue) }
    }
    var searchScope: SearchScope {
        didSet { persist("searchScope", searchScope.rawValue) }
    }
    var refreshInterval: TimeInterval { didSet { persist("refreshInterval", refreshInterval) } }

    var showWiFi: Bool { didSet { persist("showWiFi", showWiFi) } }
    var showBattery: Bool { didSet { persist("showBattery", showBattery) } }
    var showSpotlight: Bool { didSet { persist("showSpotlight", showSpotlight) } }
    var showControlCenter: Bool { didSet { persist("showControlCenter", showControlCenter) } }
    var temperatureUnit: TemperatureUnit {
        didSet { persist("temperatureUnit", temperatureUnit.rawValue) }
    }

    func expandedPanelHeight(collapsedBar: CGFloat, isPro: Bool) -> CGFloat {
        var rows: [CGFloat] = []
        if showMonitoring { rows.append(64) }
        if showNetwork, isPro { rows.append(36) }
        if showAppSlots { rows.append(appSlotsHeight) }
        if showNowPlaying { rows.append(Self.nowPlayingRowHeight) }
        if showProcesses, isPro { rows.append(72) }
        if showDevices, isPro { rows.append(28) }
        if showStatusStrip { rows.append(28) }
        if showCalendar, isPro { rows.append(32) }
        if showWeather, isPro { rows.append(32) }
        if showScreenshots { rows.append(32) }
        if showSearch { rows.append(32) }
        let spacing = CGFloat(max(rows.count - 1, 0)) * 8
        let padding = 2 + NotchGeometry.cornerRadius + 2
        return collapsedBar + rows.reduce(0, +) + spacing + padding
    }

    var appSlotsHeight: CGFloat {
        switch appSlotStyle {
        case .grid: return showAppLabels ? 64 : 52
        case .list: return 96
        }
    }

    /// Distance from the top of the island to the app-slot row, matching `ContentView` order.
    func slotRowTopInset(collapsedBar: CGFloat, isPro: Bool) -> CGFloat {
        var y = collapsedBar + 2
        if showMonitoring { y += 64 + 8 }
        if showNetwork, isPro { y += 36 + 8 }
        if showNowPlaying { y += Self.nowPlayingRowHeight + 8 }
        return y
    }

    static let nowPlayingRowHeight: CGFloat = 62

    private init() {
        let defaults = UserDefaults.standard
        leftShoulder = NotchShoulder(rawValue: defaults.string(forKey: "notch.leftShoulder") ?? "") ?? .load
        rightShoulder = NotchShoulder(rawValue: defaults.string(forKey: "notch.rightShoulder") ?? "") ?? .clock
        if defaults.object(forKey: "notch.alwaysShowShoulderWidgets") != nil {
            showFullscreenShoulders = defaults.bool(forKey: "notch.alwaysShowShoulderWidgets")
        } else if defaults.object(forKey: "notch.glanceBarInFullscreen") != nil {
            showFullscreenShoulders = defaults.bool(forKey: "notch.glanceBarInFullscreen")
        } else {
            showFullscreenShoulders = true
        }
        if defaults.object(forKey: "notch.keepIslandInFullScreen") == nil {
            alwaysShowInFullScreen = true
            overlayLevel = .popUpMenu
            defaults.set(true, forKey: "notch.keepIslandInFullScreen")
            defaults.set(NotchOverlayLevel.popUpMenu.rawValue, forKey: "notch.overlayLevel")
        } else {
            alwaysShowInFullScreen = defaults.bool(forKey: "notch.keepIslandInFullScreen")
            let storedLevel = NotchOverlayLevel.stored(defaults.string(forKey: "notch.overlayLevel"))
            overlayLevel = storedLevel == .screenSaver ? .popUpMenu : storedLevel
            if storedLevel == .screenSaver {
                defaults.set(NotchOverlayLevel.popUpMenu.rawValue, forKey: "notch.overlayLevel")
            }
        }
        overlaySettingsWindows = defaults.object(forKey: "notch.overlaySettingsWindows") as? Bool ?? false
        showMonitoring = defaults.object(forKey: "notch.showMonitoring") as? Bool ?? true
        showAppSlots = defaults.object(forKey: "notch.showAppSlots") as? Bool ?? true
        showStatusStrip = defaults.object(forKey: "notch.showStatusStrip") as? Bool ?? false
        showCalendar = defaults.object(forKey: "notch.showCalendar") as? Bool ?? true
        showWeather = defaults.object(forKey: "notch.showWeather") as? Bool ?? true
        showNowPlaying = defaults.object(forKey: "notch.showNowPlaying") as? Bool ?? true
        showPomodoro = defaults.object(forKey: "notch.showPomodoro") as? Bool ?? true
        pomodoroDuration = defaults.object(forKey: "notch.pomodoroDuration") as? Double ?? 25 * 60
        rememberPosition = defaults.object(forKey: "notch.rememberPosition") as? Bool ?? true
        showCPUStat = defaults.object(forKey: "notch.showCPUStat") as? Bool ?? true
        showMemoryStat = defaults.object(forKey: "notch.showMemoryStat") as? Bool ?? true
        showDiskStat = defaults.object(forKey: "notch.showDiskStat") as? Bool ?? true
        showNetwork = defaults.object(forKey: "notch.showNetwork") as? Bool ?? true
        showProcesses = defaults.object(forKey: "notch.showProcesses") as? Bool ?? true
        showDevices = defaults.object(forKey: "notch.showDevices") as? Bool ?? false
        appSlotStyle = AppSlotStyle(rawValue: defaults.string(forKey: "notch.appSlotStyle") ?? "") ?? .grid
        showAppPreviews = defaults.object(forKey: "notch.showAppPreviews") as? Bool ?? false
        showAppLabels = defaults.object(forKey: "notch.showAppLabels") as? Bool ?? false
        showScreenshots = defaults.object(forKey: "notch.showScreenshots") as? Bool ?? false
        screenshotShowPreview = defaults.object(forKey: "notch.screenshotShowPreview") as? Bool ?? true
        screenshotIncludeCursor = defaults.object(forKey: "notch.screenshotIncludeCursor") as? Bool ?? false
        screenshotWindowShadows = defaults.object(forKey: "notch.screenshotWindowShadows") as? Bool ?? true
        screenshotSaveLocation = ScreenshotSaveLocation(rawValue: defaults.string(forKey: "notch.screenshotSaveLocation") ?? "") ?? .desktop
        screenshotFormat = ScreenshotImageFormat(rawValue: defaults.string(forKey: "notch.screenshotFormat") ?? "") ?? .png
        showSearch = defaults.object(forKey: "notch.showSearch") as? Bool ?? true
        searchShowHistory = defaults.object(forKey: "notch.searchShowHistory") as? Bool ?? true
        searchRememberHistory = defaults.object(forKey: "notch.searchRememberHistory") as? Bool ?? true
        searchTrigger = SearchTrigger(rawValue: defaults.string(forKey: "notch.searchTrigger") ?? "") ?? .click
        searchScope = SearchScope(rawValue: defaults.string(forKey: "notch.searchScope") ?? "") ?? .thisMac
        refreshInterval = defaults.object(forKey: "notch.refreshInterval") as? Double ?? 1
        showWiFi = defaults.object(forKey: "notch.showWiFi") as? Bool ?? true
        showBattery = defaults.object(forKey: "notch.showBattery") as? Bool ?? true
        showSpotlight = false
        showControlCenter = defaults.object(forKey: "notch.showControlCenter") as? Bool ?? true
        temperatureUnit = TemperatureUnit(rawValue: defaults.string(forKey: "notch.temperatureUnit") ?? "") ?? .localeDefault
    }

    private func persist(_ key: String, _ value: some Any) {
        UserDefaults.standard.set(value, forKey: "notch.\(key)")
        Persistence.flush()
        NotificationCenter.default.post(name: Self.layoutChanged, object: nil)
    }
}
