import AppKit
import Darwin

/// Marks a window as present on every Space, including Full Screen.
/// Does not change window level — that broke hover last time.
enum OverlaySpace {
    /// `kCGSOnAllWorkspacesTagBit` (1 << 10) and `kCGSStickyTagBit` (1 << 11).
    private static let spaceBits: Int32 = (1 << 10) | (1 << 11)
    private static let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    static func stickToAllSpaces(_ window: NSWindow?) {
        guard let window else { return }
        if window.windowNumber <= 0 {
            window.orderFrontRegardless()
        }
        let wid = Int32(window.windowNumber)
        guard wid > 0, let cid = connection(), let setTags else { return }

        // Last argument is tag word width in bits (32). A 64-width call with a
        // two-Int32 buffer can smash the stack on some OS versions.
        var tags = [spaceBits, Int32(0)]
        tags.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = setTags(cid, wid, base, 32)
        }
    }

    private static func connection() -> Int32? {
        if let fn = symbol("SLSMainConnectionID", as: (@convention(c) () -> Int32).self) {
            let id = fn()
            if id != 0 { return id }
        }
        if let fn = symbol("CGSMainConnectionID", as: (@convention(c) () -> Int32).self) {
            let id = fn()
            if id != 0 { return id }
        }
        return nil
    }

    private static var setTags: (@convention(c) (Int32, Int32, UnsafePointer<Int32>, Int32) -> Int32)? {
        symbol("SLSSetWindowTags", as: (@convention(c) (Int32, Int32, UnsafePointer<Int32>, Int32) -> Int32).self)
            ?? symbol("CGSSetWindowTags", as: (@convention(c) (Int32, Int32, UnsafePointer<Int32>, Int32) -> Int32).self)
    }

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let sky, let raw = dlsym(sky, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }
}
