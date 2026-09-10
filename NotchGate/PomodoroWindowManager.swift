import AppKit
import SwiftUI

@MainActor
final class PomodoroWindowManager: NSObject, NSWindowDelegate {
    static let shared = PomodoroWindowManager()

    private var panel: NSPanel?
    private let originKey = "notch.pomodoro.origin"

    func toggle() {
        if panel?.isVisible == true {
            hideAnimated()
            return
        }
        show()
    }

    func show() {
        let panel = makePanel()
        panel.setContentSize(PomodoroWindowView.panelSize)
        if NotchCustomization.shared.rememberPosition, let origin = storedOrigin(), originIsOnScreen(origin) {
            panel.setFrameOrigin(origin)
        } else {
            panel.center()
        }
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NotchAnimationManager.shared.expandDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hideAnimated() {
        persistPosition()
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NotchAnimationManager.shared.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    private func originIsOnScreen(_ origin: NSPoint) -> Bool {
        let probe = NSRect(x: origin.x, y: origin.y, width: 40, height: 40)
        return NSScreen.screens.contains { $0.visibleFrame.intersects(probe) }
    }

    func persistPosition() {
        guard NotchCustomization.shared.rememberPosition, let panel else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: originKey)
    }

    func windowDidMove(_ notification: Notification) {
        persistPosition()
    }

    func windowWillClose(_ notification: Notification) {
        persistPosition()
    }

    private func makePanel() -> NSPanel {
        if let panel { return panel }
        let hosting = NSHostingView(
            rootView: PomodoroWindowView()
                .environment(PomodoroService.shared)
                .environment(ThemeManager.shared)
                .environment(NotchCustomization.shared)
                .environment(NotchAnimationManager.shared)
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: PomodoroWindowView.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Pomodoro"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.contentView = hosting
        panel.delegate = self
        return panel
    }

    private func storedOrigin() -> NSPoint? {
        guard let raw = UserDefaults.standard.string(forKey: originKey) else { return nil }
        let point = NSPointFromString(raw)
        if point.x == 0, point.y == 0, raw != "{0, 0}" { return nil }
        return point
    }
}
