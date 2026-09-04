import SwiftUI
import ServiceManagement

enum NotchTheme: String, CaseIterable, Identifiable {
    case midnight
    case aurora
    case ember
    case glacier

    var id: String { rawValue }

    var title: String {
        switch self {
        case .midnight: return "Midnight"
        case .aurora: return "Aurora"
        case .ember: return "Ember"
        case .glacier: return "Glacier"
        }
    }

    var accent: Color {
        switch self {
        case .midnight: return Color(red: 0.45, green: 0.78, blue: 1)
        case .aurora: return Color(red: 0.45, green: 0.92, blue: 0.62)
        case .ember: return Color(red: 1.0, green: 0.55, blue: 0.38)
        case .glacier: return Color(red: 0.72, green: 0.58, blue: 1)
        }
    }
}

@Observable
final class ThemeManager {
    static let shared = ThemeManager()
    private let defaultsKey = "notchlens.theme"

    var theme: NotchTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: defaultsKey) }
    }

    var accent: Color {
        LicenseManager.shared.isPro ? theme.accent : NotchTheme.midnight.accent
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: defaultsKey),
           let saved = NotchTheme(rawValue: raw) {
            theme = saved
        } else {
            theme = .midnight
        }
    }
}

struct SettingsView: View {
    @Environment(LicenseManager.self) private var license
    @Environment(ThemeManager.self) private var themeManager
    @Environment(NotchCustomization.self) private var customization
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var theme = themeManager
        @Bindable var layout = customization
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                islandLayout(layout: layout)
                fullScreenBehavior(layout: layout)
                modules(layout: layout)
                if usesStatusChips(layout) {
                    statusChips(layout: layout)
                }
                appearance(theme: theme)
                general
                licenseSection
            }
            .padding(22)
        }
        .frame(minWidth: 400, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            license.start()
            launchesAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func usesStatusChips(_ layout: NotchCustomization) -> Bool {
        layout.showStatusStrip || layout.leftShoulder == .status || layout.rightShoulder == .status
    }

    private func islandLayout(layout: NotchCustomization) -> some View {
        @Bindable var layout = layout
        return settingsGroup("Island") {
            Text("What sits on each side of the camera cutout.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(NotchGeometry.current().hasNotch ? "Hardware notch detected." : "No notch on this display — the island stays centered.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                shoulderPicker("Left", selection: $layout.leftShoulder)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.primary.opacity(0.18))
                    .frame(width: 54, height: 22)
                    .overlay {
                        Text("Notch")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                shoulderPicker("Right", selection: $layout.rightShoulder)
            }
            Toggle(isOn: $layout.showFullscreenShoulders) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Show shoulder indicators")
                    Text("CPU, clock, and the other glance items on the wings. Click one to open it. Off hides the items; the black shoulders stay.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }

    private func fullScreenBehavior(layout: NotchCustomization) -> some View {
        @Bindable var layout = layout
        return settingsGroup("Command center") {
            Text("The island stays on every Space, including Full Screen. Hover the camera to drop the panel. Hover the top of the display to pull it forward if an app covered it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("How high it sits", selection: $layout.overlayLevel) {
                ForEach(NotchOverlayLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            Text(layout.overlayLevel.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(isOn: $layout.overlaySettingsWindows) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sit above Settings and Pro")
                    Text("Off keeps NotchGate Settings and Pro in front of the island and its dropdown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }

    private func shoulderPicker(_ label: String, selection: Binding<NotchShoulder>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(label, selection: selection) {
                ForEach(NotchShoulder.allCases) { slot in
                    Label(slot.title, systemImage: slot.symbol).tag(slot)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .frame(maxWidth: .infinity)
    }

    private func modules(layout: NotchCustomization) -> some View {
        @Bindable var layout = layout
        return settingsGroup("When you hover") {
            Text("Only what’s on stays in the expanded island.")
                .font(.caption)
                .foregroundStyle(.secondary)
            moduleRow("cpu", "Stats", "CPU and memory. Hover a meter for history.", $layout.showMonitoring)
            if layout.showMonitoring {
                HStack(spacing: 16) {
                    Toggle("CPU", isOn: $layout.showCPUStat)
                    Toggle("RAM", isOn: $layout.showMemoryStat)
                    Toggle("Disk", isOn: $layout.showDiskStat)
                    Toggle("Battery", isOn: $layout.showBattery)
                }
                .toggleStyle(.checkbox)
                .padding(.leading, 30)
            }
            moduleRow("music.note", "Now Playing", "Track, artist, and playback.", $layout.showNowPlaying)
            moduleRow("square.grid.2x2", "Apps", "Click an icon to open it. Right-click for Open, Force Quit, Show in Finder, or Remove.", $layout.showAppSlots)
            if layout.showAppSlots {
                appsPreferences(layout: layout)
            }
            moduleRow("switch.2", "Status", "Wi‑Fi, battery, Control Center.", $layout.showStatusStrip)
            moduleRow("camera", "Screenshots", "Capture the display, a window, or a selection.", $layout.showScreenshots)
            if layout.showScreenshots {
                ScreenshotOptions(layout: layout)
            }
            moduleRow("magnifyingglass", "Search", "Spotlight-powered search from the island.", $layout.showSearch)
            if layout.showSearch {
                SearchOptions(layout: layout)
            }
            moduleRow("timer", "Pomodoro", "Draggable timer window. Assign it to a shoulder to open it from the island.", $layout.showPomodoro)
            if license.isPro {
                moduleRow("arrow.up.arrow.down", "Network", "Live upload and download.", $layout.showNetwork)
                moduleRow("app.badge", "Active apps", "CPU and memory per app.", $layout.showProcesses)
                moduleRow("cable.connector", "Devices", "Displays and USB devices.", $layout.showDevices)
                moduleRow("calendar", "Calendar", "Next event.", $layout.showCalendar)
                moduleRow("cloud.sun", "Weather", "Local conditions.", $layout.showWeather)
                if layout.showWeather {
                    Picker("Temperature", selection: $layout.temperatureUnit) {
                        ForEach(TemperatureUnit.allCases) { unit in
                            Text(unit.suffix).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.leading, 30)
                }
            }
        }
    }

    private func appsPreferences(layout: NotchCustomization) -> some View {
        @Bindable var layout = layout
        let store = AppSlotStore.shared
        return VStack(alignment: .leading, spacing: 10) {
            Picker("Layout", selection: $layout.appSlotStyle) {
                ForEach(AppSlotStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            Toggle("Show names under icons", isOn: $layout.showAppLabels)
            Toggle("Preview mode", isOn: $layout.showAppPreviews)
            Text("Hover an app to see its window. NotchGate only captures if Screen Recording is already allowed — it never asks on hover. Click the icon to open.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(0..<AppSlotStore.slotCount, id: \.self) { index in
                HStack(spacing: 8) {
                    if store.slots.indices.contains(index), let app = store.slots[index] {
                        Image(nsImage: app.icon())
                            .resizable()
                            .frame(width: 20, height: 20)
                        Text(app.displayName)
                            .lineLimit(1)
                        Spacer()
                        Button("Remove") { store.clear(index: index) }
                    } else {
                        Image(systemName: "plus.square.dashed")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Empty slot")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose…") { store.chooseApp(for: index) }
                    }
                }
                .font(.system(size: 12))
            }
        }
        .padding(.leading, 30)
    }

    private func moduleRow(_ symbol: String, _ title: String, _ detail: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: symbol)
                    .frame(width: 16)
            }
        }
        .toggleStyle(.switch)
    }

    private func statusChips(layout: NotchCustomization) -> some View {
        @Bindable var layout = layout
        return settingsGroup("Status chips") {
            HStack(spacing: 16) {
                Toggle("Wi‑Fi", isOn: $layout.showWiFi)
                Toggle("Battery", isOn: $layout.showBattery)
                Toggle("Control Center", isOn: $layout.showControlCenter)
            }
            .toggleStyle(.checkbox)
        }
    }

    private func appearance(theme: ThemeManager) -> some View {
        @Bindable var theme = theme
        return settingsGroup("Look") {
            if license.isPro {
                HStack(spacing: 10) {
                    ForEach(NotchTheme.allCases) { item in
                        Button {
                            theme.theme = item
                        } label: {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(item.accent)
                                    .frame(width: 22, height: 22)
                                    .overlay {
                                        Circle()
                                            .strokeBorder(.white.opacity(theme.theme == item ? 0.9 : 0.15), lineWidth: theme.theme == item ? 2 : 1)
                                    }
                                Text(item.title)
                                    .font(.caption2)
                                    .foregroundStyle(theme.theme == item ? .primary : .secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("Accent themes unlock with Pro.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var general: some View {
        settingsGroup("Mac") {
            Picker("Stat refresh", selection: Bindable(customization).refreshInterval) {
                Text("1 second").tag(1.0)
                Text("5 seconds").tag(5.0)
                Text("10 seconds").tag(10.0)
            }
            Toggle("Open at login", isOn: $launchesAtLogin)
                .onChange(of: launchesAtLogin) { _, enabled in
                    setLaunchAtLogin(enabled)
                }
            if let loginError {
                Text(loginError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsGroup("NotchGate") {
                HStack {
                    Text(license.isPro ? "Pro" : "Free")
                        .font(.headline)
                    Spacer()
                    if !license.isPro {
                        Button("Unlock Pro") {
                            UtilityWindows.showPricing()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                if LicenseManager.bypassPaidGate {
                    Text("Paid gate is off for testing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(license.isRestoring ? "Restoring…" : "Restore Purchases") {
                    Task { await license.restorePurchases() }
                }
                .disabled(license.isRestoring)
                if let statusMessage = license.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Product ID \(LicenseManager.productID)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            settingsGroup("Legal") {
                Text("NotchGate uses calendar, location, now-playing, and optional screen capture only on this Mac. Screenshots and search history stay on this Mac. Nothing is sold or sent to NotchLens except App Store receipt checks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchesAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

#Preview {
    SettingsView()
        .environment(LicenseManager.shared)
        .environment(ThemeManager.shared)
        .environment(NotchCustomization.shared)
}
