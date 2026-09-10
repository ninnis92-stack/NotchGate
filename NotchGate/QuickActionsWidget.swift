import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppSlotsView: View {
    var store: AppSlotStore

    @Environment(NotchCustomization.self) private var layout

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: layout.appSlotsHeight)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

final class AppSlotsRowView: NSView {
    var store: AppSlotStore?
    private var cells: [AppSlotCellView] = []
    private var signature = ""
    private weak var pressedCell: AppSlotCellView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for index in 0..<AppSlotStore.slotCount {
            let cell = AppSlotCellView()
            cell.index = index
            cell.row = self
            addSubview(cell)
            cells.append(cell)
        }
        registerForDraggedTypes(PasteboardApps.dragTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func reloadIfNeeded() {
        guard let store else { return }
        let layout = NotchCustomization.shared
        let next = store.slots.map { app in
            "\(app?.id.uuidString ?? "empty"):\(app?.bundleIdentifier ?? "")"
        }.joined(separator: "|") + "|\(layout.appSlotStyle.rawValue)|\(layout.showAppLabels)"
        if next != signature {
            signature = next
            reload()
            return
        }
        for cell in cells {
            cell.setHighlighted(store.hoveredSlot == cell.index)
        }
    }

    func reload() {
        guard let store else { return }
        let layout = NotchCustomization.shared
        for cell in cells {
            cell.store = store
            cell.style = layout.appSlotStyle
            cell.showsLabel = layout.appSlotStyle == .list || layout.showAppLabels
            cell.reload(app: store.slots[safe: cell.index] ?? nil, highlighted: store.hoveredSlot == cell.index)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let style = NotchCustomization.shared.appSlotStyle
        let columns = max(style.columns, 1)
        let rows = max(style.rows, 1)
        let spacing: CGFloat = style == .list ? 6 : 8
        let width = max((bounds.width - spacing * CGFloat(columns - 1)) / CGFloat(columns), 28)
        let height = max((bounds.height - spacing * CGFloat(rows - 1)) / CGFloat(rows), 28)
        for (index, cell) in cells.enumerated() {
            let column = index % columns
            let row = index / columns
            let y = bounds.height - CGFloat(row + 1) * height - CGFloat(row) * spacing
            cell.frame = NSRect(
                x: CGFloat(column) * (width + spacing),
                y: y,
                width: width,
                height: height
            )
        }
        store?.dropRowFrame = convert(bounds, to: nil)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        for cell in cells.reversed() where cell.frame.contains(local) {
            return cell
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        pressedCell = cells.first(where: { $0.frame.contains(local) })
        pressedCell?.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        pressedCell?.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        pressedCell?.mouseUp(with: event)
        pressedCell = nil
    }

    override func rightMouseUp(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if let cell = cells.first(where: { $0.frame.contains(local) }) {
            cell.rightMouseUp(with: event)
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        highlight(sender)
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        highlight(sender)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        store?.hoveredSlot = nil
        for cell in cells { cell.setHighlighted(false) }
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        store?.hoveredSlot = nil
        for cell in cells { cell.setHighlighted(false) }
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        acceptDrop(sender)
    }

    @discardableResult
    func acceptDrop(_ sender: NSDraggingInfo) -> Bool {
        let index = slotIndex(for: sender)
        let ok = store?.handleDragging(sender, onto: index) ?? false
        store?.hoveredSlot = nil
        reload()
        return ok
    }

    func finishInternalDrag(from source: Int, screenPoint: NSPoint) -> Bool {
        guard let store, store.slots.indices.contains(source) else { return false }
        let windowPoint = window?.convertPoint(fromScreen: screenPoint) ?? screenPoint
        let local = convert(windowPoint, from: nil)
        guard bounds.insetBy(dx: -16, dy: -16).contains(local) else { return false }
        let dest = slotIndex(atLocalPoint: local)
        store.move(from: source, to: dest)
        store.draggingIndex = nil
        store.hoveredSlot = nil
        reload()
        return true
    }

    private func highlight(_ sender: NSDraggingInfo) {
        let index = slotIndex(for: sender)
        store?.hoveredSlot = index
        for cell in cells {
            cell.setHighlighted(cell.index == index)
        }
    }

    private func slotIndex(for sender: NSDraggingInfo) -> Int {
        slotIndex(atLocalPoint: convert(sender.draggingLocation, from: nil))
    }

    func slotIndex(atLocalPoint point: NSPoint) -> Int {
        if let cell = cells.first(where: { $0.frame.contains(point) }) {
            return cell.index
        }
        return cells.min { lhs, rhs in
            hypot(lhs.frame.midX - point.x, lhs.frame.midY - point.y)
                < hypot(rhs.frame.midX - point.x, rhs.frame.midY - point.y)
        }?.index ?? 0
    }
}

/// Overlay panels are rarely key, so a normal NSImageView draws the inactive (grey) look.
private final class AlwaysActiveIconView: NSImageView {
    override var allowsVibrancy: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: bounds,
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }
}

final class AppSlotCellView: NSView, NSDraggingSource {
    var index = 0
    var store: AppSlotStore?
    weak var row: AppSlotsRowView?
    var style: AppSlotStyle = .grid
    var showsLabel = false
    private let iconView = AlwaysActiveIconView()
    private let nameField = NSTextField(labelWithString: "")
    private let plus = NSTextField(labelWithString: "+")
    private var app: PinnedApp?
    private var tracking: NSTrackingArea?
    private var mouseDownPoint: NSPoint?
    private var isDraggingSlot = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.isEnabled = true
        iconView.animates = false
        iconView.refusesFirstResponder = true
        iconView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        iconView.setContentHuggingPriority(.defaultLow, for: .vertical)
        nameField.font = .systemFont(ofSize: 9, weight: .medium)
        nameField.textColor = NSColor.white.withAlphaComponent(0.78)
        nameField.alignment = .center
        nameField.lineBreakMode = .byTruncatingTail
        nameField.isBezeled = false
        nameField.drawsBackground = false
        nameField.isSelectable = false
        plus.font = .systemFont(ofSize: 14, weight: .semibold)
        plus.textColor = NSColor.white.withAlphaComponent(0.72)
        plus.alignment = .center
        plus.isBezeled = false
        plus.drawsBackground = false
        plus.isSelectable = false
        plus.isEditable = false
        plus.refusesFirstResponder = true
        plus.isSelectable = false
        addSubview(iconView)
        addSubview(nameField)
        addSubview(plus)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func reload(app: PinnedApp?, highlighted: Bool) {
        self.app = app
        iconView.isHidden = app == nil
        plus.isHidden = app != nil
        nameField.isHidden = app == nil || !showsLabel
        let icon = app?.icon()
        icon?.isTemplate = false
        iconView.image = icon
        iconView.isEnabled = true
        nameField.stringValue = app?.displayName ?? ""
        setHighlighted(highlighted)
        if let app {
            toolTip = app.isInstalled ? app.displayName : "\(app.displayName) isn’t installed"
        } else {
            toolTip = "Click to choose an app"
        }
        needsLayout = true
    }

    func setHighlighted(_ highlighted: Bool) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(highlighted ? 0.16 : 0.07).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(highlighted ? 0.5 : 0.12).cgColor
    }

    override func layout() {
        super.layout()
        if showsLabel, app != nil {
            let nameHeight: CGFloat = 12
            let side = min(28, bounds.width - 8, bounds.height - nameHeight - 8)
            iconView.frame = NSRect(
                x: (bounds.width - side) / 2,
                y: bounds.height - side - 4,
                width: side,
                height: side
            )
            nameField.frame = NSRect(x: 3, y: 3, width: bounds.width - 6, height: nameHeight)
        } else {
            let side = min(style == .list ? 28 : 32, bounds.width - 10, bounds.height - 10)
            iconView.frame = NSRect(
                x: (bounds.width - side) / 2,
                y: (bounds.height - side) / 2,
                width: side,
                height: side
            )
            nameField.frame = .zero
        }
        plus.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTracking()
    }

    private func updateTracking() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        setHighlighted(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHighlighted(false)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        isDraggingSlot = false
        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
            store?.chooseApp(for: index)
            mouseDownPoint = nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownPoint, !isDraggingSlot else { return }
        let location = convert(event.locationInWindow, from: nil)
        let distance = hypot(location.x - mouseDownPoint.x, location.y - mouseDownPoint.y)
        guard distance >= 4 else { return }
        guard let app, let store else { return }
        store.draggingIndex = index

        let item = NSPasteboardItem()
        item.setString("\(index)", forType: NSPasteboard.PasteboardType(AppSlotStore.slotType))
        let drag = NSDraggingItem(pasteboardWriter: item)
        let grab = iconView.frame == .zero ? bounds : iconView.frame
        drag.setDraggingFrame(grab, contents: app.icon())
        beginDraggingSession(with: [drag], event: event, source: self)
        isDraggingSlot = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownPoint = nil }
        guard !isDraggingSlot else { return }
        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
            return
        }
        let pinned = (store?.slots.indices.contains(index) == true) ? store?.slots[index] : app
        if let pinned {
            pinned.launch()
        } else {
            store?.chooseApp(for: index)
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let source = index
        if operation.isEmpty {
            _ = row?.finishInternalDrag(from: source, screenPoint: screenPoint)
        }
        store?.draggingIndex = nil
        isDraggingSlot = false
        mouseDownPoint = nil
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(openApp), #selector(showInFinder):
            return app?.isInstalled == true
        case #selector(forceQuit):
            return app?.isRunning == true
        default:
            return true
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        let menu = NSMenu()
        if let app {
            menu.addItem(actionItem("Open", #selector(openApp), enabled: app.isInstalled))
            menu.addItem(actionItem("Force Quit", #selector(forceQuit), enabled: app.isRunning))
            menu.addItem(actionItem("Show in Finder", #selector(showInFinder), enabled: app.isInstalled))
            menu.addItem(.separator())
            menu.addItem(actionItem("Remove from Notch", #selector(removeApp), enabled: true))
        }
        menu.addItem(actionItem("Choose App…", #selector(choose), enabled: true))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func actionItem(_ title: String, _ selector: Selector, enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    @objc private func openApp() { app?.launch() }
    @objc private func forceQuit() { app?.forceQuit() }
    @objc private func showInFinder() { app?.revealInFinder() }
    @objc private func choose() { store?.chooseApp(for: index) }
    @objc private func removeApp() { store?.clear(index: index) }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
