import AppKit
import Foundation
import SwiftUI

struct SearchHit: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let url: URL?
    let kind: Kind

    enum Kind {
        case file
        case app
        case web
        case calculator
        case history
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

    private var metadata = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []
    private var keyMonitor: Any?

    func start() {
        loadHistory()
        installQueryObserver()
        installShortcut()
    }

    func stop() {
        metadata.stop()
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    func open() {
        isOpen = true
        SpotlightPanelController.shared.show(service: self)
    }

    func search(_ text: String) {
        query = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = historyHits()
            return
        }
        var hits: [SearchHit] = []
        if let calc = evaluateCalculator(trimmed) {
            hits.append(calc)
        }
        if NotchCustomization.shared.searchScope == .web {
            hits.append(webHit(trimmed))
        }
        results = hits
        runSpotlight(trimmed)
    }

    func submit(_ hit: SearchHit) {
        remember(query)
        switch hit.kind {
        case .web:
            if let url = hit.url { NSWorkspace.shared.open(url) }
        case .calculator:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hit.title, forType: .string)
        default:
            if let url = hit.url {
                NSWorkspace.shared.open(url)
            }
        }
        isOpen = false
        SpotlightPanelController.shared.hide()
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

    private func runSpotlight(_ text: String) {
        metadata.stop()
        metadata.searchScopes = [NSMetadataQueryLocalComputerScope]
        let scope = NotchCustomization.shared.searchScope
        let pattern = "*\(text)*"
        let nameMatch = NSPredicate(format: "kMDItemDisplayName LIKE[cd] %@", pattern)
        if scope == .apps {
            metadata.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "kMDItemContentTypeTree == %@", "com.apple.application-bundle"),
                nameMatch
            ])
        } else if scope == .files {
            metadata.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "kMDItemContentTypeTree != %@", "com.apple.application-bundle"),
                nameMatch
            ])
        } else {
            metadata.predicate = nameMatch
        }
        metadata.start()
    }

    private func installQueryObserver() {
        guard observers.isEmpty else { return }
        let finished = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: metadata,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.ingestQuery() }
        }
        let updated = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: metadata,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.ingestQuery() }
        }
        observers = [finished, updated]
    }

    private func ingestQuery() {
        metadata.disableUpdates()
        defer { metadata.enableUpdates() }
        let scope = NotchCustomization.shared.searchScope
        var hits: [SearchHit] = results.filter { $0.kind == .calculator || $0.kind == .web }
        let items = (0..<min(metadata.resultCount, 12)).compactMap { metadata.result(at: $0) as? NSMetadataItem }
        for item in items {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            let name = (item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let isApp = url.pathExtension.lowercased() == "app"
            if scope == .apps, !isApp { continue }
            if scope == .files, isApp { continue }
            hits.append(
                SearchHit(
                    id: path,
                    title: name,
                    subtitle: url.deletingLastPathComponent().path,
                    url: url,
                    kind: isApp ? .app : .file
                )
            )
        }
        results = hits
    }

    private func webHit(_ text: String) -> SearchHit {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+")
        let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
        let url = URL(string: "https://www.google.com/search?q=\(encoded)")
        return SearchHit(id: "web-\(text)", title: "Search the web", subtitle: text, url: url, kind: .web)
    }

    private func evaluateCalculator(_ text: String) -> SearchHit? {
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/()% ")
        guard text.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
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
            guard NotchCustomization.shared.showSearch else { return event }
            guard NotchCustomization.shared.searchTrigger == .keyboard else { return event }
            if event.modifierFlags.contains(.command),
               event.modifierFlags.contains(.shift),
               event.charactersIgnoringModifiers?.lowercased() == "f" {
                self?.open()
                return nil
            }
            return event
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
