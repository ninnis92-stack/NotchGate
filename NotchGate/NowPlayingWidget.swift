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
                        NowPlayingSourceMenu(service: service, accent: accent, style: .expanded)
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

struct NowPlayingFlyout: View {
    var service: NowPlayingService
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let item = service.item {
                NowPlayingSourceMenu(service: service, accent: accent, style: .flyout)
                HStack(alignment: .center, spacing: 14) {
                    artwork(item.artwork, size: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        if !item.artist.isEmpty {
                            Text(item.artist)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        if !item.album.isEmpty {
                            Text(item.album)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.4))
                                .lineLimit(1)
                        }
                        if !item.appName.isEmpty {
                            Text(item.appName)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(accent.opacity(0.85))
                        }
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 18) {
                    Spacer()
                    flyoutControl("backward.fill", "Previous", action: service.previousTrack)
                    flyoutControl(item.isPlaying ? "pause.fill" : "play.fill", item.isPlaying ? "Pause" : "Play", prominent: true, action: service.togglePlayPause)
                    flyoutControl("forward.fill", "Next", action: service.nextTrack)
                    Spacer()
                }
                VolumeSlider(accent: accent)
                Button("Open \(item.appName.isEmpty ? "Player" : item.appName)") {
                    service.openPlayer()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
            } else {
                Text("Nothing is playing. Start something in Music, Spotify, or another standalone player.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                VolumeSlider(accent: accent)
            }
        }
    }

    private func artwork(_ image: NSImage?, size: CGFloat) -> some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent)
            }
        }
        .frame(width: size, height: size)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func flyoutControl(_ symbol: String, _ label: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 20 : 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(prominent ? 0.14 : 0.06), in: Circle())
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
    var accent: Color
    var style: Style

    enum Style {
        case expanded, flyout
    }

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
            label
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .tint(.white)
        .help("Choose which app these controls affect")
    }

    @ViewBuilder
    private var label: some View {
        let item = service.item
        switch style {
        case .expanded:
            HStack(spacing: 4) {
                Text(item?.title ?? "Nothing playing")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
        case .flyout:
            HStack(spacing: 6) {
                Text("Controlling")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                Text(item?.appName.isEmpty == false ? (item?.appName ?? "Player") : "Player")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
