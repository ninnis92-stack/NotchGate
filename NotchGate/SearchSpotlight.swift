import Foundation

enum SpotlightQueryString {
    static func make(from text: String, scope: SearchScope) -> String {
        let tokens = text.split { $0.isWhitespace || $0.isNewline }.map(String.init).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return "" }
        let includeContent = tokens.contains { $0.count >= 2 }
        var query = tokens.map { tokenClause($0, includeContent: includeContent && $0.count >= 2) }.joined(separator: " && ")
        switch scope {
        case .apps:
            query = "(\(query)) && kMDItemContentTypeTree == \"com.apple.application-bundle\""
        case .files:
            query = "(\(query)) && kMDItemContentTypeTree != \"com.apple.application-bundle\""
        case .thisMac, .web:
            break
        }
        return query
    }

    private static func tokenClause(_ token: String, includeContent: Bool) -> String {
        let prefix = prefixTerm(token)
        let contains = containsTerm(token)
        var clauses = [
            "kMDItemDisplayName == \(prefix)",
            "kMDItemDisplayName == \(contains)",
            "kMDItemFSName == \(prefix)",
            "kMDItemTitle == \(prefix)",
            "kMDItemTitle == \(contains)"
        ]
        if includeContent {
            clauses.append(contentsOf: [
                "kMDItemTextContent == \(prefix)",
                "kMDItemAuthors == \(prefix)",
                "kMDItemKeywords == \(prefix)",
                "kMDItemWhereFroms == \(prefix)",
                "kMDItemAlbum == \(prefix)",
                "kMDItemOrganization == \(prefix)",
                "kMDItemComment == \(prefix)",
                "kMDItemHeadline == \(prefix)",
                "kMDItemSubject == \(prefix)"
            ])
        }
        return "(" + clauses.joined(separator: " || ") + ")"
    }

    private static func prefixTerm(_ token: String) -> String {
        "\"\(escape(token))*\"cdw"
    }

    private static func containsTerm(_ token: String) -> String {
        "\"*\(escape(token))*\"cd"
    }

    static func escape(_ token: String) -> String {
        token
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "?", with: "\\?")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }
}
