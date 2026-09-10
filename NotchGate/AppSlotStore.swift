import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PinnedApp: Codable, Equatable, Identifiable {
    var id: UUID
    var displayName: String
    var bundleIdentifier: String?
    var bookmark: Data?

    init(id: UUID = UUID(), displayName: String, bundleIdentifier: String?, bookmark: Data?) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.bookmark = bookmark
    }

    static func from(url: URL) -> PinnedApp? {
        guard let resolved = url.resolvedApplicationURL() else { return nil }
        let bundle = Bundle(url: resolved)
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? resolved.deletingPathExtension().lastPathComponent
        let bookmark = SecurityScoped.bookmark(for: resolved)
        return PinnedApp(
            displayName: name,
            bundleIdentifier: bundle?.bundleIdentifier,
            bookmark: bookmark
        )
    }

    func resolvedURL() -> URL? {
        if let bookmark, let url = SecurityScoped.resolve(bookmark) {
            if let access = ScopedFileAccess(url: url) {
                access.end()
                return url
            }
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        if let bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return url
        }
        return nil
    }

    func withResolvedURL<R>(_ body: (URL) throws -> R) rethrows -> R? {
        if let bookmark, let url = SecurityScoped.resolve(bookmark), let access = ScopedFileAccess(url: url) {
            defer { access.end() }
            return try body(access.url)
        }
        if let bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return try body(url)
        }
        return nil
    }

    func icon() -> NSImage {
        if let image = withResolvedURL({ AppIconCache.image(for: $0) }) {
            return image
        }
        let fallback = NSImage(systemSymbolName: "app.fill", accessibilityDescription: displayName) ?? NSImage()
        fallback.size = NSSize(width: 64, height: 64)
        fallback.isTemplate = false
        return fallback
    }

    func launch() {
        if let running = runningInstance() {
            running.unhide()
            running.activate(options: [.activateAllWindows])
            return
        }
        if let bookmark, let url = SecurityScoped.resolve(bookmark), let access = ScopedFileAccess(url: url) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: access.url, configuration: config) { _, error in
                access.end()
                if error != nil {
                    DispatchQueue.main.async { NSSound.beep() }
                }
            }
            return
        }
        if let bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if error != nil {
                    DispatchQueue.main.async { NSSound.beep() }
                }
            }
            return
        }
        NSSound.beep()
    }

    func forceQuit() {
        guard let running = runningInstance() else { return }
        running.forceTerminate()
    }

    func revealInFinder() {
        withResolvedURL { url in
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    var isInstalled: Bool {
        withResolvedURL { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    var isRunning: Bool { runningInstance() != nil }

    func runningInstance() -> NSRunningApplication? {
        guard let bundleIdentifier else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundleIdentifier && $0.activationPolicy == .regular
        }
    }
}

enum AppIconCache {
    private static var images: [String: NSImage] = [:]

    static func image(for url: URL) -> NSImage {
        let key = url.standardizedFileURL.path
        if let cached = images[key] { return cached }
        let baked = NSWorkspace.shared.icon(forFile: url.path).fullColorBitmap(pointSize: 64)
        images[key] = baked
        return baked
    }
}

private extension NSImage {
    /// Flatten IconRef images to a retina bitmap so overlay windows don't grey them,
    /// without keeping a huge representation that crops when drawn.
    func fullColorBitmap(pointSize: CGFloat) -> NSImage {
        let scale: CGFloat = 2
        let pixels = max(Int((pointSize * scale).rounded()), 1)
        let point = NSSize(width: pointSize, height: pointSize)
        guard let canvas = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return self
        }
        canvas.size = point

        let source = (copy() as? NSImage) ?? self
        source.isTemplate = false
        source.size = point

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: point),
            from: NSRect(origin: .zero, size: source.size),
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: point)
        image.addRepresentation(canvas)
        image.isTemplate = false
        return image
    }
}

private struct SavedSlots: Codable {
    var version: Int
    var items: [SavedSlot]
}

private struct SavedSlot: Codable {
    var id: UUID?
    var displayName: String
    var bundleIdentifier: String?
    var bookmark: Data?
    var empty: Bool

    init(from app: PinnedApp?) {
        if let app {
            id = app.id
            displayName = app.displayName
            bundleIdentifier = app.bundleIdentifier
            bookmark = app.bookmark
            empty = false
        } else {
            id = nil
            displayName = ""
            bundleIdentifier = nil
            bookmark = nil
            empty = true
        }
    }

    var pinned: PinnedApp? {
        guard !empty else { return nil }
        return PinnedApp(
            id: id ?? UUID(),
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            bookmark: bookmark
        )
    }
}

@Observable
@MainActor
final class AppSlotStore {
    static let shared = AppSlotStore()
    static let slotType = "com.notchgate.slot-index"
    static let slotsChanged = Notification.Name("notchgate.slotsChanged")
    static let slotCount = AppSlotStyle.capacity
    private static let defaultsKey = "notchgate.pinnedApps"
    private static let defaultsKeyV2 = "notchgate.pinnedApps.v2"

    var slots: [PinnedApp?]
    var draggingIndex: Int?
    var hoveredSlot: Int?
    var dropRowFrame: NSRect = .zero

    init() {
        if let saved = Self.loadSavedSlots() {
            slots = Self.normalized(saved)
        } else {
            slots = Self.factorySlots()
            persist()
        }
    }

    func drop(url: URL, onto index: Int) {
        guard index >= 0, index < Self.slotCount else { return }
        guard let app = PinnedApp.from(url: url) else { return }
        replace(app, onto: index)
    }

    func replace(_ app: PinnedApp, onto index: Int) {
        guard index >= 0, index < Self.slotCount else { return }
        for i in slots.indices where i != index {
            if let existing = slots[i],
               existing.bundleIdentifier != nil,
               existing.bundleIdentifier == app.bundleIdentifier {
                slots[i] = nil
            }
        }
        slots[index] = app
        persist()
    }

    func move(from: Int, to: Int) {
        guard from != to, slots.indices.contains(from), slots.indices.contains(to) else { return }
        slots.swapAt(from, to)
        persist()
    }

    func sourceSlotIndex(from pasteboard: NSPasteboard? = nil) -> Int? {
        if let draggingIndex, slots.indices.contains(draggingIndex) {
            return draggingIndex
        }
        let type = NSPasteboard.PasteboardType(Self.slotType)
        let boards = [pasteboard, NSPasteboard(name: .drag)].compactMap { $0 }
        for board in boards {
            if let raw = board.string(forType: type)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let value = Int(raw), slots.indices.contains(value) {
                return value
            }
            if let data = board.data(forType: type),
               let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let value = Int(raw), slots.indices.contains(value) {
                return value
            }
        }
        return nil
    }

    func clear(index: Int) {
        guard slots.indices.contains(index) else { return }
        slots[index] = nil
        persist()
    }

    func chooseApp(for index: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application, .applicationBundle]
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose an app to pin in this slot. It replaces whatever is there."
        panel.prompt = "Use This App"
        UtilityWindows.prepareForStoreKit()
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.drop(url: url, onto: index)
            }
            UtilityWindows.restoreAccessoryIfIdle()
        }
    }

    func slotIndex(atWindowPoint point: NSPoint) -> Int? {
        let frame = dropRowFrame
        guard frame.width > 8 else { return nil }
        let style = NotchCustomization.shared.appSlotStyle
        let columns = max(style.columns, 1)
        let rows = max(style.rows, 1)
        let colWidth = frame.width / CGFloat(columns)
        let rowHeight = frame.height / CGFloat(rows)
        let col = min(max(Int((point.x - frame.minX) / colWidth), 0), columns - 1)
        let rowFromTop = min(max(Int((frame.maxY - point.y) / rowHeight), 0), rows - 1)
        let index = rowFromTop * columns + col
        return min(max(index, 0), Self.slotCount - 1)
    }

    func handleDragging(_ sender: NSDraggingInfo, onto index: Int) -> Bool {
        guard slots.indices.contains(index) else { return false }
        if let source = sourceSlotIndex(from: sender.draggingPasteboard) {
            move(from: source, to: index)
            draggingIndex = nil
            hoveredSlot = nil
            return true
        }
        return false
    }

    func handlePasteboard(_ pasteboard: NSPasteboard, onto index: Int) -> Bool {
        guard slots.indices.contains(index) else { return false }
        if let source = sourceSlotIndex(from: pasteboard) {
            move(from: source, to: index)
            draggingIndex = nil
            hoveredSlot = nil
            return true
        }
        return false
    }

    private func persist() {
        Self.write(slots)
        Persistence.flush()
        NotificationCenter.default.post(name: Self.slotsChanged, object: nil)
    }

    private static func write(_ slots: [PinnedApp?]) {
        let file = SavedSlots(version: 2, items: normalized(slots).map { SavedSlot(from: $0) })
        guard let data = try? JSONEncoder().encode(file) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKeyV2)
        UserDefaults.standard.set(data, forKey: defaultsKey)
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try? data.write(to: slotsFileURL, options: .atomic)
    }

    private static func normalized(_ slots: [PinnedApp?]) -> [PinnedApp?] {
        (0..<slotCount).map { slots.indices.contains($0) ? slots[$0] : nil }
    }

    private static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchGate", isDirectory: true)
    }

    private static var slotsFileURL: URL {
        supportDirectory.appendingPathComponent("slots.json")
    }

    private static func loadSavedSlots() -> [PinnedApp?]? {
        if let slots = decodeSlots(from: (try? Data(contentsOf: slotsFileURL))) {
            return slots
        }
        let defaults = UserDefaults.standard
        if let slots = decodeSlots(from: defaults.data(forKey: defaultsKeyV2)) {
            write(slots)
            return slots
        }
        if let slots = decodeSlots(from: defaults.data(forKey: defaultsKey)) {
            write(slots)
            return slots
        }
        return nil
    }

    private static func decodeSlots(from data: Data?) -> [PinnedApp?]? {
        guard let data, !data.isEmpty else { return nil }
        if let file = try? JSONDecoder().decode(SavedSlots.self, from: data), !file.items.isEmpty {
            return normalized(file.items.map(\.pinned))
        }
        if let saved = try? JSONDecoder().decode([PinnedApp?].self, from: data), !saved.isEmpty {
            return normalized(saved)
        }
        if let saved = try? JSONDecoder().decode([PinnedApp].self, from: data), !saved.isEmpty {
            return normalized(saved.map { Optional($0) })
        }
        return nil
    }

    private static func factorySlots() -> [PinnedApp?] {
        [
            pinned(bundleID: "com.apple.finder", name: "Finder"),
            pinned(bundleID: "com.apple.Safari", name: "Safari"),
            pinned(bundleID: "com.apple.MobileSMS", name: "Messages"),
            nil,
            nil
        ]
    }

    private static func pinned(bundleID: String, name: String) -> PinnedApp? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return PinnedApp(displayName: name, bundleIdentifier: bundleID, bookmark: nil)
        }
        return PinnedApp.from(url: url)
    }
}

enum PasteboardApps {
    // Only internal slot reordering is a drag target. External files and URLs are not accepted.
    static let dragTypes: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType(AppSlotStore.slotType)
    ]

    static func dropOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        guard sourceSlotIndex(from: sender.draggingPasteboard) != nil else { return [] }
        return .move
    }

    private static func sourceSlotIndex(from pasteboard: NSPasteboard) -> Int? {
        guard let raw = pasteboard.string(forType: NSPasteboard.PasteboardType(AppSlotStore.slotType)),
              let index = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              (0..<AppSlotStore.slotCount).contains(index) else { return nil }
        return index
    }

}

extension URL {
    func resolvedApplicationURL() -> URL? {
        var current = (self as NSURL).filePathURL ?? self
        current = current.standardizedFileURL.resolvingSymlinksInPath()
        if current.pathExtension.lowercased() == "app" { return current }
        var walker = current
        while walker.path != "/" {
            if walker.pathExtension.lowercased() == "app" { return walker }
            walker.deleteLastPathComponent()
        }
        let values = try? current.resourceValues(forKeys: [.contentTypeKey, .isApplicationKey])
        if values?.isApplication == true || values?.contentType?.conforms(to: .application) == true {
            return current
        }
        return nil
    }
}

struct SlotDropCatcher: NSViewRepresentable {
    let index: Int
    var store: AppSlotStore
    var onDragging: ((Bool) -> Void)? = nil

    func makeNSView(context: Context) -> SlotDropNSView {
        let view = SlotDropNSView()
        view.index = index
        view.store = store
        view.onDragging = onDragging
        return view
    }

    func updateNSView(_ nsView: SlotDropNSView, context: Context) {
        nsView.index = index
        nsView.store = store
        nsView.onDragging = onDragging
    }
}

final class SlotDropNSView: NSView {
    var index = 0
    var store: AppSlotStore?
    var onDragging: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(PasteboardApps.dragTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(PasteboardApps.dragTypes)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        if NSEvent.pressedMouseButtons & 1 == 1 { return self }
        if let event = NSApp.currentEvent {
            switch event.type {
            case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
                if NSPasteboard(name: .drag).types?.isEmpty == false { return self }
            default:
                break
            }
        }
        return nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        store?.hoveredSlot = index
        onDragging?(true)
        return PasteboardApps.dropOperation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        store?.hoveredSlot = index
        return PasteboardApps.dropOperation(for: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if store?.hoveredSlot == index {
            store?.hoveredSlot = nil
        }
        onDragging?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        if store?.hoveredSlot == index {
            store?.hoveredSlot = nil
        }
        onDragging?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { onDragging?(false) }
        return store?.handlePasteboard(sender.draggingPasteboard, onto: index) ?? false
    }
}
