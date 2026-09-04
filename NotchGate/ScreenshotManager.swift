import AppKit
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

@Observable
@MainActor
final class ScreenshotManager {
    static let shared = ScreenshotManager()
    static let didCapture = Notification.Name("notchgate.screenshotDidCapture")

    var lastImage: NSImage?
    var lastURL: URL?
    var countdown: Int = 0
    var isCapturing = false
    var statusMessage: String?
    var onWillCapture: (() -> Void)?
    var onDidCapture: (() -> Void)?

    private var timer: Timer?

    func captureFullScreen() {
        Task { await captureDisplay() }
    }

    func captureFrontWindow() {
        Task { await captureWindow() }
    }

    func captureSelection() {
        SelectionCaptureOverlay.present { [weak self] rect in
            guard let self, let rect else { return }
            Task { await self.captureDisplay(crop: rect) }
        }
    }

    func captureAfterDelay(_ seconds: Int) {
        timer?.invalidate()
        countdown = seconds
        statusMessage = "Capturing in \(seconds)s"
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { return }
                self.countdown -= 1
                if self.countdown <= 0 {
                    timer.invalidate()
                    self.countdown = 0
                    self.statusMessage = nil
                    await self.captureDisplay()
                } else {
                    self.statusMessage = "Capturing in \(self.countdown)s"
                }
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func revealLast() {
        guard let lastURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastURL])
    }

    func openLast() {
        guard let lastURL else { return }
        NSWorkspace.shared.open(lastURL)
    }

    private func captureDisplay(crop: CGRect? = nil) async {
        guard await ensureCaptureAccess() else { return }
        isCapturing = true
        onWillCapture?()
        defer {
            isCapturing = false
            onDidCapture?()
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            let displayID = screen.flatMap { NotchGeometryDisplay.displayID($0) } ?? CGMainDisplayID()
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                statusMessage = "No display to capture"
                return
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let image = try await capture(filter: filter, width: display.width, height: display.height)
            let cropped: CGImage
            if let crop, let screen {
                cropped = cropImage(image, crop: crop, screen: screen) ?? image
            } else {
                cropped = image
            }
            try finish(cropped)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func captureWindow() async {
        guard await ensureCaptureAccess() else { return }
        isCapturing = true
        onWillCapture?()
        defer {
            isCapturing = false
            onDidCapture?()
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let ours = Bundle.main.bundleIdentifier
            let window = content.windows
                .filter { $0.owningApplication?.bundleIdentifier != ours && $0.isOnScreen && $0.frame.width > 80 }
                .sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }
                .first
            guard let window else {
                statusMessage = "No window to capture"
                return
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = window.frame.size
            let image = try await capture(
                filter: filter,
                width: Int(max(scale.width, 200)),
                height: Int(max(scale.height, 120))
            )
            try finish(image)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func capture(filter: SCContentFilter, width: Int, height: Int) async throws -> CGImage {
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.showsCursor = NotchCustomization.shared.screenshotIncludeCursor
        config.capturesAudio = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private func ensureCaptureAccess() async -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        let granted = CGRequestScreenCaptureAccess()
        if !granted {
            statusMessage = "Screen Recording is required to capture."
        }
        return granted
    }

    private func finish(_ image: CGImage) throws {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        lastImage = nsImage
        lastURL = try save(image)
        statusMessage = lastURL?.lastPathComponent
        NotificationCenter.default.post(name: Self.didCapture, object: lastURL)
        NSSound(named: "Tink")?.play()
    }

    private func save(_ image: CGImage) throws -> URL {
        let layout = NotchCustomization.shared
        let folder = layout.screenshotSaveLocation.directory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        var format = layout.screenshotFormat
        let url = folder.appendingPathComponent("NotchGate-\(stamp).\(format.pathExtension)")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            format = .png
            let fallback = folder.appendingPathComponent("NotchGate-\(stamp).png")
            guard let png = CGImageDestinationCreateWithURL(fallback as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw ScreenshotError.writeFailed
            }
            CGImageDestinationAddImage(png, image, nil)
            guard CGImageDestinationFinalize(png) else { throw ScreenshotError.writeFailed }
            return fallback
        }
        var options: [CFString: Any] = [:]
        if format == .jpeg {
            options[kCGImageDestinationLossyCompressionQuality] = 0.86
        }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ScreenshotError.writeFailed }
        return url
    }

    private func cropImage(_ image: CGImage, crop: CGRect, screen: NSScreen) -> CGImage? {
        let frame = screen.frame
        let scale = screen.backingScaleFactor
        let x = (crop.minX - frame.minX) * scale
        let y = (frame.maxY - crop.maxY) * scale
        let rect = CGRect(x: x, y: y, width: crop.width * scale, height: crop.height * scale)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard rect.width > 2, rect.height > 2 else { return nil }
        return image.cropping(to: rect)
    }
}

private enum ScreenshotError: LocalizedError {
    case writeFailed
    var errorDescription: String? { "Couldn’t save the screenshot." }
}

private enum NotchGeometryDisplay {
    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

@MainActor
private enum SelectionCaptureOverlay {
    static func present(completion: @escaping (CGRect?) -> Void) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else {
            completion(nil)
            return
        }
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = SelectionView(frame: screen.frame) { rect in
            window.orderOut(nil)
            completion(rect)
        }
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class SelectionView: NSView {
    private let completion: (CGRect?) -> Void
    private var start: NSPoint?
    private var current: NSPoint?

    init(frame: NSRect, completion: @escaping (CGRect?) -> Void) {
        self.completion = completion
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        start = event.locationInWindow
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = event.locationInWindow
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = event.locationInWindow
        guard let start, let current else {
            completion(nil)
            return
        }
        let window = self.window
        let a = window?.convertToScreen(NSRect(origin: start, size: .zero)).origin ?? start
        let b = window?.convertToScreen(NSRect(origin: current, size: .zero)).origin ?? current
        let rect = NSRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
        completion(rect.width < 4 || rect.height < 4 ? nil : rect)
    }

    override func cancelOperation(_ sender: Any?) {
        completion(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let start, let current else { return }
        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(start.x - current.x),
            height: abs(start.y - current.y)
        )
        NSColor.white.withAlphaComponent(0.12).setFill()
        rect.fill()
        NSColor.white.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.stroke()
    }
}
