import SwiftUI

struct NowPlayingExpanded: View {
    var service: NowPlayingService
    var accent: Color

    var body: some View {
        HStack(spacing: 10) {
            artwork
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        NowPlayingSourceMenu(service: service)
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    control("backward.fill", "Previous") { service.previousTrack() }
                    control(service.item?.isPlaying == true ? "pause.fill" : "play.fill", service.item?.isPlaying == true ? "Pause" : "Play") {
                        service.togglePlayPause()
                    }
                    control("forward.fill", "Next") { service.nextTrack() }
                }
                VolumeSlider(accent: accent)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: NotchCustomization.nowPlayingRowHeight, maxHeight: NotchCustomization.nowPlayingRowHeight)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        guard let item = service.item else { return "Play something to control it here" }
        if item.artist.isEmpty { return item.appName.isEmpty ? "Now Playing" : item.appName }
        if item.appName.isEmpty { return item.artist }
        return "\(item.artist) · \(item.appName)"
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let image = service.item?.artwork {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            }
        }
        .frame(width: 32, height: 32)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func control(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct VolumeSlider: View {
    var accent: Color
    @Bindable private var volume = OutputVolume.shared

    var body: some View {
        HStack(spacing: 8) {
            Button(action: volume.toggleMute) {
                Image(systemName: volume.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(volume.isMuted ? "Unmute" : "Mute")
            .accessibilityLabel(volume.isMuted ? "Unmute" : "Mute")

            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let fill = CGFloat(volume.isMuted ? 0 : volume.level)
                let thumb = max(7, min(width - 7, width * fill))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .frame(height: 6)
                    Capsule()
                        .fill(accent.opacity(0.95))
                        .frame(width: max(6, thumb), height: 6)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                        .offset(x: thumb - 7)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            volume.setLevel(Double(drag.location.x / width))
                        }
                )
            }
            .frame(height: 22)
        }
        .frame(height: 22)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int((volume.isMuted ? 0 : volume.level) * 100)) percent")
    }
}

struct NowPlayingSourceMenu: View {
    var service: NowPlayingService

    var body: some View {
        Menu {
            if service.sources.isEmpty {
                Text("No sources")
            } else {
                ForEach(service.sources) { source in
                    Button {
                        service.select(source)
                    } label: {
                        if source.id == service.selectedSourceID {
                            Label(source.menuTitle, systemImage: "checkmark")
                        } else {
                            Text(source.menuTitle)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(service.item?.title ?? "Nothing playing")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .tint(.white)
        .help("Choose which app these controls affect")
    }
}
