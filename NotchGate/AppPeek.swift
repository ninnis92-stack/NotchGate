import AppKit
import SwiftUI

/// Hover card for Preview mode. Shows local app metadata without capturing window content.
@MainActor
final class AppPeekController {
    weak var notchPanel: NSPanel?
    var onVisibilityChange: ((Bool) -> Void)?

    private var panel: NSPanel?
    private var app: PinnedApp?
    private var showWork: DispatchWorkItem?
    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private let statusField = NSTextField(labelWithString: "")
    private let hintField = NSTextField(labelWithString: "Click the icon to open")

    var isVisible: Bool { app != nil && panel?.isVisible == true }

    func contains(_ point: NSPoint) -> Bool {
        guard isVisible, let panel else { return false }
        return panel.frame.contains(point)
    }

    func applyLevel(_ level: NSWindow.Level) {
        OverlayChrome.apply(panel)
        if isVisible {
            panel?.orderFrontRegardless()
            UtilityWindows.keepAboveOverlay()
        }
    }

    func hover(_ app: PinnedApp?, isInside: Bool) {
        showWork?.cancel()
        guard NotchCustomization.shared.showAppPreviews else {
            dismiss()
            return
        }
        guard !UtilityWindows.isBlockingIsland else {
            dismiss()
            return
        }
        guard isInside, let app else { return }
        if self.app?.bundleIdentifier == app.bundleIdentifier, isVisible { return }
        let work = DispatchWorkItem { [weak self] in
            self?.show(app)
        }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    func trackPointer(_ point: NSPoint, island: NSRect?) {
        guard app != nil else { return }
        if contains(point) || (island?.contains(point) ?? false) {
            showWork?.cancel()
            return
        }
        dismiss()
        onVisibilityChange?(false)
    }

    func dismiss() {
        showWork?.cancel()
        showWork = nil
        app = nil
        panel?.orderOut(nil)
    }

    private func show(_ app: PinnedApp) {
        guard NotchCustomization.shared.showAppPreviews, !UtilityWindows.isBlockingIsland else {
            dismiss()
            return
        }
        self.app = app
        display(app)
    }

    private func display(_ app: PinnedApp) {
        let panel = makePanel()
        iconView.image = app.icon()
        nameField.stringValue = app.displayName
        statusField.stringValue = app.isRunning ? "Running" : (app.isInstalled ? "Not running" : "Not installed")
        panel.setFrame(frame(), display: true)
        panel.contentView?.frame = NSRect(origin: .zero, size: panel.frame.size)
        layoutContent()
        panel.orderFrontRegardless()
        UtilityWindows.keepAboveOverlay()
        onVisibilityChange?(true)
    }

    private func makePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NotchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 88),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        OverlayChrome.apply(panel)
        panel.ignoresMouseEvents = true

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 88))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.94).cgColor
        root.layer?.cornerRadius = 16
        root.layer?.cornerCurve = .continuous
        root.layer?.borderWidth = 1
        root.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor

        iconView.imageScaling = .scaleProportionallyUpOrDown

        configureLabel(nameField, size: 13, weight: .semibold, alpha: 1)
        configureLabel(statusField, size: 11, weight: .medium, alpha: 0.55)
        configureLabel(hintField, size: 10, weight: .medium, alpha: 0.4)

        root.addSubview(iconView)
        root.addSubview(nameField)
        root.addSubview(statusField)
        root.addSubview(hintField)
        panel.contentView = root
        self.panel = panel
        return panel
    }

    private func configureLabel(_ field: NSTextField, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) {
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = NSColor.white.withAlphaComponent(alpha)
        field.drawsBackground = false
        field.isBezeled = false
        field.lineBreakMode = .byTruncatingTail
    }

    private func layoutContent() {
        guard let root = panel?.contentView else { return }
        let width = root.bounds.width
        let height = root.bounds.height
        iconView.frame = NSRect(x: 14, y: height - 54, width: 36, height: 36)
        nameField.frame = NSRect(x: 60, y: height - 36, width: width - 74, height: 18)
        statusField.frame = NSRect(x: 60, y: height - 54, width: width - 74, height: 16)
        hintField.frame = NSRect(x: 60, y: height - 72, width: width - 74, height: 14)
    }

    private func frame() -> NSRect {
        let size = NSSize(width: 280, height: 88)
        let notch = notchPanel?.frame ?? .zero
        return NSRect(
            x: notch.midX - size.width / 2,
            y: notch.minY - size.height + 8,
            width: size.width,
            height: size.height
        )
    }
}
