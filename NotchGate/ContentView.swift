import SwiftUI
import AppKit

struct ContentView: View {
    var state: NotchState
    var stats: SystemMonitor
    var calendar: CalendarService
    var weather: WeatherService
    var apps: AppSlotStore
    var flyout: WidgetFlyoutController
    var onHoverChange: (Bool) -> Void

    @Environment(LicenseManager.self) private var license
    @Environment(ThemeManager.self) private var theme
    @Environment(NotchCustomization.self) private var layout
    @Environment(PomodoroService.self) private var pomodoro

    private var geometry: NotchGeometry { state.geometry }

    var body: some View {
        VStack(spacing: 0) {
            collapsedBar
            if state.isExpanded {
                expandedBody
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -18)),
                            removal: .opacity.combined(with: .offset(y: -10))
                        )
                    )
            }
        }
        .animation(NotchAnimationManager.shared.expandAnimation, value: state.isExpanded)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            NotchBackdrop(
                expanded: state.isExpanded,
                flushToTopBar: !state.isExpanded,
                bottomRadius: state.isExpanded ? NotchGeometry.cornerRadius : geometry.collapsedBottomRadius
            )
        )
        .ignoresSafeArea(edges: .all)
        .environment(\.controlActiveState, .key)
        .onChange(of: license.isPro) { _, isPro in
            if isPro { startOptionalServices() }
        }
        .onChange(of: layout.showCalendar) { _, _ in
            startOptionalServices()
        }
        .onChange(of: layout.showWeather) { _, _ in
            if layout.showWeather {
                weather.start(promptForPermission: true)
            } else {
                startOptionalServices()
            }
        }
        .onAppear {
            startOptionalServices()
        }
    }

    private var accent: Color {
        license.isPro ? theme.theme.accent : NotchTheme.midnight.accent
    }

    private var collapsedBar: some View {
        GeometryReader { proxy in
            let reserved = NotchGeometry.settingsReservedWidth
            let gutter = NotchGeometry.shoulderNotchGutter
            let cutout = geometry.hasNotch ? geometry.notchWidth : 120
            // Match the hardware cutout: the island is centered on the camera.
            let left = max(0, (proxy.size.width - cutout) / 2)
            // Keep the right shoulder's visual and hit-test region clear of Settings.
            let right = max(0, proxy.size.width - left - cutout - reserved)
            let showContent = layout.showFullscreenShoulders
            let showExpandControl = layout.autoHide && layout.autoHideRevealStyle == .closed && !state.isExpanded
            HStack(spacing: 0) {
                collapsedContent(layout.leftShoulder)
                    .padding(.leading, showExpandControl ? 36 : 6)
                    .padding(.trailing, gutter)
                    .frame(width: left, height: proxy.size.height, alignment: .trailing)
                    .contentShape(Rectangle())
                    .opacity(showContent ? 1 : 0)
                    .clipped()
                Color.clear
                    .frame(width: cutout)
                collapsedContent(layout.rightShoulder)
                    .padding(.leading, gutter)
                    .padding(.trailing, 4)
                    .frame(width: right, height: proxy.size.height, alignment: .leading)
                    .contentShape(Rectangle())
                    .opacity(showContent ? 1 : 0)
                    .clipped()
                Color.clear
                    .frame(width: reserved)
            }
            .allowsHitTesting(showContent)
        }
        .frame(height: geometry.collapsedSize.height)
        .clipped()
        .onChange(of: layout.showFullscreenShoulders) { _, _ in
            state.geometry = NotchGeometry.current()
        }
    }

    private var expandedBody: some View {
        VStack(spacing: 8) {
            if layout.showMonitoring {
                HStack(alignment: .top, spacing: 8) {
                    if layout.showCPUStat {
                        FlyoutAnchor(kind: .cpu, controller: flyout) {
                            ExpandedMeter(
                                title: "CPU",
                                value: stats.cpuUsage,
                                tint: StatHealth.load(stats.cpuUsage),
                                history: stats.cpuHistory,
                                trend: stats.trend(stats.cpuHistory),
                                prominent: true
                            )
                        }
                    }
                    if layout.showMemoryStat {
                        FlyoutAnchor(kind: .memory, controller: flyout) {
                            ExpandedMeter(
                                title: "RAM",
                                value: stats.memoryUsage,
                                tint: StatHealth.load(stats.memoryUsage),
                                history: stats.memoryHistory,
                                trend: stats.trend(stats.memoryHistory),
                                prominent: true
                            )
                        }
                    }
                    if license.isPro {
                        if let battery = stats.batteryPercent, layout.showBattery {
                            FlyoutAnchor(kind: .battery, controller: flyout) {
                                ExpandedMeter(
                                    title: stats.isCharging ? "Batt" : "Battery",
                                    value: Double(battery),
                                    tint: StatHealth.battery(battery, charging: stats.isCharging),
                                    history: stats.batteryHistory,
                                    subtitle: stats.batteryShortTime,
                                    symbol: stats.isCharging ? "bolt.fill" : nil,
                                    prominent: false
                                )
                            }
                        }
                        if layout.showDiskStat {
                            FlyoutAnchor(kind: .disk, controller: flyout) {
                                ExpandedMeter(
                                    title: "Disk",
                                    value: stats.diskUsage,
                                    tint: StatHealth.load(stats.diskUsage),
                                    history: stats.diskHistory,
                                    trend: stats.trend(stats.diskHistory),
                                    prominent: false
                                )
                            }
                        }
                    }
                }
                .frame(height: 64)
            }

            if layout.showNetwork, license.isPro {
                FlyoutAnchor(kind: .network, controller: flyout) {
                    NetworkExpanded(stats: stats)
                }
            }

            if layout.showMusic {
                // Keep playback controls independent from the generic flyout
                // tap gesture. Wrapping this row in FlyoutAnchor caused a tap
                // on previous/pause/next to bubble up and open the Music
                // window. The dedicated music shoulder remains the explicit
                // entry point for the Music flyout.
                MusicWidget(service: MusicService.shared, accent: accent)
                .frame(height: 36)
            }

            if layout.showFiles, FileShelfStore.shared.isVisible {
                FlyoutAnchor(kind: .files, controller: flyout) {
                    FileShelfWidget(store: FileShelfStore.shared, accent: accent)
                }
                .frame(height: 36)
            }

            if layout.showAppSlots {
                AppSlotsView(store: apps)
            }


            if layout.showStatusStrip {
                FlyoutAnchor(kind: .status, controller: flyout) {
                    StatusStrip(stats: stats)
                }
            }

            if layout.showCalendar, license.isPro {
                Button {
                    handleCalendarInteraction()
                } label: {
                    eventRow
                }
                .buttonStyle(.plain)
                .help(calendar.nextEvent == nil ? "Open Calendar settings" : "Open Calendar")
                .frame(height: 32)
            }

            if layout.showWeather, license.isPro {
                Button {
                    flyout.toggle(.weather)
                } label: {
                    WeatherWidget(service: weather, accent: accent)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel("Weather")
                .accessibilityHint("Open the weather forecast")
                .frame(height: 32)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .padding(.bottom, NotchGeometry.cornerRadius)
    }

    private func startOptionalServices() {
        guard license.isPro else { return }
        if layout.showCalendar { calendar.start() }
        if layout.showWeather { weather.start() }
    }

    private func handleCalendarInteraction() {
        if calendar.authorizationDenied {
            calendar.openSettings()
        } else if calendar.authorizationNotDetermined {
            Task { await calendar.requestAccessFromUser() }
        } else if let calendarURL = URL(string: "calshow:"),
                  let url = NSWorkspace.shared.urlForApplication(toOpen: calendarURL) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
        }
    }

    @ViewBuilder
    private func collapsedContent(_ slot: NotchShoulder) -> some View {
        switch slot {
        case .load:
            Button {
                flyout.toggle(.load)
            } label: {
                SystemLoadChip(cpu: stats.cpuUsage, memory: stats.memoryUsage, tint: accent, cpuHistory: stats.cpuHistory, memoryHistory: stats.memoryHistory)
            }
            .buttonStyle(.plain)
        case .clock:
            Button {
                if license.isPro {
                    flyout.toggle(.calendar)
                } else {
                    UtilityWindows.showPricing()
                }
            } label: {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(context.date, format: Date.FormatStyle(date: .omitted, time: .shortened))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .buttonStyle(.plain)
        case .status:
            Button {
                flyout.toggle(.status)
            } label: {
                StatusStrip(stats: stats, compact: true, interactive: false)
            }
            .buttonStyle(.plain)
        case .network:
            Button {
                if license.isPro {
                    flyout.toggle(.network)
                } else {
                    UtilityWindows.showPricing()
                }
            } label: {
                NetworkChip(stats: stats)
            }
            .buttonStyle(.plain)
        case .pomodoro:
            Button {
                if layout.showPomodoro {
                    PomodoroWindowManager.shared.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 10, weight: .semibold))
                    Text(pomodoro.display)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .foregroundStyle(pomodoro.justFinished ? Color(red: 0.45, green: 0.92, blue: 0.62) : .white)
                .animation(NotchAnimationManager.shared.fadeAnimation, value: pomodoro.justFinished)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(HoverScaleButtonStyle(hover: 1.05))
            .opacity(layout.showPomodoro ? 1 : 0)
            .disabled(!layout.showPomodoro)
        case .search:
            Button {
                SearchService.shared.toggle()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .help("Search")
            }
            .buttonStyle(HoverScaleButtonStyle(hover: 1.05))
        case .music:
            Button {
                flyout.toggle(.music)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                    Text(MusicService.shared.hasTrack ? MusicService.shared.title : "Music")
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(HoverScaleButtonStyle(hover: 1.05))
        case .files:
            if FileShelfStore.shared.isVisible {
            Button { flyout.toggle(.files) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.down")
                    Text(FileShelfStore.shared.items.isEmpty ? "Files" : "\(FileShelfStore.shared.items.count)")
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(HoverScaleButtonStyle(hover: 1.05))
            }
        case .empty:
            Color.clear.frame(height: 1)
        }
    }

    @ViewBuilder
    private var eventRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(calendar.nextEvent?.calendarColor ?? Color.white.opacity(0.2))
                .frame(width: 7, height: 7)
            if let event = calendar.nextEvent {
                Text(event.title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(0)
                Spacer(minLength: 8)
                Text(event.isAllDay
                     ? "\(event.start.formatted(date: .abbreviated, time: .omitted)) · All day"
                     : event.start.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            } else {
                Text("Calendar")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(calendar.authorizationDenied || calendar.authorizationNotDetermined ? "—" : "No events")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var batteryColor: Color {
        guard let battery = stats.batteryPercent else { return .white }
        if stats.isCharging { return Color(red: 0.45, green: 0.92, blue: 0.62) }
        if battery <= 20 { return Color(red: 1, green: 0.42, blue: 0.38) }
        return .white
    }
}

private struct SystemLoadChip: View {
    let cpu: Double
    let memory: Double
    let tint: Color
    var cpuHistory: [Double] = []
    var memoryHistory: [Double] = []

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "cpu")
                .font(.system(size: 9, weight: .semibold))
            Text(String(format: "%.0f/%.0f", cpu, memory))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(StatHealth.load(max(cpu, memory)))
            TrendArrow(direction: cpuHistory.isEmpty ? 0 : (cpuHistory.suffix(2).last ?? cpu) > cpuHistory.dropLast().last ?? cpu ? 1 : -1)
        }
        .foregroundStyle(tint.opacity(0.92))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .truncationMode(.tail)
        .help("CPU \(Int(cpu))%  ·  Memory \(Int(memory))%")
        .accessibilityLabel("CPU \(Int(cpu)) percent, memory \(Int(memory)) percent")
    }
}

private struct ExpandedMeter: View {
    let title: String
    let value: Double
    let tint: Color
    var history: [Double] = []
    var trend: Int = 0
    var subtitle: String = ""
    var symbol: String? = nil
    var prominent: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: prominent ? 5 : 4) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(.system(size: prominent ? 10 : 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(prominent ? 0.55 : 0.4))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.8)
                TrendArrow(direction: trend)
                Spacer(minLength: 4)
                Text(String(format: "%.0f%%", value))
                    .font(.system(size: prominent ? 12 : 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
            if prominent, history.count > 1 {
                MiniSparkline(values: history, tint: tint)
                    .frame(height: 14)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(6, proxy.size.width * CGFloat(min(max(value, 0), 100) / 100)))
                }
            }
            .frame(height: prominent ? 4 : 3)
        }
        .padding(8)
        .background(Color.white.opacity(prominent ? 0.06 : 0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

final class SettingsGearView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings")
        image?.isTemplate = true
        let view = NSImageView(image: image ?? NSImage())
        view.imageScaling = .scaleProportionallyDown
        view.contentTintColor = NSColor.white.withAlphaComponent(0.92)
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        toolTip = "Settings"
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        UtilityWindows.toggleSettings()
    }
}

private struct NotchBackdrop: View {
    let expanded: Bool
    var flushToTopBar = false
    var bottomRadius: CGFloat = NotchGeometry.cornerRadius

    var body: some View {
        NotchIslandShape(bottomRadius: bottomRadius)
            .fill(Color.black)
            .shadow(
                color: .black.opacity(flushToTopBar ? 0 : 0.45),
                radius: flushToTopBar ? 0 : (expanded ? 18 : 6),
                y: flushToTopBar ? 0 : 6
            )
    }
}

#Preview {
    ContentView(
        state: NotchState(),
        stats: SystemMonitor(),
        calendar: CalendarService(),
        weather: WeatherService(),
        apps: AppSlotStore.shared,
        flyout: WidgetFlyoutController(),
        onHoverChange: { _ in },
    )
    .environment(LicenseManager.shared)
    .environment(ThemeManager.shared)
    .environment(NotchCustomization.shared)
    .environment(PomodoroService.shared)
    .environment(NotchAnimationManager.shared)
    .frame(width: 420, height: 236)
}
