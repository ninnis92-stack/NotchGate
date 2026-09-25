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

    /// Shoulder width scaled to this display's camera housing (14" vs 16" vs Air).
    var leftShoulderWidth: CGFloat {
        snap(max(108, min(160, notchWidth * 0.72)))
    }

    var rightShoulderWidth: CGFloat {
        snap(max(56, min(92, notchWidth * 0.36)))
    }
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
    static let expandedHoldPad: CGFloat = 6

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
                notchWidth + leftShoulderWidth + rightShoulderWidth + Self.settingsReservedWidth,
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

    /// Reveal only over NotchGate's collapsed footprint, including its shoulders.
    /// Menu items elsewhere on the top bar must neither reveal nor keep it open.
    /// Use the same global-coordinate geometry as island activation on all displays.
    var topBarRevealZone: NSRect {
        closestActivationZone.intersection(screenFrame)
    }

    /// Auto-hide expansion target. The collapsed bar includes wide shoulder
    /// controls, but those controls should not expand the full panel merely
    /// because the pointer crossed their area.
    var autoHideExpansionZone: NSRect {
        notchRect.insetBy(dx: -8, dy: -4).intersection(screenFrame)
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
        guard let screen = preferredScreen() else {
            return NotchGeometry(
                screenFrame: .zero,
                notchMinX: 0,
                notchWidth: 0,
                notchHeight: 0,
                hasNotch: false,
                hidesCollapsedShoulders: false,
                isImmersive: false,
                isMenuBarHidden: false,
                backingScale: 1
            )
        }
        let frame = screen.frame
        let display = MacHardware.displayID(screen)
        let immersive = isImmersive(screen)
        let menuBarHidden = isMenuBarHidden(screen)
        let scale = max(screen.backingScaleFactor, 1)
        func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }

        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let cutout = hardwareCutout(left: left, right: right, screen: screen)
            if cutout.width > 40, cutout.height > 8 {
                MacHardware.cutoutCache[display] = cutout
                return make(
                    screen: screen,
                    notchMinX: cutout.minX,
                    notchWidth: cutout.width,
                    notchHeight: cutout.height,
                    hasNotch: true,
                    immersive: immersive,
                    menuBarHidden: menuBarHidden
                )
            }
        }

        if let cached = MacHardware.cutoutCache[display], cached.width > 40 {
            let notchX = frameContainsCachedCutout(frame, cached)
                ? snap(cached.minX)
                : snap(frame.midX - cached.width / 2)
            return make(
                screen: screen,
                notchMinX: notchX,
                notchWidth: snap(cached.width),
                notchHeight: snap(cached.height),
                hasNotch: true,
                immersive: immersive,
                menuBarHidden: menuBarHidden
            )
        }

        let inset = screen.safeAreaInsets.top
        let fallback = MacHardware.fallbackNotch(on: screen)
        if inset > 8 || (MacHardware.isLaptop && MacHardware.isBuiltIn(screen)) {
            return make(
                screen: screen,
                notchMinX: snap(frame.midX - fallback.width / 2),
                notchWidth: fallback.width,
                notchHeight: snap(max(inset, fallback.height)),
                hasNotch: inset > 8 || MacHardware.isLaptop,
                immersive: immersive,
                menuBarHidden: menuBarHidden
            )
        }

        return make(
            screen: screen,
            notchMinX: snap(frame.midX - fallback.width / 2),
            notchWidth: fallback.width,
            notchHeight: fallback.height,
            hasNotch: false,
            immersive: immersive,
            menuBarHidden: menuBarHidden
        )
    }

    private static func make(
        screen: NSScreen,
        notchMinX: CGFloat,
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        hasNotch: Bool,
        immersive: Bool,
        menuBarHidden: Bool
    ) -> NotchGeometry {
        NotchGeometry(
            screenFrame: screen.frame,
            notchMinX: notchMinX,
            notchWidth: notchWidth,
            notchHeight: notchHeight,
            hasNotch: hasNotch,
            hidesCollapsedShoulders: hidesShoulders(on: screen),
            isImmersive: immersive,
            isMenuBarHidden: menuBarHidden,
            backingScale: screen.backingScaleFactor
        )
    }

    private static func frameContainsCachedCutout(_ frame: NSRect, _ cutout: NSRect) -> Bool {
        cutout.minX >= frame.minX - 2 && cutout.maxX <= frame.maxX + 2
    }

    /// Follow the display under the pointer so a laptop + external setup
    /// sizes the island for that screen's camera (or a centered fake island).
    private static func preferredScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        if let underMouse = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            return underMouse
        }
        if let builtIn = NSScreen.screens.first(where: { MacHardware.isBuiltIn($0) && hasCutout($0) }) {
            return builtIn
        }
        if let notched = NSScreen.screens.first(where: { hasCutout($0) }) {
            return notched
        }
        return NSScreen.main
            ?? NSScreen.screens.first
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
