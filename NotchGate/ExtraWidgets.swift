import AppKit
import SwiftUI

struct NetworkChip: View {
    var stats: SystemMonitor

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down")
                .font(.system(size: 8, weight: .bold))
            Text(stats.formattedRate(stats.downloadBytesPerSecond))
                .monospacedDigit()
            Image(systemName: "arrow.up")
                .font(.system(size: 8, weight: .bold))
            Text(stats.formattedRate(stats.uploadBytesPerSecond))
                .monospacedDigit()
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.9))
        .lineLimit(1)
        .truncationMode(.tail)
        .clipped()
    }
}

struct NetworkExpanded: View {
    var stats: SystemMonitor

    var body: some View {
        HStack(spacing: 10) {
            rateColumn(
                title: "Down",
                value: stats.downloadBytesPerSecond,
                history: stats.downloadHistory,
                tint: StatHealth.load(min(stats.downloadBytesPerSecond / 50_000, 100))
            )
            rateColumn(
                title: "Up",
                value: stats.uploadBytesPerSecond,
                history: stats.uploadHistory,
                tint: Color(red: 0.72, green: 0.58, blue: 1)
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func rateColumn(title: String, value: Double, history: [Double], tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
            Text(formatted(value))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            TrendArrow(direction: stats.trend(history))
            MiniSparkline(values: history, tint: tint)
                .frame(width: 52, height: 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatted(_ value: Double) -> String {
        stats.formattedRate(value)
    }
}

struct ProcessStrip: View {
    var stats: SystemMonitor

    var body: some View {
        HStack(spacing: 8) {
            ForEach(stats.processes.prefix(3)) { process in
                HStack(spacing: 6) {
                    Image(nsImage: process.icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(process.name)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.86))
                            .lineLimit(1)
                        Text(String(format: "%.0f%% · %@", process.cpu, ByteCountFormatter.string(fromByteCount: Int64(process.memory), countStyle: .memory)))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(StatHealth.load(min(process.cpu, 100)))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if stats.processes.isEmpty {
                Text("No active apps")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct DeviceStrip: View {
    var stats: SystemMonitor

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "cable.connector")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text(summary)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var summary: String {
        let displays = stats.connectedDevices.filter { $0.kind == .display }.count
        let usb = stats.connectedDevices.filter { $0.kind == .usb }.count
        return "\(displays) display\(displays == 1 ? "" : "s")  ·  \(usb) USB"
    }
}

struct TrendArrow: View {
    var direction: Int

    var body: some View {
        Image(systemName: direction > 0 ? "arrow.up.right" : direction < 0 ? "arrow.down.right" : "minus")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(direction > 0 ? Color(red: 1, green: 0.42, blue: 0.38) : direction < 0 ? Color(red: 0.45, green: 0.92, blue: 0.62) : .white.opacity(0.28))
    }
}

struct MiniSparkline: View {
    var values: [Double]
    var tint: Color

    var body: some View {
        GeometryReader { proxy in
            let points = normalized(in: proxy.size)
            Path { path in
                guard points.count > 1 else { return }
                path.move(to: points[0])
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
    }

    private func normalized(in size: CGSize) -> [CGPoint] {
        guard values.count > 1, size.width > 0, size.height > 0 else { return [] }
        let maxValue = max(values.max() ?? 1, 1)
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) * step,
                y: size.height - (CGFloat(value / maxValue) * (size.height - 2) + 1)
            )
        }
    }
}
