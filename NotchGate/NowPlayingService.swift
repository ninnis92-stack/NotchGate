import AppKit
import Foundation

struct NowPlayingItem: Equatable, Identifiable {
    var bundleIdentifier: String
    var title: String
    var artist: String
    var album: String
    var appName: String
    var isPlaying: Bool
    var artwork: NSImage?

    var id: String { bundleIdentifier }

    var line: String {
        if artist.isEmpty { return title }
        return "\(title) · \(artist)"
    }

    var menuTitle: String {
        if title.isEmpty { return appName }
        return "\(appName) — \(title)"
    }

    static func == (lhs: NowPlayingItem, rhs: NowPlayingItem) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.appName == rhs.appName
            && lhs.isPlaying == rhs.isPlaying
            && lhs.artwork === rhs.artwork
    }
}

@Observable
@MainActor
final class NowPlayingService {
    private static let selectionKey = "notchgate.nowPlaying.selectedSource"

    var sources: [NowPlayingItem] = []
    var item: NowPlayingItem?
    var selectedSourceID: String = UserDefaults.standard.string(forKey: NowPlayingService.selectionKey) ?? ""

    private var timer: Timer?
    private var started = false
    private var refreshGeneration = 0
    private var emptyStreak = 0
    private var refreshWork: DispatchWorkItem?

    func start() {
        guard !started else { return }
        started = true
        listenForPlayerChanges()
        refresh()
        let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            guard let service = self else { return }
            Task { @MainActor in
                service.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func select(_ source: NowPlayingItem) {
        selectedSourceID = source.id
        UserDefaults.standard.set(source.id, forKey: Self.selectionKey)
        item = source
    }

    func openPlayer() {
        let id = item?.bundleIdentifier ?? ""
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        let name = item?.appName ?? ""
        let fallback: [String: String] = [
            "Music": "com.apple.Music",
            "Spotify": "com.spotify.client",
            "Pandora": "com.pandora.desktop",
            "Podcasts": "com.apple.podcasts",
            "TV": "com.apple.TV",
            "Amazon Music": "com.amazon.music",
            "TIDAL": "com.tidal.desktop",
            "Deezer": "com.deezer.deezer"
        ]
        if let bundle = fallback.first(where: { name.localizedCaseInsensitiveContains($0.key) })?.value,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func refresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performRefresh()
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func performRefresh() {
        refreshGeneration += 1
        let generation = refreshGeneration
        Task.detached { [weak self] in
            let music = AppleScriptNowPlaying.fetchMusic()
            let spotify = AppleScriptNowPlaying.fetchSpotify()
            await MainActor.run {
                guard let service = self, generation == service.refreshGeneration else { return }
                service.publish(remote: nil, music: music, spotify: spotify)
            }
        }
    }

    private func listenForPlayerChanges() {
        let refreshOnChange = { [weak self] in
            Task { @MainActor in
                self?.refresh()
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { _ in
            refreshOnChange()
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { _ in
            refreshOnChange()
        }
    }

    private func publish(
        remote: NowPlayingItem?,
        music: NowPlayingItem?,
        spotify: NowPlayingItem?
    ) {
        var list: [NowPlayingItem] = []
        if var music {
            if let remote, remote.matches(bundle: "com.apple.Music", names: ["Music"]), music.artwork == nil {
                music.artwork = remote.artwork
            }
            list.append(music)
        }
        if var spotify {
            if let remote, remote.matches(bundle: "com.spotify.client", names: ["Spotify"]), spotify.artwork == nil {
                spotify.artwork = remote.artwork
            }
            list.append(spotify)
        }
        if let remote, !remote.isBrowserSource, !list.contains(where: { $0.id == remote.id || $0.matches(item: remote) }) {
            list.append(remote)
        }

        if list.isEmpty {
            emptyStreak += 1
            if emptyStreak >= 4 {
                item = nil
                sources = []
            }
            return
        }

        emptyStreak = 0
        sources = list
        if let selected = list.first(where: { $0.id == selectedSourceID }) {
            item = selected
            return
        }
        let fallback = list.first(where: \.isPlaying) ?? list.first
        selectedSourceID = fallback?.id ?? ""
        if !selectedSourceID.isEmpty {
            UserDefaults.standard.set(selectedSourceID, forKey: Self.selectionKey)
        }
        item = fallback
    }
}

private extension NowPlayingItem {
    func matches(bundle: String, names: [String]) -> Bool {
        if bundleIdentifier.caseInsensitiveCompare(bundle) == .orderedSame { return true }
        return names.contains { appName.caseInsensitiveCompare($0) == .orderedSame }
    }

    func matches(item: NowPlayingItem) -> Bool {
        if !bundleIdentifier.isEmpty, bundleIdentifier.caseInsensitiveCompare(item.bundleIdentifier) == .orderedSame {
            return true
        }
        return !appName.isEmpty && appName.caseInsensitiveCompare(item.appName) == .orderedSame
    }

    var isBrowserSource: Bool {
        let id = bundleIdentifier.lowercased()
        let name = appName.lowercased()
        let hints = [
            "safari", "chrome", "firefox", "webkit", "edgemac",
            "brave", "opera", "vivaldi", "chromium", "orion", "thebrowser"
        ]
        if hints.contains(where: { id.contains($0) }) { return true }
        if name == "safari" || name == "google chrome" || name == "chrome"
            || name == "firefox" || name == "brave" || name == "brave browser"
            || name == "microsoft edge" || name == "arc" || name == "opera"
            || name == "vivaldi" || name.contains("browser") {
            return true
        }
        return false
    }
}

private enum AppleScriptNowPlaying {
    nonisolated static func fetchMusic() -> NowPlayingItem? {
        guard isRunning("com.apple.Music") else { return nil }
        return parse(
            script: """
            tell application "Music"
                if player state is stopped then return "NO"
                set playingFlag to player state is playing
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                return (playingFlag as text) & "\t" & trackName & "\t" & trackArtist & "\t" & trackAlbum
            end tell
            """,
            appName: "Music",
            bundleIdentifier: "com.apple.Music"
        )
    }

    nonisolated static func fetchSpotify() -> NowPlayingItem? {
        guard isRunning("com.spotify.client") else { return nil }
        return parse(
            script: """
            tell application "Spotify"
                if player state is stopped then return "NO"
                set playingFlag to player state is playing
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                return (playingFlag as text) & "\t" & trackName & "\t" & trackArtist & "\t" & trackAlbum
            end tell
            """,
            appName: "Spotify",
            bundleIdentifier: "com.spotify.client"
        )
    }

    nonisolated private static func isRunning(_ bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    nonisolated private static func parse(script: String, appName: String, bundleIdentifier: String) -> NowPlayingItem? {
        guard let raw = run(script), raw != "NO", !raw.isEmpty else { return nil }
        let parts = raw.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return nil }
        let playing = parts[0].localizedCaseInsensitiveContains("true")
        let title = parts[safe: 1] ?? "Now Playing"
        let artist = parts[safe: 2] ?? ""
        let album = parts[safe: 3] ?? ""
        guard !title.isEmpty else { return nil }
        return NowPlayingItem(
            bundleIdentifier: bundleIdentifier,
            title: title,
            artist: artist,
            album: album,
            appName: appName,
            isPlaying: playing,
            artwork: nil
        )
    }

    @discardableResult
    nonisolated private static func run(_ source: String) -> String? {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        let result = script?.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return result?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
