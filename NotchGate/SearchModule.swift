import AppKit
import Foundation
import SwiftUI

struct SearchHit: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let url: URL?
    let kind: Kind
    let isDirectory: Bool
    let size: Int64?
    let modified: Date?

    init(id: String, title: String, subtitle: String, url: URL?, kind: Kind, isDirectory: Bool = false, size: Int64? = nil, modified: Date? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.kind = kind
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
    }

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

    func toggle() {
        if SpotlightPanelController.shared.isVisible {
            isOpen = false
            SpotlightPanelController.shared.hide()
        } else {
            start()
            open()
        }
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

    func setScope(_ scope: SearchScope) {
        NotchCustomization.shared.searchScope = scope
        search(query)
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

    func reveal(_ hit: SearchHit) {
        guard let url = hit.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
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
        let contentMatch = NSPredicate(format: "kMDItemTextContent LIKE[cd] %@", pattern)
        let finderMatch = NSCompoundPredicate(orPredicateWithSubpredicates: [nameMatch, contentMatch])
        if scope == .apps {
            metadata.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "kMDItemContentTypeTree == %@", "com.apple.application-bundle"),
                nameMatch
            ])
        } else if scope == .files {
            metadata.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "kMDItemContentTypeTree != %@", "com.apple.application-bundle"),
                finderMatch
            ])
        } else {
            metadata.predicate = finderMatch
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
            Task { @MainActor [weak self] in
                self?.ingestQuery()
            }
        }
        let updated = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: metadata,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.ingestQuery()
            }
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
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            hits.append(
                SearchHit(
                    id: path,
                    title: name,
                    subtitle: url.deletingLastPathComponent().path,
                    url: url,
                    kind: isApp ? .app : .file,
                    isDirectory: values?.isDirectory ?? false,
                    size: values?.fileSize.map(Int64.init),
                    modified: values?.contentModificationDate
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
        var parser = CalculatorParser(text)
        guard let value = parser.parse() else { return nil }
        return SearchHit(
            id: "calc-\(text)",
            title: value.formatted(.number.precision(.fractionLength(0...8))),
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

    private var historyURL: URL {
        let folder = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
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

private struct CalculatorParser {
    private let characters: [Character]
    private var index = 0

    init(_ text: String) {
        characters = Array(text)
    }

    mutating func parse() -> Double? {
        guard let value = parseExpression() else { return nil }
        skipWhitespace()
        guard index == characters.count, value.isFinite else { return nil }
        return value
    }

    private mutating func parseExpression() -> Double? {
        guard var value = parseTerm() else { return nil }
        while true {
            skipWhitespace()
            guard let operation = current else { return value }
            guard operation == "+" || operation == "-" else { return value }
            index += 1
            guard let rhs = parseTerm() else { return nil }
            value = operation == "+" ? value + rhs : value - rhs
            guard value.isFinite else { return nil }
        }
    }

    private mutating func parseTerm() -> Double? {
        guard var value = parseFactor() else { return nil }
        while true {
            skipWhitespace()
            guard let operation = current else { return value }
            guard operation == "*" || operation == "/" || operation == "%" else { return value }
            index += 1
            guard let rhs = parseFactor(), rhs != 0 else { return nil }
            switch operation {
            case "*": value *= rhs
            case "/": value /= rhs
            default: value.formTruncatingRemainder(dividingBy: rhs)
            }
            guard value.isFinite else { return nil }
        }
    }

    private mutating func parseFactor() -> Double? {
        skipWhitespace()
        if current == "+" || current == "-" {
            let negative = current == "-"
            index += 1
            guard let value = parseFactor() else { return nil }
            return negative ? -value : value
        }
        return parsePrimary()
    }

    private mutating func parsePrimary() -> Double? {
        skipWhitespace()
        if current == "(" {
            index += 1
            guard let value = parseExpression() else { return nil }
            skipWhitespace()
            guard current == ")" else { return nil }
            index += 1
            return value
        }

        let start = index
        var hasDigit = false
        var hasDecimal = false
        while let character = current {
            if character.isNumber {
                hasDigit = true
                index += 1
            } else if character == ".", !hasDecimal {
                hasDecimal = true
                index += 1
            } else {
                break
            }
        }
        guard hasDigit else { return nil }
        return Double(String(characters[start..<index]))
    }

    private var current: Character? {
        guard characters.indices.contains(index) else { return nil }
        return characters[index]
    }

    private mutating func skipWhitespace() {
        while current?.isWhitespace == true {
            index += 1
        }
    }
}
