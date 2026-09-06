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
            running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
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
        let revealed = withResolvedURL { url in
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        if revealed == nil { NSSound.beep() }
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
        _ = pasteboard
        if let draggingIndex, slots.indices.contains(draggingIndex) {
            return draggingIndex
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

    func handleProviders(_ providers: [NSItemProvider], onto index: Int) -> Bool {
        let sourceSlot = draggingIndex
        draggingIndex = nil

        if let provider = providers.first {
            if let sourceSlot, provider.hasItemConformingToTypeIdentifier(Self.slotType) {
                move(from: sourceSlot, to: index)
                return true
            }
            Self.loadDroppedURL(from: provider) { [weak self] url in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let url, PinnedApp.from(url: url) != nil {
                        self.drop(url: url, onto: index)
                    } else if let sourceSlot {
                        self.move(from: sourceSlot, to: index)
                    }
                }
            }
            return true
        }

        if let sourceSlot {
            move(from: sourceSlot, to: index)
            return true
        }
        return false
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
        guard canHandle(sender.draggingPasteboard) else { return false }
        if let source = sourceSlotIndex(from: sender.draggingPasteboard) {
            move(from: source, to: index)
            draggingIndex = nil
            hoveredSlot = nil
            return true
        }
        let boards = [sender.draggingPasteboard, NSPasteboard(name: .drag)]
        for board in boards {
            if handlePasteboard(board, onto: index) {
                return true
            }
        }
        if receiveFilePromises(sender, onto: index) {
            return true
        }
        if receiveEnumeratedURLs(sender, onto: index) {
            return true
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("NotchGateDrop-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let names = sender.namesOfPromisedFilesDropped(atDestination: temp) ?? []
        for name in names {
            let url = temp.appendingPathComponent(name)
            if let app = Self.waitForApplication(at: url) {
                drop(url: app, onto: index)
                return true
            }
        }
        if let contents = try? FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil),
           let app = contents.compactMap({ $0.resolvedApplicationURL() }).first {
            drop(url: app, onto: index)
            return true
        }
        return false
    }

    func canHandle(_ pasteboard: NSPasteboard) -> Bool {
        sourceSlotIndex(from: pasteboard) != nil
            || PasteboardApps.firstApplication(from: pasteboard) != nil
    }

    private func receiveEnumeratedURLs(_ sender: NSDraggingInfo, onto index: Int) -> Bool {
        var accepted = false
        sender.enumerateDraggingItems(
            options: [],
            for: nil,
            classes: [NSURL.self, NSString.self],
            searchOptions: [
                .urlReadingFileURLsOnly: false,
                .urlReadingContentsConformToTypes: [
                    UTType.application.identifier,
                    UTType.applicationBundle.identifier,
                    UTType.bundle.identifier
                ]
            ]
        ) { [weak self] draggingItem, _, _ in
            guard let self else { return }
            if let url = draggingItem.item as? URL, let app = url.resolvedApplicationURL() {
                self.drop(url: app, onto: index)
                accepted = true
            } else if let string = draggingItem.item as? String,
                      let app = PasteboardApps.application(fromDroppedString: string) {
                self.drop(url: app, onto: index)
                accepted = true
            }
        }
        return accepted
    }

    private static func waitForApplication(at url: URL) -> URL? {
        for _ in 0..<25 {
            if FileManager.default.fileExists(atPath: url.path),
               let app = url.resolvedApplicationURL() {
                return app
            }
            Thread.sleep(forTimeInterval: 0.04)
        }
        return url.resolvedApplicationURL()
    }

    private func receiveFilePromises(_ sender: NSDraggingInfo, onto index: Int) -> Bool {
        var accepted = false
        sender.enumerateDraggingItems(
            options: [],
            for: nil,
            classes: [NSFilePromiseReceiver.self],
            searchOptions: [:]
        ) { [weak self] draggingItem, _, _ in
            guard let self, let receiver = draggingItem.item as? NSFilePromiseReceiver else { return }
            accepted = true
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("NotchGateDrop", isDirectory: true)
            try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            receiver.receivePromisedFiles(atDestination: dest, options: [:], operationQueue: .main) { url, error in
                guard error == nil else { return }
                Task { @MainActor in
                    self.drop(url: url, onto: index)
                }
            }
        }
        return accepted
    }

    func handlePasteboard(_ pasteboard: NSPasteboard, onto index: Int) -> Bool {
        guard slots.indices.contains(index) else { return false }
        if let source = sourceSlotIndex(from: pasteboard) {
            move(from: source, to: index)
            draggingIndex = nil
            hoveredSlot = nil
            return true
        }
        guard let url = PasteboardApps.firstApplication(from: pasteboard) else { return false }
        drop(url: url, onto: index)
        draggingIndex = nil
        hoveredSlot = nil
        return true
    }

    func itemProvider(for index: Int) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: Self.slotType, visibility: .ownProcess) { completion in
            completion(Data("\(index)".utf8), nil)
            return nil
        }
        if let url = slots[index]?.withResolvedURL({ $0 }) {
            provider.registerObject(url as NSURL, visibility: .all)
        }
        return provider
    }

    private static func loadDroppedURL(from provider: NSItemProvider, completion: @escaping (URL?) -> Void) {
        let identifiers = [
            UTType.fileURL.identifier,
            UTType.application.identifier,
            UTType.applicationBundle.identifier,
            "com.apple.application"
        ]
        if let type = identifiers.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) {
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                if let url = coerceURL(item) {
                    completion(url)
                    return
                }
                provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                    completion(url)
                }
            }
            return
        }
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                completion(url)
            }
            return
        }
        completion(nil)
    }

    static func coerceURL(_ item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let url = item as? NSURL { return url as URL }
        if let data = item as? Data {
            if let url = URL(dataRepresentation: data, relativeTo: nil) { return url }
            if let string = String(data: data, encoding: .utf8) {
                return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
                    ?? URL(fileURLWithPath: string)
            }
        }
        if let string = item as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed), url.isFileURL { return url }
            if trimmed.hasPrefix("/") { return URL(fileURLWithPath: trimmed) }
        }
        return nil
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
            pinned(bundleID: "com.apple.Music", name: "Music"),
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
    static let dragTypes: [NSPasteboard.PasteboardType] = {
        var types: [NSPasteboard.PasteboardType] = [
            .fileURL,
            .URL,
            .string,
            .tiff,
            NSPasteboard.PasteboardType("public.item"),
            NSPasteboard.PasteboardType("public.data"),
            NSPasteboard.PasteboardType("public.url"),
            NSPasteboard.PasteboardType("public.file-url"),
            NSPasteboard.PasteboardType("public.utf8-plain-text"),
            NSPasteboard.PasteboardType("public.utf16-plain-text"),
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
            NSPasteboard.PasteboardType("Apple URL pasteboard type"),
            NSPasteboard.PasteboardType("NSURLPboardType"),
            NSPasteboard.PasteboardType("Apple files promise pasteboard type"),
            NSPasteboard.PasteboardType("NSPromiseContentsPboardType"),
            NSPasteboard.PasteboardType("NeXT plain ascii pasteboard type"),
            NSPasteboard.PasteboardType("com.apple.application-bundle-identifier"),
            NSPasteboard.PasteboardType("com.apple.application"),
            NSPasteboard.PasteboardType("com.apple.application-name"),
            NSPasteboard.PasteboardType("com.apple.application-bundle"),
            NSPasteboard.PasteboardType("com.apple.dock.extra"),
            NSPasteboard.PasteboardType("com.apple.dock.tile"),
            NSPasteboard.PasteboardType("com.apple.finder.nodename"),
            NSPasteboard.PasteboardType("com.apple.finder.pathname"),
            NSPasteboard.PasteboardType("com.apple.finder.metadata"),
            NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
            NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type"),
            NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData"),
            NSPasteboard.PasteboardType("CorePasteboardFlavorType 0x6675726C"),
            NSPasteboard.PasteboardType("CorePasteboardFlavorType 0x75726C20"),
            NSPasteboard.PasteboardType(AppSlotStore.slotType)
        ]
        types.append(contentsOf: NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
        return types
    }()

    static func dropOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        let source = sender.draggingSourceOperationMask
        if source.contains(.copy) { return .copy }
        if source.contains(.generic) { return .generic }
        if source.contains(.link) { return .link }
        if source.contains(.move) { return .move }
        return .generic
    }

    static func firstApplication(from pasteboard: NSPasteboard) -> URL? {
        let bundleTypes: [NSPasteboard.PasteboardType] = [
            .init("com.apple.application-bundle-identifier"),
            .init("com.apple.application"),
            .init("com.apple.application-bundle")
        ]
        for type in bundleTypes {
            if let bundleID = pasteboard.string(forType: type)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return url
            }
        }
        for extraType in ["com.apple.dock.extra", "com.apple.dock.tile"] {
            let type = NSPasteboard.PasteboardType(extraType)
            if let extra = pasteboard.propertyList(forType: type), let url = application(fromPlist: extra) {
                return url
            }
            if let extra = pasteboard.data(forType: type), let url = application(fromDroppedData: extra) {
                return url
            }
        }

        let urlOptions: [[NSPasteboard.ReadingOptionKey: Any]] = [
            [
                .urlReadingFileURLsOnly: true,
                .urlReadingContentsConformToTypes: [UTType.application.identifier, UTType.applicationBundle.identifier, UTType.bundle.identifier]
            ],
            [.urlReadingFileURLsOnly: true],
            [:]
        ]
        for options in urlOptions {
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
               let app = urls.compactMap({ $0.resolvedApplicationURL() }).first {
                return app
            }
        }
        if let filenames = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String],
           let app = filenames.map(URL.init(fileURLWithPath:)).compactMap({ $0.resolvedApplicationURL() }).first {
            return app
        }
        if let names = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("Apple files promise pasteboard type")) as? [String] {
            for name in names {
                if let url = application(fromDroppedString: name) { return url }
            }
        }
        for type in pasteboard.types ?? [] {
            if let plist = pasteboard.propertyList(forType: type), let url = application(fromPlist: plist) {
                return url
            }
            if let string = pasteboard.string(forType: type), let url = application(fromDroppedString: string) {
                return url
            }
            if let data = pasteboard.data(forType: type), let url = application(fromDroppedData: data) {
                return url
            }
        }
        for item in pasteboard.pasteboardItems ?? [] {
            for type in item.types {
                if let plist = item.propertyList(forType: type), let url = application(fromPlist: plist) {
                    return url
                }
                if let string = item.string(forType: type), let url = application(fromDroppedString: string) {
                    return url
                }
                if let data = item.data(forType: type), let url = application(fromDroppedData: data) {
                    return url
                }
            }
        }
        return nil
    }

    private static func application(fromPlist plist: Any) -> URL? {
        if let dict = plist as? [String: Any] {
            let keys = ["bundle-identifier", "bundle identifier", "bundleIdentifier", "CFBundleIdentifier", "id", "path", "url"]
            for key in keys {
                if let id = dict[key] as? String {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                        return url
                    }
                    if let url = application(fromDroppedString: id) {
                        return url
                    }
                }
            }
            if let name = (dict["name"] as? String) ?? (dict["title"] as? String),
               let url = applicationURL(named: name) {
                return url
            }
            for value in dict.values {
                if let url = application(fromPlist: value) { return url }
            }
        }
        if let array = plist as? [Any] {
            for value in array {
                if let url = application(fromPlist: value) { return url }
            }
        }
        if let string = plist as? String {
            return application(fromDroppedString: string)
        }
        if let data = plist as? Data {
            return application(fromDroppedData: data)
        }
        return nil
    }

    private static func application(fromDroppedData data: Data) -> URL? {
        if let unarchived = try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSDictionary.self, NSArray.self, NSString.self, NSNumber.self, NSURL.self],
            from: data
        ), let url = application(fromPlist: unarchived) {
            return url
        }
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let url = application(fromPlist: plist) {
            return url
        }
        if let url = URL(dataRepresentation: data, relativeTo: nil)?.resolvedApplicationURL() {
            return url
        }
        if let string = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) {
            return application(fromDroppedString: string)
        }
        return nil
    }

    fileprivate static func application(fromDroppedString string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let app = url.resolvedApplicationURL() {
            return app
        }
        let decoded = trimmed.removingPercentEncoding ?? trimmed
        let path = decoded.replacingOccurrences(of: "file://", with: "")
        if path.contains("."), !path.contains("/"), !path.contains(" "),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: path) {
            return url
        }
        if let match = path.range(of: #"^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$"#, options: .regularExpression),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: String(path[match])) {
            return url
        }
        if let url = URL(string: path), let app = url.resolvedApplicationURL() {
            return app
        }
        if path.hasPrefix("/") || path.hasSuffix(".app") {
            let resolved = path.hasPrefix("/") ? path : "/Applications/\(path)"
            if let app = URL(fileURLWithPath: resolved).resolvedApplicationURL() {
                return app
            }
        }
        return applicationURL(named: path)
    }

    private static func applicationURL(named name: String) -> URL? {
        let cleaned = name.replacingOccurrences(of: ".app", with: "")
        guard !cleaned.isEmpty, cleaned.count < 80 else { return nil }
        let roots = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Cryptexes/App/System/Applications",
            NSHomeDirectory() + "/Applications"
        ]
        for root in roots {
            let url = URL(fileURLWithPath: root).appendingPathComponent("\(cleaned).app")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}

extension URL {
    func resolvedApplicationURL() -> URL? {
        var current = (self as NSURL).filePathURL ?? self
        guard current.isFileURL else { return nil }
        current = current.standardizedFileURL.resolvingSymlinksInPath()
        if current.pathExtension.lowercased() == "app" { return current }
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
