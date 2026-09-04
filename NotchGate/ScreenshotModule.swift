import AppKit
import SwiftUI

struct ScreenshotWidget: View {
    var manager: ScreenshotManager
    var accent: Color

    @Environment(NotchCustomization.self) private var layout

    var body: some View {
        HStack(spacing: 8) {
            if layout.screenshotShowPreview, let image = manager.lastImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: manager.countdown > 0 ? "timer" : "camera")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
            }
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var label: String {
        if manager.countdown > 0 { return "\(manager.countdown)s" }
        if let name = manager.lastURL?.lastPathComponent { return name }
        if let status = manager.statusMessage { return status }
        return "Screenshot"
    }
}

struct ScreenshotFlyout: View {
    var manager: ScreenshotManager
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                captureButton("Display", symbol: "display") { manager.captureFullScreen() }
                captureButton("Window", symbol: "macwindow") { manager.captureFrontWindow() }
                captureButton("Selection", symbol: "rectangle.dashed") { manager.captureSelection() }
            }
            HStack(spacing: 8) {
                ForEach([5, 10, 15], id: \.self) { seconds in
                    Button("\(seconds)s") { manager.captureAfterDelay(seconds) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
            }
            if let image = manager.lastImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onTapGesture { manager.openLast() }
                HStack {
                    Button("Open") { manager.openLast() }
                    Button("Show in Finder") { manager.revealLast() }
                    Spacer()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(accent)
            }
            if let status = manager.statusMessage {
                Text(status)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private func captureButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
