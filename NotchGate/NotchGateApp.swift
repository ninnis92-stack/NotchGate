import AppKit
import CoreGraphics
import SwiftUI

@Observable
final class NotchState {
    var isExpanded = false
    var isDragTargeted = false
    var geometry = NotchGeometry.current()
}

@main
struct NotchGateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("NotchGate", systemImage: "rectangle.inset.filled") {
            Button("NotchGate Pro…") {
                UtilityWindows.showPricing()
            }
            Button("Settings…") {
                UtilityWindows.toggleSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            Button("Restore Purchases") {
                Task { await LicenseManager.shared.restorePurchases() }
            }
            Divider()
            Button("Quit NotchGate") {
                NSApp.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
        Settings {
            SettingsView()
                .environment(LicenseManager.shared)
                .environment(ThemeManager.shared)
                .environment(NotchCustomization.shared)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    UtilityWindows.toggleSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let panelController = NotchPanelController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        LicenseManager.shared.start()
        panelController.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController.show()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if UtilityWindows.isBlockingIsland { return }
        panelController.show()
    }

    func applicationDidResignActive(_ notification: Notification) {
        panelController.keepVisible()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Persistence.flush()
    }
}

enum OverlayChrome {
    static let standardLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
    static let behavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .ignoresCycle
    ]

    static func resolvedLevel() -> NSWindow.Level {
        let chosen = NotchCustomization.shared.overlayLevel.nsLevel
        if shouldYieldToScreenSaver(), NotchCustomization.shared.overlayLevel != .screenSaver {
            return .popUpMenu
        }
        return chosen
    }

    static func apply(_ window: NSWindow?) {
        guard let window else { return }
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .canJoinAllApplications
        ]
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        if let panel = window as? NSPanel {
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = true
        }
        // isFloatingPanel resets level to .floating (3). Set the real level after.
        window.level = resolvedLevel()
        OverlaySpace.stickToAllSpaces(window)
    }

    /// Land on the newly active Space (including Full Screen), then become sticky again.
    static func followActiveSpace(_ window: NSWindow?) {
        guard let window else { return }
        window.collectionBehavior = [
            .moveToActiveSpace,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .canJoinAllApplications
        ]
        window.hidesOnDeactivate = false
        if let panel = window as? NSPanel {
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = true
        }
        window.level = resolvedLevel()
        window.orderFrontRegardless()
        DispatchQueue.main.async {
            apply(window)
            window.orderFrontRegardless()
        }
    }

    private static var screenSaverCache: (at: TimeInterval, value: Bool)?

    /// Stay below a foreign screen-saver / lock window unless the user chose that overlay.
    private static func shouldYieldToScreenSaver() -> Bool {
        if NotchCustomization.shared.overlayLevel == .screenSaver {
            return false
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let cached = screenSaverCache, now - cached.at < 0.35 {
            return cached.value
        }
        let saver = Int(CGWindowLevelForKey(.screenSaverWindow))
        let ours = Set(NSApp.windows.map(\.windowNumber))
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            screenSaverCache = (now, false)
            return false
        }
        for window in info {
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            guard layer >= saver else { continue }
            let number = window[kCGWindowNumber as String] as? Int ?? 0
            if ours.contains(number) { continue }
            screenSaverCache = (now, true)
            return true
        }
        screenSaverCache = (now, false)
        return false
    }
}

final class NotchPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchPanelController: NSObject {
    private var panel: NotchPanel?
    private let state = NotchState()
    private let stats = SystemMonitor()
    private let calendar = CalendarService()
    private let weather = WeatherService()
    private let nowPlaying = NowPlayingService()
    private let apps = AppSlotStore.shared
    private let flyout = WidgetFlyoutController()
    private let peek = AppPeekController()
    private var isPointerInside = false
    private var ignoreActivationUntilExit = false
    private var isEvaluatingPointer = false
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var pointerPoll: Timer?
    private var didInstallObservers = false
    private var didInstallMonitors = false
    private var lastSpaceRestick: TimeInterval = 0
    private var revealedByTopBar = false
    private var lastTopBarFront: TimeInterval = 0

    func show() {
        state.geometry = NotchGeometry.current()
        stats.start(interval: NotchCustomization.shared.refreshInterval)
        OutputVolume.shared.start()
        if NotchCustomization.shared.showSearch { SearchService.shared.start() }
        ScreenshotManager.shared.onWillCapture = { [weak self] in
            self?.panel?.orderOut(nil)
        }
        ScreenshotManager.shared.onDidCapture = { [weak self] in
            self?.panel?.orderFrontRegardless()
            self?.evaluatePointer(NSEvent.mouseLocation)
        }
        if LicenseManager.isPro {
            if NotchCustomization.shared.showCalendar { calendar.start() }
            if NotchCustomization.shared.showWeather { weather.start() }
        }

        if panel != nil {
            bindOverlay()
            if !UtilityWindows.isBlockingIsland {
                OverlayChrome.apply(panel)
                panel?.orderFrontRegardless()
                applyFrame(expanded: state.isExpanded, animated: false)
            } else {
                state.isExpanded = false
                applyFrame(expanded: false, animated: false)
            }
            startMouseTracking()
            nowPlaying.start()
            return
        }

        let panel = NotchPanel(
            contentRect: state.geometry.frame(expanded: false),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        OverlayChrome.apply(panel)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovable = false

        let hosting = FirstMouseHostingView(
            rootView: ContentView(
                state: state,
                stats: stats,
                calendar: calendar,
                weather: weather,
                nowPlaying: nowPlaying,
                apps: apps,
                flyout: flyout,
                onHoverChange: { _ in },
                onDragTargeted: { [weak self] targeted in
                    self?.handleDrag(targeted)
                }
            )
            .environment(LicenseManager.shared)
            .environment(ThemeManager.shared)
            .environment(NotchCustomization.shared)
            .environment(PomodoroService.shared)
            .ignoresSafeArea(edges: .all)
        )
        hosting.autoresizingMask = []
        hosting.safeAreaRegions = []
        hosting.unregisterDraggedTypes()

        let container = DragAwareContainer(frame: .zero)
        container.store = apps
        container.peek = peek
        container.onDragging = { [weak self] targeted in
            self?.handleDrag(targeted)
        }
        container.hosting = hosting
        container.addSubview(hosting)

        let gear = SettingsGearView()
        container.gear = gear
        container.addSubview(gear)

        let slotsRow = AppSlotsRowView()
        slotsRow.store = apps
        slotsRow.peek = peek
        slotsRow.onDragging = { [weak self] targeted in
            self?.handleDrag(targeted)
        }
        slotsRow.reload()
        container.slotsRow = slotsRow
        container.addSubview(slotsRow)

        panel.contentView = container
        panel.registerForDraggedTypes(PasteboardApps.dragTypes)
        panel.orderFrontRegardless()
        panel.alphaValue = 1
        self.panel = panel
        bindOverlay()
        applyFrame(expanded: false, animated: false)
        startMouseTracking()
        installObservers()
        nowPlaying.start()
    }

    func keepVisible() {
        guard let panel else { return }
        OverlayChrome.apply(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    private func bindOverlay() {
        flyout.notchPanel = panel
        flyout.stats = stats
        flyout.calendar = calendar
        flyout.weather = weather
        flyout.nowPlaying = nowPlaying
        flyout.apps = apps
        peek.notchPanel = panel
        peek.onVisibilityChange = { [weak self] _ in
            self?.evaluatePointer(NSEvent.mouseLocation)
        }
        flyout.onVisibilityChange = { [weak self] _ in
            self?.evaluatePointer(NSEvent.mouseLocation)
        }
    }

    private func installObservers() {
        guard !didInstallObservers else { return }
        didInstallObservers = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(layoutChanged),
            name: NotchCustomization.layoutChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(slotsChanged),
            name: AppSlotStore.slotsChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(utilityWindowsChanged),
            name: UtilityWindows.blockingChanged,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSNotification.Name("com.apple.spaces.didChange"),
            object: nil
        )
    }

    private func startMouseTracking() {
        guard !didInstallMonitors else { return }
        didInstallMonitors = true
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            let location = NSEvent.mouseLocation
            let clicked = event.type == .leftMouseDown
            DispatchQueue.main.async {
                self?.evaluatePointer(location)
                if clicked { self?.openSettingsIfClickingGear() }
            }
        }
        // Do not intercept leftMouseDown locally — that duplicate-opens then
        // closes Settings when the gear also receives the click.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.evaluatePointer(NSEvent.mouseLocation)
            return event
        }
        startPointerPoll()
    }

    private func startPointerPoll() {
        guard pointerPoll == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 90.0, target: self, selector: #selector(pollPointer), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        pointerPoll = timer
    }

    @objc private func pollPointer() {
        let next = NotchGeometry.current()
        if next != state.geometry {
            state.geometry = next
            applyFrame(expanded: state.isExpanded, animated: false)
        }
        restickIfOffActiveSpace()
        evaluatePointer(NSEvent.mouseLocation)
    }

    private func restickIfOffActiveSpace() {
        guard let panel else { return }
        guard !panel.isOnActiveSpace || !panel.isVisible else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSpaceRestick > 0.6 else { return }
        lastSpaceRestick = now
        OverlayChrome.followActiveSpace(panel)
    }

    private func openSettingsIfClickingGear() {
        guard let panel, let container = panel.contentView as? DragAwareContainer, let gear = container.gear else { return }
        guard gear.frame.width > 1 else { return }
        let onScreen = panel.convertToScreen(gear.frame.insetBy(dx: -4, dy: -4))
        if onScreen.contains(NSEvent.mouseLocation) {
            UtilityWindows.toggleSettings()
        }
    }

    private func evaluatePointer(_ point: NSPoint) {
        guard !isEvaluatingPointer else { return }
        isEvaluatingPointer = true
        defer { isEvaluatingPointer = false }

        if UtilityWindows.isBlockingIsland {
            ignoreActivationUntilExit = true
            collapseNow()
            return
        }

        let panelFrame = panel?.frame ?? .zero
        let dragging = state.isDragTargeted || apps.draggingIndex != nil
        if dragging {
            ignoreActivationUntilExit = false
            setExpanded(true)
            return
        }

        let overFlyout = flyout.contains(point)
        let overPeek = peek.contains(point)
        let overBridge = flyout.bridgeContains(point, island: panelFrame)
        let overTopBar = state.geometry.topBarRevealZone.contains(point)
        let overIsland = state.geometry.closestActivationZone.contains(point)

        if overTopBar {
            revealForTopBarHover()
        } else if revealedByTopBar, !state.isExpanded {
            revealedByTopBar = false
        }

        if state.isExpanded {
            let overPanel = state.geometry.holdZone(panelFrame: panelFrame).contains(point)
            if overPanel || overFlyout || overPeek || overBridge {
                ignoreActivationUntilExit = false
                if !overPeek, !overPanel { peek.dismiss() }
                setExpanded(true)
                return
            }
            ignoreActivationUntilExit = overIsland
            collapseNow()
            return
        }

        if flyout.isVisible || peek.isVisible {
            if overFlyout || overPeek || overBridge || overIsland {
                return
            }
            collapseNow()
            return
        }

        if ignoreActivationUntilExit {
            if !overIsland {
                ignoreActivationUntilExit = false
            }
            return
        }

        if overIsland {
            setExpanded(true)
        }
    }

    /// Bring the island onto this Space while the pointer is in the menu-bar strip.
    private func revealForTopBarHover() {
        guard let panel else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if !revealedByTopBar {
            revealedByTopBar = true
            lastSpaceRestick = now
            lastTopBarFront = now
            OverlayChrome.followActiveSpace(panel)
            applyFrame(expanded: state.isExpanded, animated: false)
            panel.orderFrontRegardless()
            return
        }
        guard now - lastTopBarFront > 0.2 else { return }
        lastTopBarFront = now
        OverlayChrome.apply(panel)
        panel.orderFrontRegardless()
    }

    private func handleDrag(_ targeted: Bool) {
        state.isDragTargeted = targeted
        if targeted {
            peek.dismiss()
            ignoreActivationUntilExit = false
            setExpanded(true)
            panel?.level = OverlayChrome.resolvedLevel()
        } else {
            panel?.level = OverlayChrome.resolvedLevel()
            evaluatePointer(NSEvent.mouseLocation)
        }
    }

    private func setExpanded(_ expanded: Bool) {
        isPointerInside = expanded
        guard expanded else {
            collapseNow()
            return
        }
        guard !state.isExpanded else { return }
        setOverlayFront(true)
        state.isExpanded = true
        applyFrame(expanded: true, animated: true)
    }

    private func collapseNow() {
        isPointerInside = false
        flyout.dismiss()
        peek.dismiss()
        guard state.isExpanded else { return }
        state.isExpanded = false
        applyFrame(expanded: false, animated: true)
        setOverlayFront(false)
    }

    private func setOverlayFront(_ front: Bool) {
        guard let panel else { return }
        OverlayChrome.apply(panel)
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        flyout.applyLevel(OverlayChrome.resolvedLevel())
        peek.applyLevel(OverlayChrome.resolvedLevel())
        UtilityWindows.keepAboveOverlay()
    }

    private func applyFrame(expanded: Bool, animated: Bool) {
        guard let panel else { return }
        let header = expanded ? state.geometry.wideCollapsedSize.height : state.geometry.collapsedSize.height
        let height = NotchCustomization.shared.expandedPanelHeight(
            collapsedBar: state.geometry.wideCollapsedSize.height,
            isPro: LicenseManager.isPro
        )
        let frame = state.geometry.frame(expanded: expanded, expandedHeight: height)
        OverlayChrome.apply(panel)
        panel.setFrame(frame, display: true, animate: false)
        panel.setFrameOrigin(NSPoint(x: frame.minX, y: frame.minY))
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        if let container = panel.contentView as? DragAwareContainer {
            container.isExpanded = expanded
            container.collapsedBarHeight = header
            container.hidesCollapsedShoulders = state.geometry.hidesCollapsedShoulders && !expanded
            container.notchHeight = state.geometry.notchHeight
            container.needsLayout = true
            container.layoutSubtreeIfNeeded()
        }
    }

    @objc private func screensChanged() {
        state.geometry = NotchGeometry.current()
        applyFrame(expanded: state.isExpanded, animated: false)
        lastSpaceRestick = ProcessInfo.processInfo.systemUptime
        OverlayChrome.followActiveSpace(panel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            OverlayChrome.apply(self.panel)
            self.panel?.orderFrontRegardless()
            self.applyFrame(expanded: self.state.isExpanded, animated: false)
        }
        evaluatePointer(NSEvent.mouseLocation)
    }

    @objc private func layoutChanged() {
        state.geometry = NotchGeometry.current()
        stats.start(interval: NotchCustomization.shared.refreshInterval)
        applyFrame(expanded: state.isExpanded, animated: true)
        bindOverlay()
        if !NotchCustomization.shared.showAppPreviews {
            peek.dismiss()
        }
        if NotchCustomization.shared.showSearch { SearchService.shared.start() }
        if LicenseManager.isPro {
            if NotchCustomization.shared.showCalendar { calendar.start() }
            if NotchCustomization.shared.showWeather { weather.start() }
        }
    }

    @objc private func slotsChanged() {
        guard let container = panel?.contentView as? DragAwareContainer else { return }
        container.slotsRow?.store = apps
        container.slotsRow?.peek = peek
        container.slotsRow?.reload()
        container.needsLayout = true
    }

    @objc private func utilityWindowsChanged() {
        if UtilityWindows.isBlockingIsland {
            ignoreActivationUntilExit = true
            collapseNow()
        } else {
            evaluatePointer(NSEvent.mouseLocation)
        }
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        appearance = NSAppearance(named: .darkAqua)
        layer?.opacity = 1
    }
}

final class DragAwareContainer: NSView {
    var onDragging: ((Bool) -> Void)?
    var store: AppSlotStore?
    var peek: AppPeekController?
    var hosting: NSView?
    var gear: SettingsGearView?
    var slotsRow: AppSlotsRowView?
    var isExpanded = false
    var collapsedBarHeight: CGFloat = 40
    var notchHeight: CGFloat = 32
    var hidesCollapsedShoulders = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(PasteboardApps.dragTypes)
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.actions = [
            "opacity": NSNull(),
            "bounds": NSNull(),
            "frame": NSNull(),
            "position": NSNull(),
            "hidden": NSNull()
        ]
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(PasteboardApps.dragTypes)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }

    override func layout() {
        super.layout()
        hosting?.frame = bounds
        layoutChrome()
    }

    func layoutChrome() {
        let gearSize = NotchGeometry.settingsGearSize
        gear?.isHidden = false
        gear?.frame = NSRect(
            x: bounds.width - NotchGeometry.settingsGearTrailing - gearSize,
            y: bounds.height - notchHeight / 2 - gearSize / 2,
            width: gearSize,
            height: gearSize
        )

        let showSlots = isExpanded && NotchCustomization.shared.showAppSlots
        slotsRow?.isHidden = !showSlots
        if showSlots, let slotsRow {
            let inset = NotchCustomization.shared.slotRowTopInset(
                collapsedBar: collapsedBarHeight,
                isPro: LicenseManager.isPro
            )
            let height = NotchCustomization.shared.appSlotsHeight
            slotsRow.frame = NSRect(
                x: 14,
                y: bounds.height - inset - height,
                width: max(bounds.width - 28, 40),
                height: height
            )
            slotsRow.reloadIfNeeded()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let gear, !gear.isHidden, gear.frame.contains(point) {
            return gear
        }
        if let slotsRow, !slotsRow.isHidden, slotsRow.frame.contains(point) {
            return slotsRow.hitTest(point) ?? slotsRow
        }
        return hosting?.hitTest(point) ?? super.hitTest(point)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        peek?.dismiss()
        onDragging?(true)
        needsLayout = true
        layoutSubtreeIfNeeded()
        window?.orderFrontRegardless()
        return PasteboardApps.dropOperation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragging?(true)
        needsLayout = true
        layoutSubtreeIfNeeded()
        return PasteboardApps.dropOperation(for: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if store?.draggingIndex == nil {
            onDragging?(false)
        }
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onDragging?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { onDragging?(false) }
        layoutSubtreeIfNeeded()
        if let slotsRow, !slotsRow.isHidden {
            let local = convert(sender.draggingLocation, from: nil)
            if slotsRow.frame.insetBy(dx: -8, dy: -8).contains(local) {
                return slotsRow.acceptDrop(sender)
            }
        }
        guard let store else { return false }
        let index: Int
        if let slotsRow, !slotsRow.isHidden {
            index = slotsRow.slotIndex(atLocalPoint: slotsRow.convert(sender.draggingLocation, from: nil))
        } else {
            index = store.slotIndex(atWindowPoint: sender.draggingLocation) ?? store.hoveredSlot ?? 0
        }
        return store.handleDragging(sender, onto: index)
    }
}
