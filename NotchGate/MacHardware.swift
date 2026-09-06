import AppKit
import Darwin
import Foundation

/// Built-in display facts for MacBooks so the island can match the camera
/// housing instead of a one-size overlay.
enum MacHardware {
    static let modelIdentifier: String = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }()

    static var isLaptop: Bool {
        modelIdentifier.hasPrefix("MacBook")
    }

    static func isBuiltIn(_ screen: NSScreen) -> Bool {
        CGDisplayIsBuiltin(displayID(screen)) != 0
    }

    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Last measured camera cutout per display. Full Screen often drops
    /// `auxiliaryTopLeftArea`; keep the hardware size so the island doesn't jump.
    static var cutoutCache: [CGDirectDisplayID: NSRect] = [:]

    /// When AppKit cannot see a cutout, size the fake island like this MacBook.
    static func fallbackNotch(on screen: NSScreen) -> NSSize {
        let scale = max(screen.backingScaleFactor, 1)
        func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let safe = screen.safeAreaInsets.top
        let height = snap(max(safe > 8 ? safe : 32, 32))
        let width: CGFloat
        switch screen.frame.width {
        case 1800...: width = 200
        case 1512...: width = 190
        case 1440...: width = 184
        default: width = isLaptop ? 172 : 160
        }
        return NSSize(width: snap(width), height: height)
    }
}
