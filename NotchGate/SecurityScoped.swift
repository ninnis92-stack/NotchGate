import AppKit
import Darwin
import Foundation

enum RealUserHome {
    static var url: URL {
        guard let pw = getpwuid(getuid()) else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir), isDirectory: true)
    }
}

enum SecurityScoped {
    static func bookmark(for url: URL) -> Data? {
        (try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )) ?? (try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ))
    }

    static func resolve(_ data: Data) -> URL? {
        var stale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) {
            return url
        }
        return try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }
}

struct ScopedFileAccess {
    let url: URL
    private let didStart: Bool

    init?(url: URL) {
        self.url = url
        didStart = url.startAccessingSecurityScopedResource()
        guard FileManager.default.fileExists(atPath: url.path) else {
            if didStart { url.stopAccessingSecurityScopedResource() }
            return nil
        }
    }

    func end() {
        if didStart { url.stopAccessingSecurityScopedResource() }
    }
}
