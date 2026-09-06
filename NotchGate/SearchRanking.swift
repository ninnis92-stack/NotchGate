import Foundation

enum SearchMatchRank: Int, Comparable {
    case exact = 0
    case prefix = 1
    case wordPrefix = 2
    case initials = 3
    case contains = 4

    static func < (lhs: SearchMatchRank, rhs: SearchMatchRank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum SearchMatcher {
    static func folded(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    /// Spotlight-style name matching: exact, prefix, word prefix, initials, then substring.
    static func rank(name: String, query: String) -> SearchMatchRank? {
        let q = folded(query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        let n = folded(name)
        if n == q { return .exact }
        if n.hasPrefix(q) { return .prefix }
        let words = n.split { !$0.isLetter && !$0.isNumber }
        if words.contains(where: { $0.hasPrefix(q) }) { return .wordPrefix }
        let initials = words.map { String($0.prefix(1)) }.joined()
        if q.count >= 2, initials.hasPrefix(q) { return .initials }
        if n.contains(q) { return .contains }
        return nil
    }
}
