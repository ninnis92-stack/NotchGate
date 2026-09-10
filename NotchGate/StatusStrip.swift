import AppKit
import SwiftUI

enum MenuBarShortcuts {
    static func openWiFi() {
        if open("x-apple.systempreferences:com.apple.wifi-settings-extension") { return }
        if open("x-apple.systempreferences:com.apple.Network-Settings.extension") { return }
        _ = NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Network.prefPane"))
    }

    static func openBattery() {
        open("x-apple.systempreferences:com.apple.Battery-Settings.extension")
    }

    static func openControlCenter() {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/ControlCenter.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    @discardableResult
    private static func open(_ spec: String) -> Bool {
        guard let url = URL(string: spec) else { return false }
        return NSWorkspace.shared.open(url)
    }
}

struct StatusStrip: View {
    var stats: SystemMonitor
    var compact: Bool = false

    @Environment(NotchCustomization.self) private var layout

    var body: some View {
        Group {
            if compact {
                compactStrip
            } else {
                fullStrip
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .contain)
    }

    private var fullStrip: some View {
        HStack(spacing: 4) {
            ForEach(enabledItems) { item in
                stripButton(item.symbol, label: item.label, tint: item.tint, action: item.action)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .padding(.horizontal, 6)
        .background {
            Capsule(style: .continuous).fill(Color.white.opacity(0.05))
        }
    }

    private var compactStrip: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(compactPrefixes, id: \.count) { items in
                HStack(spacing: 6) {
                    ForEach(items) { item in
                        stripButton(item.symbol, label: item.label, tint: item.tint, action: item.action)
                    }
                }
            }
        }
        .clipped()
    }

    private var compactPrefixes: [[StatusItem]] {
        let items = enabledItems
        guard !items.isEmpty else { return [] }
        return (1...items.count).reversed().map { Array(items.prefix($0)) }
    }

    private var enabledItems: [StatusItem] {
        var items: [StatusItem] = []
        if layout.showWiFi {
            items.append(StatusItem(id: "wifi", symbol: stats.wifiSymbol, label: "Wi-Fi", tint: nil, action: MenuBarShortcuts.openWiFi))
        }
        if layout.showBattery {
            items.append(StatusItem(id: "battery", symbol: stats.batterySymbol, label: "Battery", tint: stats.batteryTint, action: MenuBarShortcuts.openBattery))
        }
        if layout.showControlCenter {
            items.append(StatusItem(id: "control", symbol: "switch.2", label: "Control Center", tint: nil, action: MenuBarShortcuts.openControlCenter))
        }
        return items
    }

    private func stripButton(_ symbol: String, label: String, tint: Color?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .foregroundStyle(tint ?? Color.white.opacity(0.9))
                .frame(maxWidth: compact ? nil : .infinity)
                .frame(height: compact ? 16 : 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct StatusItem: Identifiable {
    let id: String
    let symbol: String
    let label: String
    let tint: Color?
    let action: () -> Void
}

struct StatusFlyout: View {
    var stats: SystemMonitor
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("These open the real Mac controls. They do not replace the menu bar.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
            StatusStrip(stats: stats)
        }
    }
}

extension SystemMonitor {
    var wifiSymbol: String {
        if !wifiPowered { return "wifi.slash" }
        if wifiConnected { return "wifi" }
        return "wifi.exclamationmark"
    }

    var batterySymbol: String {
        if isCharging { return "battery.100percent.bolt" }
        guard let battery = batteryPercent else { return "battery.100percent" }
        switch battery {
        case 0..<20: return "battery.25percent"
        case 20..<50: return "battery.50percent"
        case 50..<80: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var batteryTint: Color {
        guard let battery = batteryPercent else { return .white }
        if isCharging { return Color(red: 0.45, green: 0.92, blue: 0.62) }
        if battery <= 20 { return Color(red: 1, green: 0.42, blue: 0.38) }
        return .white
    }
}
