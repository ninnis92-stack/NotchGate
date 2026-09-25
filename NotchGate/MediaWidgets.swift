import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum PlaybackSelection {
    static func choose<Player: Equatable>(available: [Player], playing: [Player], current: Player, frontmost: Player?) -> Player? {
        if playing.contains(current) { return current }
        if let first = playing.first { return first }
        if available.contains(current) { return current }
        if let frontmost, available.contains(frontmost) { return frontmost }
        return available.first
    }
}

@Observable
@MainActor
final class MusicService {
    static let shared = MusicService()

    var title = "Music"
    var artist = "Open Music to start listening"
    var album = ""
    var isPlaying = false
    var hasTrack = false
    var playerName = "Music"
    var automationIssue: String?
    var connectionStatus = "Choose a player to connect."

    private var timer: Timer?
    private var started = false
    private var detectionEnabled = false
    private(set) var refreshInFlight = false
    private var connectedPlayers: [Player] = []
    private var activePlayer: Player = .music
    var supportsPlaybackControls: Bool { true }

    private struct PlayerSnapshot: Sendable {
        let player: Player
        let title: String
        let artist: String
        let album: String
        let isPlaying: Bool
    }

    private enum Player: Sendable, Equatable {
        case music
        case spotify

        nonisolated var name: String {
            switch self {
            case .music: return "Music"
            case .spotify: return "Spotify"
            }
        }

        nonisolated var bundleIdentifier: String {
            switch self {
            case .music: return "com.apple.Music"
            case .spotify: return "com.spotify.client"
            }
        }

        nonisolated var applicationName: String { name }
    }

    func start() {
        guard !started else { return }
        started = true
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.detectionEnabled else { return }
                self.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Begin inspecting external players only after the user opens or enables
    /// the Music module. This keeps the Apple Events prompt contextual.
    func activate() {
        let running = [Player.music, .spotify].filter(Self.isPlayerRunning)
        guard !running.isEmpty else {
            connectionStatus = "Open Apple Music or Spotify, choose a track, then connect again."
            return
        }

        connectionStatus = "Finding your active player…"
        detectionEnabled = true
        let current = activePlayer
        Task.detached(priority: .utility) { [weak self] in
            let result = Self.collectSnapshots(in: running)
            await self?.finishActivation(result, current: current, fallback: running.first!)
        }
    }

    func connectSpotify() { connect(.spotify) }
    func connectAppleMusic() { connect(.music) }

    private func connect(_ player: Player) {
        guard Self.isPlayerRunning(player) else {
            connectionStatus = "Open \(player.name), choose a track, then connect again."
            return
        }
        connectionStatus = "Connecting to \(player.name)…"
        if !connectedPlayers.contains(player) { connectedPlayers.append(player) }
        activePlayer = player
        detectionEnabled = true
        refresh()
    }

    private func finishActivation(
        _ result: (snapshots: [PlayerSnapshot], issue: String?),
        current: Player,
        fallback: Player
    ) {
        let selected = PlaybackSelection.choose(
            available: result.snapshots.map(\.player),
            playing: result.snapshots.filter(\.isPlaying).map(\.player),
            current: current,
            frontmost: nil
        ) ?? fallback
        connect(selected)
    }

    var suggestedPlayerName: String {
        (frontmostPlayer
            ?? [Player.spotify, .music].first(where: Self.isPlayerRunning)
            ?? .music).name
    }


    func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        if !NSWorkspace.shared.open(url),
           let settings = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.open(settings)
        }
    }

    func refresh() {
        guard detectionEnabled, !refreshInFlight else { return }
        refreshInFlight = true

        // Apple Events can wait on a player or on the Automation permission
        // service. Never run them on the main actor or a UI action can look
        // frozen while Spotify/Music responds.
        let preferredPlayer = activePlayer
        let frontmost = frontmostPlayer
        let probeOrder = ([frontmost, preferredPlayer].compactMap { $0 } + connectedPlayers)
            .filter { connectedPlayers.contains($0) }
            .reduce(into: [Player]()) { result, player in
                if !result.contains(player) { result.append(player) }
            }
        Task.detached(priority: .utility) { [weak self] in
            let result = Self.collectSnapshots(in: probeOrder)
            await self?.apply(result, preferredPlayer: preferredPlayer, frontmostPlayer: frontmost)
        }
    }

    @MainActor
    private func apply(_ result: (snapshots: [PlayerSnapshot], issue: String?), preferredPlayer: Player, frontmostPlayer: Player?) {
        refreshInFlight = false
        automationIssue = result.issue
        let snapshots = result.snapshots

        // Prefer the player that is actually playing. If both are paused,
        // keep the current player when possible so the controls do not jump
        // between apps while the user is browsing.
        let selected = PlaybackSelection.choose(
            available: snapshots.map(\.player),
            playing: snapshots.filter(\.isPlaying).map(\.player),
            current: activePlayer,
            frontmost: frontmostPlayer
        )
        let active = snapshots.first { $0.player == selected }

        guard let active else {
            connectionStatus = result.issue.map { "Could not connect to \($0). Check Automation settings, then try again." }
                ?? "No current track. Choose a track in your player."
            if let issue = result.issue {
                playerName = issue
            } else {
                playerName = "Music"
            }
            title = "Music"
            artist = result.issue == nil
                ? "Open Music or Spotify to start listening"
                : "Allow automation in System Settings"
            album = ""
            isPlaying = false
            hasTrack = false
            return
        }

        activePlayer = active.player
        connectionStatus = "Connected to \(active.player.name)"
        playerName = active.player.name
        title = active.title
        artist = active.artist
        album = active.album
        isPlaying = active.isPlaying
        hasTrack = true
    }

    private nonisolated static func collectSnapshots(in players: [Player]) -> (snapshots: [PlayerSnapshot], issue: String?) {
        var issue: String?
        let snapshots = players.compactMap { player -> PlayerSnapshot? in
            guard isPlayerRunning(player) else { return nil }
            guard let raw = execute(statusScript(for: player)) else {
                issue = player.name
                return nil
            }
            return snapshot(for: player, raw: raw)
        }
        return (snapshots, issue)
    }

    private nonisolated static func snapshot(for player: Player, raw: String) -> PlayerSnapshot? {
        let parts = raw.components(separatedBy: "|")
        guard parts.count >= 4, !parts[0].isEmpty else { return nil }
        return PlayerSnapshot(
            player: player,
            title: parts[0],
            artist: parts[1].isEmpty ? "Unknown artist" : parts[1],
            album: parts[2],
            isPlaying: parts[3].localizedCaseInsensitiveContains("playing")
        )
    }

    private var frontmostPlayer: Player? {
        guard let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return nil }
        return [Player.music, .spotify].first { $0.bundleIdentifier == bundleIdentifier }
    }

    private var hasRunningMusicPlayer: Bool {
        Self.isPlayerRunning(.spotify) || Self.isPlayerRunning(.music)
    }

    func togglePlayPause() {
        guard hasTrack, Self.isPlayerRunning(activePlayer) else { return }
        sendControl("playpause")
    }

    func next() {
        guard hasTrack, Self.isPlayerRunning(activePlayer) else { return }
        sendControl("next track")
    }

    func previous() {
        guard hasTrack, Self.isPlayerRunning(activePlayer) else { return }
        sendControl("previous track")
    }

    private func sendControl(_ command: String) {
        guard supportsPlaybackControls else { return }
        let player = activePlayer
        Task.detached(priority: .utility) { [weak self] in
            _ = Self.execute("tell application \"\(player.applicationName)\" to \(command)")
            await self?.refresh()
        }
        // Spotify can update its player state just after the Apple Event
        // returns. Refresh on the next run-loop turn so the notch icon and
        // title reflect the new state without launching either player.
    }

    func openMusic() {
        open(player: activePlayer)
    }

    func openMusicApp() {
        open(player: .music)
    }

    func openSpotifyApp() {
        open(player: .spotify)
    }

    private func open(player: Player) {
        let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleIdentifier)
        if let applicationURL { NSWorkspace.shared.open(applicationURL) }
    }

    private nonisolated static func isPlayerRunning(_ player: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleIdentifier).isEmpty
    }

    private nonisolated static func statusScript(for player: Player) -> String {
        switch player {
        case .music:
            return """
            tell application "Music"
                if player state is stopped then return ""
                set trackName to name of current track
                set artistName to artist of current track
                set albumName to album of current track
                set stateName to player state as text
                return trackName & "|" & artistName & "|" & albumName & "|" & stateName
            end tell
            """
        case .spotify:
            return """
            tell application "Spotify"
                if player state is stopped then return ""
                set trackName to name of current track
                set artistName to artist of current track
                set albumName to album of current track
                set stateName to player state as text
                return trackName & "|" & artistName & "|" & albumName & "|" & stateName
            end tell
            """
        }
    }

    @discardableResult
    private nonisolated static func execute(_ source: String) -> String? {
        var error: NSDictionary?
        let script = NSAppleScript(source: "with timeout of 5 seconds\n\(source)\nend timeout")
        let result = script?.executeAndReturnError(&error)
        return result?.stringValue
    }

}

private final class AirDropSession: NSObject, NSSharingServiceDelegate {
    let urls: [URL]
    var onFinish: (() -> Void)?

    init?(urls: [URL]) {
        let accessible = urls.filter { $0.startAccessingSecurityScopedResource() }
        guard !accessible.isEmpty else { return nil }
        self.urls = accessible
    }

    private func finish() {
        urls.forEach { $0.stopAccessingSecurityScopedResource() }
        onFinish?()
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { finish() }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) { finish() }
}

struct MusicConnectionSettings: View {
    private var service = MusicService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Open your player, then connect it to show the current track and control playback. macOS may ask for permission.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Apple Music and Spotify provide track information and playback controls. Other audio players are not currently supported by NotchGate.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Connect Spotify") { service.connectSpotify() }
                Button("Connect Apple Music") { service.connectAppleMusic() }
            }
            .disabled(service.refreshInFlight)
            Text(service.connectionStatus).font(.caption).foregroundStyle(.secondary)
            Button("Open Automation Settings") { service.openAutomationSettings() }
            Text("Under Privacy & Security → Automation, expand NotchGate and enable your player. Then click its Connect button again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct MusicWidget: View {
    var service: MusicService
    var accent: Color

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(service.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Text(service.hasTrack ? "\(service.playerName) · \(service.artist)" : (service.automationIssue.map { "Allow \($0) in System Settings → Privacy & Security → Automation" } ?? "Open Music or Spotify to choose a track"))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            Spacer(minLength: 4)
            if !service.hasTrack {
                Button(service.automationIssue == nil ? "Connect \(service.suggestedPlayerName)" : "Open Settings") {
                    if service.automationIssue == nil { service.activate() }
                    else { service.openAutomationSettings() }
                }
                .disabled(service.refreshInFlight)
            } else if service.supportsPlaybackControls {
            Button { service.previous() } label: { Image(systemName: "backward.fill") }
            Button { service.togglePlayPause() } label: {
                Image(systemName: service.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(accent.opacity(0.2), in: Circle())
            }
            Button { service.next() } label: { Image(systemName: "forward.fill") }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct MusicFlyout: View {
    var service: MusicService
    var accent: Color

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(accent)
            Text(service.title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(service.hasTrack ? service.artist : (service.automationIssue.map { "Open Privacy & Security → Automation, expand NotchGate, then enable \($0). Return here and try again." } ?? "Connect your player to show the current track and control playback. macOS may ask for permission."))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
            if !service.hasTrack {
                HStack {
                    if service.automationIssue != nil {
                        Button("Open Automation Settings") { service.openAutomationSettings() }
                    }
                    Button(service.refreshInFlight ? "Connecting…" : (service.automationIssue == nil ? "Connect \(service.suggestedPlayerName)" : "Try Again")) {
                        service.activate()
                    }
                    .disabled(service.refreshInFlight)
                }
            } else if service.supportsPlaybackControls {
            HStack(spacing: 24) {
                Button { service.previous() } label: { Image(systemName: "backward.fill") }
                Button { service.togglePlayPause() } label: {
                    Image(systemName: service.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 38, height: 38)
                        .background(accent.opacity(0.25), in: Circle())
                }
                Button { service.next() } label: { Image(systemName: "forward.fill") }
            }
            .buttonStyle(.plain)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            }
            Menu {
                Button("Open Music") { service.openMusicApp() }
                Button("Open Spotify") { service.openSpotifyApp() }
            } label: {
                Text("Open Player")
            }
            .menuStyle(.borderlessButton)
            .foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            service.refresh()
        }
    }
}

struct FileShelfItem: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var bookmark: Data
    var isDirectory: Bool

    func resolvedURL() -> URL? { SecurityScoped.resolve(bookmark) }
}

@Observable
@MainActor
final class FileShelfStore {
    static let shared = FileShelfStore()
    private let defaultsKey = "notchgate.fileShelf.v1"
    private let maximumItems = 8
    private var airDropSessions: [AirDropSession] = []

    var items: [FileShelfItem] = []

    private init() { load() }

    var isVisible: Bool { LicenseManager.shared.isPro || !items.isEmpty }

    private func requirePro() -> Bool {
        guard LicenseManager.shared.isPro else {
            UtilityWindows.showPricing()
            return false
        }
        return true
    }

    func add(urls: [URL]) {
        guard requirePro() else { return }
        let incoming = urls.compactMap { url -> FileShelfItem? in
            guard FileManager.default.fileExists(atPath: url.path), let bookmark = SecurityScoped.bookmark(for: url) else { return nil }
            return FileShelfItem(id: UUID(), name: url.lastPathComponent, bookmark: bookmark, isDirectory: (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
        }
        for item in incoming {
            items.removeAll { existing in
                guard let a = existing.resolvedURL(), let b = item.resolvedURL() else { return false }
                return a.standardizedFileURL.path == b.standardizedFileURL.path
            }
        }
        items = Array((incoming + items).prefix(maximumItems))
        persist()
    }

    func remove(_ item: FileShelfItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func open(_ item: FileShelfItem) {
        guard requirePro() else { return }
        withAccess(item) { url in _ = NSWorkspace.shared.open(url) }
    }

    func reveal(_ item: FileShelfItem) {
        guard requirePro() else { return }
        withAccess(item) { url in NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    func airDrop(_ item: FileShelfItem? = nil) {
        // Enforce entitlement at the shared action, not just individual buttons.
        guard LicenseManager.shared.isPro else {
            UtilityWindows.showPricing()
            return
        }
        let chosen = item.map { [$0] } ?? items
        let urls = chosen.compactMap { $0.resolvedURL() }
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        guard let session = AirDropSession(urls: urls) else { return }
        airDropSessions.append(session)
        session.onFinish = { [weak self, weak session] in
            guard let self, let session else { return }
            self.airDropSessions.removeAll { $0 === session }
        }
        service.delegate = session
        service.perform(withItems: session.urls)
    }

    func chooseFiles() {
        guard requirePro() else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = "Add to Shelf"
        UtilityWindows.prepareForStoreKit()
        panel.begin { [weak self] response in
            if response == .OK { self?.add(urls: panel.urls) }
            UtilityWindows.restoreAccessoryIfIdle()
        }
    }

    private func withAccess(_ item: FileShelfItem, _ body: (URL) -> Void) {
        guard let url = item.resolvedURL(), let access = ScopedFileAccess(url: url) else { return }
        body(access.url)
        access.end()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([FileShelfItem].self, from: data) else { return }
        items = decoded
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: defaultsKey)
        Persistence.flush()
    }
}

struct FileShelfWidget: View {
    var store: FileShelfStore
    var accent: Color
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down.fill")
                .foregroundStyle(accent)
            if let first = store.items.first {
                Text(first.name)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                if store.items.count > 1 { Text("+\(store.items.count - 1)").foregroundStyle(.white.opacity(0.45)) }
            } else {
                Text(isTargeted ? "Release to add files" : "Drop files here")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            if LicenseManager.shared.isPro {
            Button { store.chooseFiles() } label: { Image(systemName: "plus") }
            Button { store.airDrop() } label: { Image(systemName: "airplayaudio") }
                .help("AirDrop sharing — NotchGate Pro")
                .accessibilityLabel("AirDrop — Pro")
                .disabled(store.items.isEmpty)
            } else {
                Text("Remove saved items").font(.caption)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
        .background((isTargeted ? accent.opacity(0.18) : Color.white.opacity(0.06)), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
            guard LicenseManager.shared.isPro else { return false }
            for provider in providers {
                _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                    guard let object, let url = object as? NSURL else { return }
                    let fileURL = url as URL
                    Task { @MainActor in store.add(urls: [fileURL]) }
                }
            }
            return true
        }
        .contextMenu {
            ForEach(store.items) { item in
                if LicenseManager.shared.isPro {
                Button(item.name) { store.open(item) }
                Button("Send \(item.name) with AirDrop — Pro") { store.airDrop(item) }
                Button("Show in Finder") { store.reveal(item) }
                }
                Button("Remove from Shelf") { store.remove(item) }
            }
        }
    }
}

struct FileShelfFlyout: View {
    var store: FileShelfStore
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !store.isVisible {
                Text("File shelf requires NotchGate Pro.")
            } else if store.items.isEmpty {
                ContentUnavailableView("File shelf is empty", systemImage: "tray", description: Text("Drop files here or choose Add Files."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.items) { item in
                            HStack(spacing: 8) {
                                Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                                    .foregroundStyle(accent)
                                Text(item.name).lineLimit(1)
                                Spacer()
                                if LicenseManager.shared.isPro {
                                Button { store.airDrop(item) } label: { Image(systemName: "airplayaudio") }
                                    .buttonStyle(.plain)
                                    .help("AirDrop sharing — NotchGate Pro")
                                    .accessibilityLabel("AirDrop \(item.name) — Pro")
                                Button { store.open(item) } label: { Image(systemName: "arrow.up.right.square") }
                                    .buttonStyle(.plain)
                                }
                                Button { store.remove(item) } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain)
                                    .help("Remove from Shelf — keeps the original file")
                                    .accessibilityLabel("Remove \(item.name) from Shelf")
                            }
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))
                            .padding(8)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
            if LicenseManager.shared.isPro {
            HStack {
                Button("Add Files…") { store.chooseFiles() }
                Spacer()
                Button("AirDrop All — Pro") { store.airDrop() }
                    .disabled(store.items.isEmpty)
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
            }
        }
    }
}
