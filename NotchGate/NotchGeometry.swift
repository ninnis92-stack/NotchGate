import AppKit
import CoreGraphics
import SwiftUI

struct NotchIslandShape: Shape {
    var bottomRadius: CGFloat = NotchGeometry.cornerRadius

    func path(in rect: CGRect) -> Path {
        let br = min(bottomRadius, rect.height * 0.9, rect.width * 0.2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(
            center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
            radius: br,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + br, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + br, y: rect.maxY - br),
            radius: br,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    /// Global X origin of the hardware cutout, not the screen midpoint.
    let notchMinX: CGFloat
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let hasNotch: Bool
    /// When true, collapsed Full Screen hides shoulder widgets but never the shoulder shape.
    let hidesCollapsedShoulders: Bool
    let isImmersive: Bool
    let isMenuBarHidden: Bool
    let backingScale: CGFloat

    /// Frontmost app while geometry was last sampled. Not part of Equatable layout.
    private(set) static var frontmostBundleID: String?

    static let cornerRadius: CGFloat = 16
    static let leftShoulderWidth: CGFloat = 124
    static let rightShoulderWidth: CGFloat = 62
    /// Gap between glance content and the camera cutout so text cannot sit under it.
    static let shoulderNotchGutter: CGFloat = 10
    static let settingsGearSize: CGFloat = 22
    static let settingsGearTrailing: CGFloat = 12
    static let settingsGearGap: CGFloat = 8
    static var settingsReservedWidth: CGFloat { settingsGearTrailing + settingsGearSize + settingsGearGap }
    static let chin: CGFloat = 10
    static let expandedHeight: CGFloat = 236
    static let panelWidth: CGFloat = 420
    /// Extra hit area while expanded so the pointer doesn't flicker off the edge.
    static let expandedHoldPad: CGFloat = 2

    /// Bottom rounding for the collapsed island. Flush Full Screen uses a tighter
    /// radius so the overlay cannot visually drop into app content.
    var collapsedBottomRadius: CGFloat {
        min(8, max(notchHeight * 0.22, 4))
    }

    var notchCenterX: CGFloat { notchMinX + notchWidth / 2 }

    var notchRect: NSRect {
        NSRect(
            x: notchMinX,
            y: screenFrame.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )
    }

    var wideCollapsedSize: NSSize {
        NSSize(
            width: max(
                notchWidth + Self.leftShoulderWidth + Self.rightShoulderWidth + Self.settingsReservedWidth,
                280
            ),
            height: snap(notchHeight)
        )
    }

    var collapsedSize: NSSize {
        wideCollapsedSize
    }

    var expandedWidth: CGFloat {
        max(Self.panelWidth, wideCollapsedSize.width)
    }

    /// Hit target to open the island: the visible collapsed bar only.
    var closestActivationZone: NSRect {
        frame(expanded: false)
    }

    /// Full menu-bar strip. Hovering here reveals the island in Full Screen
    /// without widening the expand hotspot.
    var topBarRevealZone: NSRect {
        let height = max(notchHeight, 24)
        return NSRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - height,
            width: screenFrame.width,
            height: height
        )
    }

    func holdZone(panelFrame: NSRect) -> NSRect {
        panelFrame.insetBy(dx: -Self.expandedHoldPad, dy: -Self.expandedHoldPad)
    }

    func frame(expanded: Bool, expandedHeight: CGFloat? = nil) -> NSRect {
        let size: NSSize
        if expanded {
            size = NSSize(width: expandedWidth, height: expandedHeight ?? Self.expandedHeight)
        } else {
            size = collapsedSize
        }
        var x = snap(notchCenterX - size.width / 2)
        let width = snap(size.width)
        let height = snap(size.height)
        x = min(max(x, screenFrame.minX), screenFrame.maxX - width)
        let top = screenFrame.maxY
        return NSRect(
            x: x,
            y: top - height,
            width: width,
            height: height
        )
    }

    func snap(_ value: CGFloat) -> CGFloat {
        let scale = max(backingScale, 1)
        return (value * scale).rounded() / scale
    }

    func snap(_ rect: NSRect) -> NSRect {
        let x = snap(rect.minX)
        let y = snap(rect.minY)
        let maxX = snap(rect.maxX)
        let maxY = snap(rect.maxY)
        return NSRect(x: x, y: y, width: maxX - x, height: maxY - y)
    }

    static func current() -> NotchGeometry {
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let screen = preferredScreen()
        let frame = screen.frame
        let left = screen.auxiliaryTopLeftArea
        let right = screen.auxiliaryTopRightArea
        let immersive = isImmersive(screen)
        let menuBarHidden = isMenuBarHidden(screen)

        if let left, let right {
            let cutout = hardwareCutout(left: left, right: right, screen: screen)
            if cutout.width > 40, cutout.height > 8 {
                return NotchGeometry(
                    screenFrame: frame,
                    notchMinX: cutout.minX,
                    notchWidth: cutout.width,
                    notchHeight: cutout.height,
                    hasNotch: true,
                    hidesCollapsedShoulders: hidesShoulders(on: screen),
                    isImmersive: immersive,
                    isMenuBarHidden: menuBarHidden,
                    backingScale: screen.backingScaleFactor
                )
            }
        }

        let inset = screen.safeAreaInsets.top
        let scale = max(screen.backingScaleFactor, 1)
        func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        if inset > 8 {
            let width: CGFloat = 180
            return NotchGeometry(
                screenFrame: frame,
                notchMinX: snap(frame.midX - width / 2),
                notchWidth: snap(width),
                notchHeight: snap(inset),
                hasNotch: true,
                hidesCollapsedShoulders: hidesShoulders(on: screen),
                isImmersive: immersive,
                isMenuBarHidden: menuBarHidden,
                backingScale: screen.backingScaleFactor
            )
        }

        let width: CGFloat = 160
        return NotchGeometry(
            screenFrame: frame,
            notchMinX: snap(frame.midX - width / 2),
            notchWidth: snap(width),
            notchHeight: snap(32),
            hasNotch: false,
            hidesCollapsedShoulders: hidesShoulders(on: screen),
            isImmersive: immersive,
            isMenuBarHidden: menuBarHidden,
            backingScale: screen.backingScaleFactor
        )
    }

    private static func preferredScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        if NotchCustomization.shared.alwaysShowInFullScreen,
           let immersive = NSScreen.screens.first(where: { $0.frame.contains(mouse) && (isImmersive($0) || isMenuBarHidden($0)) }) {
            return immersive
        }
        if let underMouse = NSScreen.screens.first(where: { $0.frame.contains(mouse) }), hasCutout(underMouse) {
            return underMouse
        }
        if let builtIn = NSScreen.screens.first(where: { hasCutout($0) && CGDisplayIsBuiltin(displayID($0)) != 0 }) {
            return builtIn
        }
        if let notched = NSScreen.screens.first(where: hasCutout) {
            return notched
        }
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
            ?? NSScreen.screens.first!
    }

    /// The camera housing is the gap between the two menu-bar auxiliary areas.
    private static func hardwareCutout(left: NSRect, right: NSRect, screen: NSScreen) -> NSRect {
        let scale = max(screen.backingScaleFactor, 1)
        func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let minX = snap(left.maxX)
        let maxX = snap(right.minX)
        let height = snap(max(left.height, right.height))
        return NSRect(
            x: minX,
            y: screen.frame.maxY - height,
            width: max(maxX - minX, 0),
            height: height
        )
    }

    private static func hidesShoulders(on screen: NSScreen) -> Bool {
        guard !NotchCustomization.shared.showFullscreenShoulders else { return false }
        return hasFullscreenWindow(on: screen)
    }

    static func isMenuBarHidden(_ screen: NSScreen) -> Bool {
        screen.frame.maxY - screen.visibleFrame.maxY < 8
    }

    /// Full Screen, including when the menu bar is hidden for the immersive look.
    static func isImmersive(_ screen: NSScreen) -> Bool {
        let id = displayID(screen)
        let now = ProcessInfo.processInfo.systemUptime
        if let cached = immersiveCache[id], now - cached.at < 0.35 {
            return cached.value
        }
        let value = hasFullscreenWindow(on: screen) || coversDisplay(screen)
        immersiveCache[id] = (now, value)
        return value
    }

    private static var immersiveCache: [CGDirectDisplayID: (at: TimeInterval, value: Bool)] = [:]

    private static func coversDisplay(_ screen: NSScreen) -> Bool {
        let frame = screen.frame
        let visible = screen.visibleFrame
        let topGap = frame.maxY - visible.maxY
        let bottomGap = visible.minY - frame.minY
        return topGap < 6 && bottomGap < 6
    }

    private static func hasFullscreenWindow(on screen: NSScreen) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        guard let primary = NSScreen.screens.first else { return false }
        let screenCG = CGRect(
            x: screen.frame.minX,
            y: primary.frame.maxY - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
        )
        for window in info {
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            if layer != 0 { continue }
            let alpha = window[kCGWindowAlpha as String] as? CGFloat ?? 1
            if alpha < 0.85 { continue }
            guard
                let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                let x = bounds["X"],
                let y = bounds["Y"],
                let width = bounds["Width"],
                let height = bounds["Height"]
            else { continue }
            let rect = CGRect(x: x, y: y, width: width, height: height)
            let coversWidth = abs(rect.width - screenCG.width) < 12 && abs(rect.minX - screenCG.minX) < 12
            let coversHeight = rect.height >= screenCG.height - 96
            if coversWidth && coversHeight && rect.intersects(screenCG) {
                return true
            }
        }
        return false
    }

    private static func hasCutout(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 8 ||
        (screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil)
    }

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
