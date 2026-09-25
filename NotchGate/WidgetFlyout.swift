import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

enum FlyoutKind: Equatable {
    case load
    case cpu
    case memory
    case battery
    case disk
    case network
    case calendar
    case weather
    case status
    case search
    case music
    case files

    var size: NSSize {
        switch self {
        case .load: return NSSize(width: 420, height: 248)
        case .cpu, .memory: return NSSize(width: 372, height: 292)
        case .battery, .disk: return NSSize(width: 360, height: 268)
        case .network: return NSSize(width: 380, height: 220)
        case .calendar: return NSSize(width: 360, height: 368)
        case .weather: return NSSize(width: 372, height: 312)
        case .status: return NSSize(width: 340, height: 168)
        case .search: return NSSize(width: 380, height: 340)
        case .music: return NSSize(width: 340, height: 260)
        case .files: return NSSize(width: 380, height: 360)
        }
    }

    var title: String {
        switch self {
        case .load: return "System Load"
        case .cpu: return "Processor"
        case .memory: return "Memory"
        case .battery: return "Battery"
        case .disk: return "Disk"
        case .network: return "Network"
        case .calendar: return "Calendar"
        case .weather: return "Weather"
        case .status: return "Status"
        case .search: return "Search"
        case .music: return "Music"
        case .files: return "File Shelf"
        }
    }
}

@MainActor
final class WidgetFlyoutPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class WidgetFlyoutController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var hosting: NSHostingView<WidgetFlyoutRoot>?
    private var stats: SystemMonitor?
    private var calendar: CalendarService?
    private var weather: WeatherService?
    private var apps: AppSlotStore?
    private var lastToggle = Date.distantPast

    var isVisible: Bool { window?.isVisible == true }

    func configure(stats: SystemMonitor, calendar: CalendarService, weather: WeatherService, apps: AppSlotStore) {
        self.stats = stats
        self.calendar = calendar
        self.weather = weather
        self.apps = apps
    }

    func toggle(_ kind: FlyoutKind) {
        let now = Date()
        guard now.timeIntervalSince(lastToggle) >= 0.22 else { return }
        lastToggle = now
        if isVisible {
            dismiss()
        } else {
            reveal(kind)
        }
    }

    func contains(_ point: NSPoint) -> Bool {
        guard let window, window.isVisible else { return false }
        return window.frame.insetBy(dx: -16, dy: -16).contains(point)
    }

    func bridgeContains(_ point: NSPoint, island: NSRect) -> Bool {
        guard let window, window.isVisible else { return false }
        let flyout = window.frame.insetBy(dx: -16, dy: -16)
        guard flyout.intersects(island.insetBy(dx: -16, dy: -16)) else { return false }
        let bridge = flyout.union(island.insetBy(dx: -16, dy: -16))
        return bridge.contains(point) && !flyout.contains(point) && !island.contains(point)
    }
    func applyLevel(_ level: NSWindow.Level) {}
    func hoverAnchor(_ kind: FlyoutKind, isInside: Bool) {}

    func reveal(_ kind: FlyoutKind) {
        guard let stats, let calendar, let weather, let apps else { return }
        let root = WidgetFlyoutView(
            kind: kind,
            stats: stats,
            calendar: calendar,
            weather: weather,
            apps: apps,
            onHover: { _ in }
        )
        let hostedRoot = WidgetFlyoutRoot(content: root)
        if let window, let hosting {
            hosting.rootView = hostedRoot
            window.title = kind.title
            window.setContentSize(kind.size)
            UtilityWindows.raiseUtilityWindow(window)
            return
        }

        let hosting = NSHostingView(rootView: hostedRoot)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: kind.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = kind.title
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.minSize = kind.size
        window.maxSize = CGSize(width: 560, height: 640)
        window.contentView = hosting
        window.delegate = self
        if let island = NSApp.windows.first(where: { $0 is NotchPanel && $0.isVisible })?.frame {
            let origin = NSPoint(
                x: island.midX - kind.size.width / 2,
                y: island.minY - kind.size.height - 16
            )
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }
        self.hosting = hosting
        self.window = window
        UtilityWindows.raiseUtilityWindow(window)
    }

    func dismiss() {
        guard let window, window.isVisible else { return }
        lastToggle = Date()
        window.orderOut(nil)
        UtilityWindows.restoreAccessoryIfIdle()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window, window.isVisible else { return }
        lastToggle = Date()
        window.orderOut(nil)
        UtilityWindows.restoreAccessoryIfIdle()
    }
}

struct FlyoutAnchor<Content: View>: View {
    let kind: FlyoutKind
    var controller: WidgetFlyoutController
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .contentShape(Rectangle())
            .onTapGesture {
                controller.toggle(kind)
            }
    }
}

/// Flyouts are hosted in their own AppKit window, so they must receive the
/// same shared environment objects as the main overlay root.
private struct WidgetFlyoutRoot: View {
    let content: WidgetFlyoutView

    var body: some View {
        content
            .environment(LicenseManager.shared)
            .environment(ThemeManager.shared)
            .environment(NotchCustomization.shared)
    }
}

private struct WidgetFlyoutView: View {
    let kind: FlyoutKind
    var stats: SystemMonitor
    var calendar: CalendarService
    var weather: WeatherService
    var apps: AppSlotStore
    var onHover: (Bool) -> Void

    @Environment(ThemeManager.self) private var theme
    @Environment(LicenseManager.self) private var license

    private var accent: Color {
        license.isPro ? theme.theme.accent : NotchTheme.midnight.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(kind.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer()
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.28))
            }

            switch kind {
            case .load:
                LoadFlyout(stats: stats, accent: accent)
            case .cpu:
                CPUFlyout(stats: stats, accent: accent)
            case .memory:
                MemoryFlyout(stats: stats, accent: accent)
            case .battery:
                BatteryFlyout(stats: stats, accent: accent)
            case .disk:
                DiskFlyout(stats: stats, accent: accent)
            case .calendar:
                CalendarFlyout(calendar: calendar, accent: accent)
            case .weather:
                WeatherFlyout(service: weather, accent: accent)
            case .status:
                StatusFlyout(stats: stats, accent: accent)
            case .network:
                NetworkFlyout(stats: stats, accent: accent)
            case .search:
                SearchFlyout(service: SearchService.shared, accent: accent)
            case .music:
                MusicFlyout(service: MusicService.shared, accent: accent)
            case .files:
                FileShelfFlyout(store: FileShelfStore.shared, accent: accent)
            }
        }
        .padding(18)
        // Keep the AppKit window's requested size authoritative. An
        // unconstrained max-height here can make short flyouts, especially
        // Status, expand to the hosting window's maximum height.
        .frame(
            width: max(0, kind.size.width - 16),
            height: max(0, kind.size.height - 16),
            alignment: .topLeading
        )
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.96))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
        }
        .padding(8)
        .onHover(perform: onHover)
    }
}

private struct LoadFlyout: View {
    var stats: SystemMonitor
    var accent: Color

    var body: some View {
        VStack(spacing: 10) {
            compactRow(
                title: "CPU",
                value: stats.cpuUsage,
                tint: accent,
                headline: stats.loadRating(for: stats.cpuUsage),
                history: stats.cpuHistory,
                detail: "\(Int(stats.cpuUser.rounded()))% user · \(Int(stats.cpuSystem.rounded()))% system · \(stats.thermalLabel)"
            )
            compactRow(
                title: "Memory",
                value: stats.memoryUsage,
                tint: Color(red: 0.72, green: 0.58, blue: 1),
                headline: stats.loadRating(for: stats.memoryUsage),
                history: stats.memoryHistory,
                detail: "\(stats.formattedBytes(stats.memoryUsedBytes)) of \(stats.formattedBytes(stats.memoryTotalBytes))"
            )
        }
    }

    private func compactRow(
        title: String,
        value: Double,
        tint: Color,
        headline: String,
        history: [Double],
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
                Text(headline)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                Spacer()
                Text(String(format: "%.0f%%", value))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            Sparkline(values: history, tint: tint)
                .frame(height: 36)
            Text(detail)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.42))
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CPUFlyout: View {
    var stats: SystemMonitor
    var accent: Color

    var body: some View {
        StatDetailFlyout(
            value: stats.cpuUsage,
            tint: accent,
            history: stats.cpuHistory,
            headline: stats.loadRating(for: stats.cpuUsage),
            caption: stats.cpuBrand,
            rows: [
                ("User", String(format: "%.0f%%", stats.cpuUser)),
                ("System", String(format: "%.0f%%", stats.cpuSystem)),
                ("Idle", String(format: "%.0f%%", stats.cpuIdle)),
                ("Cores", "\(stats.coreCount)"),
                ("1 min avg", String(format: "%.0f%%", stats.averageLastMinute(stats.cpuHistory))),
                ("1 min peak", String(format: "%.0f%%", stats.peakLastMinute(stats.cpuHistory))),
                ("Thermal", stats.thermalLabel),
                ("Uptime", stats.formattedUptime)
            ]
        )
    }
}

private struct MemoryFlyout: View {
    var stats: SystemMonitor
    var accent: Color

    var body: some View {
        StatDetailFlyout(
            value: stats.memoryUsage,
            tint: accent,
            history: stats.memoryHistory,
            headline: stats.loadRating(for: stats.memoryUsage),
            caption: "\(stats.formattedBytes(stats.memoryUsedBytes)) of \(stats.formattedBytes(stats.memoryTotalBytes))",
            rows: [
                ("Wired", stats.formattedBytes(stats.memoryWiredBytes)),
                ("Compressed", stats.formattedBytes(stats.memoryCompressedBytes)),
                ("Swap used", stats.formattedBytes(stats.memorySwapUsedBytes)),
                ("1 min avg", String(format: "%.0f%%", stats.averageLastMinute(stats.memoryHistory))),
                ("1 min peak", String(format: "%.0f%%", stats.peakLastMinute(stats.memoryHistory))),
                ("Mac", stats.hardwareModel)
            ]
        )
    }
}

private struct BatteryFlyout: View {
    var stats: SystemMonitor
    var accent: Color

    var body: some View {
        let percent = Double(stats.batteryPercent ?? 0)
        let low = (stats.batteryPercent ?? 100) <= 20
        StatDetailFlyout(
            value: percent,
            tint: low ? Color(red: 1, green: 0.42, blue: 0.38) : Color(red: 0.45, green: 0.92, blue: 0.62),
            history: stats.batteryHistory,
            headline: stats.powerSourceLabel,
            caption: stats.batteryPercent == nil ? "No battery reported" : stats.batteryTimeLabel,
            rows: [
                ("Charge", stats.batteryPercent.map { "\($0)%" } ?? "—"),
                ("Power", stats.powerSourceLabel),
                ("1 min avg", String(format: "%.0f%%", stats.averageLastMinute(stats.batteryHistory))),
                ("Uptime", stats.formattedUptime)
            ]
        )
    }
}

private struct DiskFlyout: View {
    var stats: SystemMonitor
    var accent: Color

    var body: some View {
        StatDetailFlyout(
            value: stats.diskUsage,
            tint: Color(red: 1.0, green: 0.55, blue: 0.38),
            history: stats.diskHistory,
            headline: stats.diskName,
            caption: "\(stats.formattedBytes(stats.diskUsedBytes)) of \(stats.formattedBytes(stats.diskTotalBytes)) used",
            rows: [
                ("Free", stats.formattedBytes(max(0, stats.diskTotalBytes - stats.diskUsedBytes))),
                ("Used", String(format: "%.0f%%", stats.diskUsage)),
                ("1 min avg", String(format: "%.0f%%", stats.averageLastMinute(stats.diskHistory))),
                ("Volume", "/")
            ]
        )
    }
}

private struct StatDetailFlyout: View {
    let value: Double
    let tint: Color
    let history: [Double]
    let headline: String
    let caption: String
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.0f%%", value))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(headline)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.16), in: Capsule())
                Spacer(minLength: 0)
            }
            Text(caption)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(2)

            Sparkline(values: history, tint: tint)
                .frame(height: 44)

            FlyoutMeterBar(value: value, tint: tint)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.0)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.38))
                        Text(row.1)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
}

private struct FlyoutMeterBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(8, proxy.size.width * CGFloat(min(max(value, 0), 100) / 100)))
            }
        }
        .frame(height: 7)
    }
}

private struct Sparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let points = normalized(in: proxy.size)
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                if points.count > 1 {
                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
                Text("60s")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.28))
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }

    private func normalized(in size: CGSize) -> [CGPoint] {
        guard values.count > 1, size.width > 0, size.height > 0 else { return [] }
        let maxValue = max(values.max() ?? 1, 1)
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) * step,
                y: size.height - (CGFloat(value / maxValue) * (size.height - 8) + 4)
            )
        }
    }
}

private struct FlyoutMeter: View {
    let title: String
    let value: Double
    let tint: Color
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
                Spacer()
                Text(String(format: "%.0f%%", value))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(8, proxy.size.width * CGFloat(min(max(value, 0), 100) / 100)))
                }
            }
            .frame(height: 7)
            Text(caption)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct NetworkFlyout: View {
    var stats: SystemMonitor
    var accent: Color

    var body: some View {
        VStack(spacing: 10) {
            compact(title: "Download", value: stats.formattedRate(stats.downloadBytesPerSecond), history: stats.downloadHistory, tint: accent)
            compact(title: "Upload", value: stats.formattedRate(stats.uploadBytesPerSecond), history: stats.uploadHistory, tint: Color(red: 0.72, green: 0.58, blue: 1))
        }
    }

    private func compact(title: String, value: String, history: [Double], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
                TrendArrow(direction: stats.trend(history))
                Spacer()
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            Sparkline(values: history, tint: tint)
                .frame(height: 36)
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CalendarFlyout: View {
    var calendar: CalendarService
    var accent: Color

    var body: some View {
        if calendar.authorizationNotDetermined {
            VStack(spacing: 10) {
                flyoutEmpty(symbol: "calendar", text: "Calendar can show upcoming events under the notch. macOS will ask for access.")
                Button("Continue") {
                    Task { await calendar.requestAccessFromUser() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
            }
        } else if calendar.authorizationDenied {
            VStack(spacing: 10) {
                flyoutEmpty(symbol: "calendar.badge.exclamationmark", text: "Calendar access is needed to show upcoming events.")
                Button("Open Settings") { calendar.openSettings() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.7))
            }
        } else if calendar.upcoming.isEmpty {
            flyoutEmpty(symbol: "calendar", text: "No events in the next 7 days.")
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(calendar.upcoming) { event in
                        HStack(alignment: .top, spacing: 10) {
                            Capsule()
                                .fill(event.calendarColor)
                                .frame(width: 4)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.title)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                Text(timeRange(event))
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(accent.opacity(0.9))
                                if let location = event.location, !location.isEmpty {
                                    Text(location)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.4))
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    private func timeRange(_ event: UpcomingEvent) -> String {
        if event.isAllDay {
            return event.start.formatted(date: .abbreviated, time: .omitted) + " · All day"
        }
        let start = event.start.formatted(date: .abbreviated, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}

private struct WeatherFlyout: View {
    var service: WeatherService
    var accent: Color

    @Environment(NotchCustomization.self) private var layout

    var body: some View {
        if let snapshot = service.snapshot {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: snapshot.symbol)
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(accent)
                        .symbolRenderingMode(.hierarchical)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.location)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                        Button {
                            layout.temperatureUnit.toggle()
                        } label: {
                            Text(layout.temperatureUnit.formatted(snapshot.temperature))
                                .font(.system(size: 36, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .help("Switch \(layout.temperatureUnit == .celsius ? "to Fahrenheit" : "to Celsius")")
                        Text(snapshot.condition)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        if let high = snapshot.high, let low = snapshot.low {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("H \(layout.temperatureUnit.formatted(high))")
                                Text("L \(layout.temperatureUnit.formatted(low))")
                            }
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.7))
                        }
                        Picker("Unit", selection: Bindable(layout).temperatureUnit) {
                            Text("°C").tag(TemperatureUnit.celsius)
                            Text("°F").tag(TemperatureUnit.fahrenheit)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 88)
                        .labelsHidden()
                    }
                }

                HStack(spacing: 8) {
                    ForEach(snapshot.days) { day in
                        VStack(spacing: 6) {
                            Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.45))
                            Image(systemName: day.symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(accent)
                            Text(layout.temperatureUnit.formatted(day.high))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                            Text(layout.temperatureUnit.formatted(day.low))
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        } else {
            VStack(spacing: 10) {
                flyoutEmpty(symbol: "cloud.sun", text: service.needsLocationPermission ? "Weather can show local conditions under the notch. macOS will ask for location." : service.statusText)
                if service.needsLocationPermission {
                    Button(service.locationAccessDenied ? "Open Settings" : "Continue") {
                        if service.locationAccessDenied {
                            service.openSettings()
                        } else {
                            service.requestAccessFromUser()
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(accent)
                }
            }
        }
    }
}

private func flyoutEmpty(symbol: String, text: String) -> some View {
    VStack(spacing: 10) {
        Image(systemName: symbol)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(.white.opacity(0.35))
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
