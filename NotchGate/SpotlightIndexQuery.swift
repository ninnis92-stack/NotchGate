import CoreServices
import Foundation

/// Runs a Spotlight MDQuery on a background queue so results include names and file contents.
final class SpotlightIndexQuery: @unchecked Sendable {
    var onHits: @MainActor ([SearchHit]) -> Void = { _ in }

    private let queue = DispatchQueue(label: "notchgate.spotlight-search", qos: .userInitiated)
    private var generation = 0

    func start(text: String, scope: SearchScope) {
        generation += 1
        let gen = generation
        let source = SpotlightQueryString.make(from: text, scope: scope)
        queue.async { [weak self] in
            guard let self, gen == self.generation else { return }
            let hits = Self.execute(source, query: text)
            guard gen == self.generation else { return }
            DispatchQueue.main.async {
                guard gen == self.generation else { return }
                Task { @MainActor in
                    self.onHits(hits)
                }
            }
        }
    }

    func stop() {
        generation += 1
    }

    private static func execute(_ source: String, query: String) -> [SearchHit] {
        guard !source.isEmpty else { return [] }
        let attributes = [
            kMDItemPath,
            kMDItemDisplayName,
            kMDItemFSName,
            kMDItemTitle,
            kMDItemKind,
            kMDItemContentTypeTree,
            kMDItemLastUsedDate
        ] as CFArray
        let sort = [kMDItemLastUsedDate] as CFArray
        guard let mdq = MDQueryCreate(kCFAllocatorDefault, source as CFString, attributes, sort) else {
            return []
        }
        MDQuerySetMaxCount(mdq, 40)
        MDQuerySetSearchScope(mdq, [kMDQueryScopeComputer, kMDQueryScopeHome] as CFArray, 0)
        guard MDQueryExecute(mdq, CFOptionFlags(kMDQuerySynchronous.rawValue)) else {
            return []
        }
        return collect(mdq, query: query)
    }

    private static func collect(_ mdq: MDQuery, query: String) -> [SearchHit] {
        let count = MDQueryGetResultCount(mdq)
        var hits: [SearchHit] = []
        hits.reserveCapacity(min(Int(count), 40))
        for index in 0..<count {
            guard let pointer = MDQueryGetResultAtIndex(mdq, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(pointer).takeUnretainedValue()
            guard let path = stringAttribute(item, kMDItemPath) else { continue }
            let url = URL(fileURLWithPath: path)
            let name = stringAttribute(item, kMDItemDisplayName)
                ?? stringAttribute(item, kMDItemTitle)
                ?? url.deletingPathExtension().lastPathComponent
            let kindLabel = stringAttribute(item, kMDItemKind)
            let types = stringListAttribute(item, kMDItemContentTypeTree)
            let isApp = url.pathExtension.lowercased() == "app"
                || types.contains("com.apple.application-bundle")
            let folder = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
            let nameMatched = SearchMatcher.rank(name: name, query: query) != nil
                || (stringAttribute(item, kMDItemFSName).map { SearchMatcher.rank(name: $0, query: query) != nil } ?? false)
                || (stringAttribute(item, kMDItemTitle).map { SearchMatcher.rank(name: $0, query: query) != nil } ?? false)
            hits.append(
                SearchHit(
                    id: path,
                    title: name,
                    subtitle: kindLabel ?? (isApp ? "Application" : folder),
                    url: url,
                    kind: isApp ? .app : .file,
                    nameMatched: nameMatched
                )
            )
        }
        return hits
    }

    private static func stringAttribute(_ item: MDItem, _ name: CFString) -> String? {
        guard let value = MDItemCopyAttribute(item, name) else { return nil }
        return value as? String
    }

    private static func stringListAttribute(_ item: MDItem, _ name: CFString) -> [String] {
        guard let value = MDItemCopyAttribute(item, name) else { return [] }
        if let list = value as? [String] { return list }
        if let string = value as? String { return [string] }
        return []
    }
}
