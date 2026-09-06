import AppKit
import Foundation
import SwiftUI

struct SearchHit: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let url: URL?
    let kind: Kind
    var nameMatched: Bool = true

    enum Kind {
        case file
        case app
        case web
        case calculator
        case history
    }
}

@MainActor
final class InstalledAppIndex {
    static let shared = InstalledAppIndex()

    private(set) var apps: [(name: String, url: URL)] = []
    private var loaded = false

    func refreshIfNeeded() {
        if loaded, !apps.isEmpty { return }
        refresh()
    }

    func refresh() {
        let fm = FileManager.default
        var roots = fm.urls(for: .applicationDirectory, in: [.systemDomainMask, .localDomainMask, .userDomainMask])
        roots.append(contentsOf: [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities")
        ])

        var seen = Set<String>()
        var found: [(String, URL)] = []
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.localizedNameKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in items where url.pathExtension.lowercased() == "app" {
                let path = url.standardizedFileURL.path
                if seen.contains(path) { continue }
                seen.insert(path)
                let name = (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName)
                    ?? url.deletingPathExtension().lastPathComponent
                found.append((name, url))
            }
        }
        apps = found
        loaded = true
    }

    func matches(query: String, limit: Int) -> [SearchHit] {
        refreshIfNeeded()
        return apps.compactMap { name, url -> (SearchMatchRank, SearchHit)? in
            guard let rank = SearchMatcher.rank(name: name, query: query) else { return nil }
            return (
                rank,
                SearchHit(
                    id: url.path,
                    title: name,
                    subtitle: "Application",
                    url: url,
                    kind: .app
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
            return lhs.1.title.localizedCaseInsensitiveCompare(rhs.1.title) == .orderedAscending
        }
        .prefix(limit)
        .map(\.1)
    }
}

@Observable
@MainActor
final class SearchService {
    static let shared = SearchService()

    var query = ""
    var results: [SearchHit] = []
    var history: [String] = []
    var isOpen = false
    var selectedIndex = 0

    private let spotlight = SpotlightIndexQuery()
    private var keyMonitor: Any?
    private var panelKeyMonitor: Any?
    private var searchWork: DispatchWorkItem?
    private var fileHits: [SearchHit] = []

    func start() {
        loadHistory()
        installShortcut()
        InstalledAppIndex.shared.refreshIfNeeded()
        spotlight.onHits = { [weak self] hits in
            guard let self else { return }
            self.fileHits = hits
            self.publish()
        }
    }

    func stop() {
        searchWork?.cancel()
        spotlight.stop()
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        removePanelKeys()
    }

    func open() {
        isOpen = true
        installPanelKeys()
        SpotlightPanelController.shared.show(service: self)
        search(query)
    }

    func close() {
        searchWork?.cancel()
        spotlight.stop()
        removePanelKeys()
        isOpen = false
        query = ""
        fileHits = []
        results = historyHits()
        selectedIndex = 0
        SpotlightPanelController.shared.hide()
    }

    func search(_ text: String) {
        query = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        fileHits = []
        if trimmed.isEmpty {
            searchWork?.cancel()
            spotlight.stop()
            publish()
            return
        }
        publish()
        searchWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.runSpotlight(trimmed)
        }
        searchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + results.count) % results.count
    }

    func submitSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        let hit = results[selectedIndex]
        if hit.kind == .history {
            search(hit.title)
            return
        }
        submit(hit)
    }

    func revealSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        reveal(results[selectedIndex])
    }

    func submit(_ hit: SearchHit) {
        remember(query.isEmpty ? hit.title : query)
        switch hit.kind {
        case .web:
            if let url = hit.url { NSWorkspace.shared.open(url) }
        case .calculator:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hit.title, forType: .string)
        case .history:
            search(hit.title)
            return
        default:
            if let url = hit.url {
                NSWorkspace.shared.open(url)
            }
        }
        close()
    }

    func reveal(_ hit: SearchHit) {
        guard let url = hit.url else { return }
        remember(query)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        close()
    }

    func remember(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NotchCustomization.shared.searchRememberHistory, !trimmed.isEmpty else { return }
        history.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        history.insert(trimmed, at: 0)
        if history.count > 20 { history = Array(history.prefix(20)) }
        saveHistory()
    }

    func historyHits() -> [SearchHit] {
        guard NotchCustomization.shared.searchShowHistory else { return [] }
        return history.prefix(8).map {
            SearchHit(id: "h-\($0)", title: $0, subtitle: "Recent", url: nil, kind: .history)
        }
    }

    private func publish() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedID = results.indices.contains(selectedIndex) ? results[selectedIndex].id : nil
        results = compose(query: trimmed, files: fileHits)
        if let selectedID, let index = results.firstIndex(where: { $0.id == selectedID }) {
            selectedIndex = index
        } else {
            selectedIndex = 0
        }
    }

    private func compose(query: String, files: [SearchHit]) -> [SearchHit] {
        if query.isEmpty { return historyHits() }

        let scope = NotchCustomization.shared.searchScope
        var hits: [SearchHit] = []

        if let calc = evaluateCalculator(query) {
            hits.append(calc)
        }

        if scope != .web {
            var rest: [SearchHit] = []
            if scope != .files {
                rest.append(contentsOf: InstalledAppIndex.shared.matches(query: query, limit: 8))
            }
            let seen = Set(rest.map(\.id))
            rest.append(contentsOf: files.filter { !seen.contains($0.id) })
            rest.sort { lhs, rhs in
                if lhs.kind == .app && rhs.kind != .app { return true }
                if lhs.kind != .app && rhs.kind == .app { return false }
                if lhs.nameMatched != rhs.nameMatched { return lhs.nameMatched && !rhs.nameMatched }
                return false
            }
            hits.append(contentsOf: rest.prefix(24))
        }

        if scope == .web || scope == .thisMac {
            hits.append(webHit(query))
        } else if scope == .files || scope == .apps, hits.isEmpty {
            hits.append(webHit(query))
        }

        return hits
    }

    private func runSpotlight(_ text: String) {
        let scope = NotchCustomization.shared.searchScope
        guard scope != .web else { return }
        spotlight.start(text: text, scope: scope)
    }

    private func webHit(_ text: String) -> SearchHit {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+")
        let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
        let url = URL(string: "https://www.google.com/search?q=\(encoded)")
        return SearchHit(id: "web-\(text)", title: text, subtitle: "Search the web", url: url, kind: .web)
    }

    private func evaluateCalculator(_ text: String) -> SearchHit? {
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/()% ")
        guard text.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        guard text.contains(where: { "+-*/%".contains($0) }) else { return nil }
        let expression = NSExpression(format: text)
        guard let number = expression.expressionValue(with: nil, context: nil) as? NSNumber else { return nil }
        return SearchHit(
            id: "calc-\(text)",
            title: number.stringValue,
            subtitle: "Calculator",
            url: nil,
            kind: .calculator
        )
    }

    private func installShortcut() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard NotchCustomization.shared.assignsSearch else { return event }
            if event.modifierFlags.contains(.command),
               event.modifierFlags.contains(.shift),
               event.charactersIgnoringModifiers?.lowercased() == "f" {
                self?.open()
                return nil
            }
            return event
        }
    }

    private func installPanelKeys() {
        guard panelKeyMonitor == nil else { return }
        panelKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isOpen else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            switch event.keyCode {
            case 125:
                self.moveSelection(1)
                return nil
            case 126:
                self.moveSelection(-1)
                return nil
            case 53:
                self.close()
                return nil
            case 36 where flags.contains(.command):
                self.revealSelected()
                return nil
            default:
                return event
            }
        }
    }

    private func removePanelKeys() {
        if let monitor = panelKeyMonitor {
            NSEvent.removeMonitor(monitor)
            panelKeyMonitor = nil
        }
    }

    private var historyURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchGate/SavedSearches", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("history.json")
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let saved = try? JSONDecoder().decode([String].self, from: data) else { return }
        history = saved
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }
}
