import AppKit

/// Marks a window as present on every Space, including Full Screen.
/// Does not change window level — that broke hover last time.
enum OverlaySpace {
    static func stickToAllSpaces(_ window: NSWindow?) {
        guard let window else { return }
        // Public AppKit behavior covers the supported Spaces and Full Screen
        // cases without relying on undocumented window-server symbols.
        window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle])
    }
}
