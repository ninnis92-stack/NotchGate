import SwiftUI

struct PricingView: View {
    @Environment(LicenseManager.self) private var license
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            comparisonTable
            footer
        }
        .padding(24)
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            license.start()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NotchGate Pro")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("A one-time unlock for calendar, weather, live network, per-app load, devices, disk and battery meters, and accent themes. No subscription.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var comparisonTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Feature")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Free")
                    .frame(width: 70)
                Text("Pro")
                    .frame(width: 70)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            row("Notch overlay", free: true, pro: true)
            row("CPU & memory", free: true, pro: true)
            row("Apps and search", free: true, pro: true)
            row("Now Playing", free: true, pro: true)
            row("Pomodoro timer", free: true, pro: true)
            row("Volume & brightness HUDs", free: true, pro: true)
            row("Calendar & weather", free: false, pro: true)
            row("Network, apps & devices", free: false, pro: true)
            row("Disk & battery meters", free: false, pro: true)
            row("Custom themes", free: false, pro: true)
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func row(_ title: String, free: Bool, pro: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                mark(free)
                    .frame(width: 70)
                mark(pro)
                    .frame(width: 70)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            Divider()
        }
    }

    private func mark(_ enabled: Bool) -> some View {
        Image(systemName: enabled ? "checkmark.circle.fill" : "minus.circle")
            .foregroundStyle(enabled ? theme.accent : Color.secondary.opacity(0.45))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if license.isPro {
                Label("You have NotchGate Pro on this Mac.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(theme.accent)
                    .font(.system(size: 13, weight: .semibold))
            } else {
                Button {
                    Task { await license.purchase() }
                } label: {
                    Text(license.isPurchasing ? "Purchasing…" : "Unlock Pro — \(license.displayPrice)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .disabled(license.isPurchasing)
                .controlSize(.large)
            }

            Button("Restore Purchases") {
                Task { await license.restorePurchases() }
            }
            .disabled(license.isRestoring)

            if let statusMessage = license.statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("One-time purchase handled securely by the Mac App Store.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    PricingView()
        .environment(LicenseManager.shared)
        .environment(ThemeManager.shared)
}
