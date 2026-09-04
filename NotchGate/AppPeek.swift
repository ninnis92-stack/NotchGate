import AppKit
import CoreGraphics
import ScreenCaptureKit
import SwiftUI

/// Hover card for Preview mode. Never requests Screen Recording; captures only if already allowed.
@MainActor
final class AppPeekController {
    weak var notchPanel: NSPanel?
    var onVisibilityChange: ((Bool) -> Void)?

    private var panel: NSPanel?
    private var app: PinnedApp?
    private var showWork: DispatchWorkItem?
    private let iconView = NSImageView()
    private let thumbView = NSImageView()
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
        display(app, snapshot: nil)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = await AppWindowCapture.snapshot(for: app)
            guard self.app?.bundleIdentifier == app.bundleIdentifier else { return }
            self.display(app, snapshot: snapshot)
        }
    }

    private func display(_ app: PinnedApp, snapshot: NSImage?) {
        let panel = makePanel()
        iconView.image = app.icon()
        nameField.stringValue = app.displayName
        statusField.stringValue = app.isRunning ? "Running" : (app.isInstalled ? "Not running" : "Not installed")
        thumbView.image = snapshot
        thumbView.isHidden = snapshot == nil
        panel.setFrame(frame(hasThumbnail: snapshot != nil), display: true)
        panel.contentView?.frame = NSRect(origin: .zero, size: panel.frame.size)
        layoutContent(hasThumbnail: snapshot != nil)
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
        thumbView.imageScaling = .scaleProportionallyUpOrDown
        thumbView.wantsLayer = true
        thumbView.layer?.cornerRadius = 10
        thumbView.layer?.cornerCurve = .continuous
        thumbView.layer?.masksToBounds = true

        configureLabel(nameField, size: 13, weight: .semibold, alpha: 1)
        configureLabel(statusField, size: 11, weight: .medium, alpha: 0.55)
        configureLabel(hintField, size: 10, weight: .medium, alpha: 0.4)

        root.addSubview(iconView)
        root.addSubview(nameField)
        root.addSubview(statusField)
        root.addSubview(hintField)
        root.addSubview(thumbView)
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

    private func layoutContent(hasThumbnail: Bool) {
        guard let root = panel?.contentView else { return }
        let width = root.bounds.width
        let height = root.bounds.height
        iconView.frame = NSRect(x: 14, y: height - 54, width: 36, height: 36)
        nameField.frame = NSRect(x: 60, y: height - 36, width: width - 74, height: 18)
        statusField.frame = NSRect(x: 60, y: height - 54, width: width - 74, height: 16)
        if hasThumbnail {
            thumbView.frame = NSRect(x: 14, y: 28, width: width - 28, height: height - 90)
            hintField.frame = NSRect(x: 14, y: 8, width: width - 28, height: 14)
        } else {
            thumbView.frame = .zero
            hintField.frame = NSRect(x: 60, y: height - 72, width: width - 74, height: 14)
        }
    }

    private func frame(hasThumbnail: Bool) -> NSRect {
        let size = hasThumbnail ? NSSize(width: 320, height: 220) : NSSize(width: 280, height: 88)
        let notch = notchPanel?.frame ?? .zero
        return NSRect(
            x: notch.midX - size.width / 2,
            y: notch.minY - size.height + 8,
            width: size.width,
            height: size.height
        )
    }
}

enum AppWindowCapture {
    static func snapshot(for app: PinnedApp) async -> NSImage? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        guard let pid = app.runningInstance()?.processIdentifier else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let windows = content.windows.filter { window in
                window.owningApplication?.processID == pid
                    && window.frame.width >= 80
                    && window.frame.height >= 80
                    && window.isOnScreen
            }
            guard let window = windows.max(by: { lhs, rhs in
                (lhs.frame.width * lhs.frame.height) < (rhs.frame.width * rhs.frame.height)
            }) else {
                return nil
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            let scale = min(1, 640 / max(window.frame.width, 1), 400 / max(window.frame.height, 1))
            config.width = max(Int(window.frame.width * scale), 160)
            config.height = max(Int(window.frame.height * scale), 100)
            config.showsCursor = false
            config.capturesAudio = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        } catch {
            return nil
        }
    }
}
