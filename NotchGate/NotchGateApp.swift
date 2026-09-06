import AppKit
import CoreGraphics
import SwiftUI

enum AppPresentation {
    /// Keep NotchGate visible in the Dock so users can always quit or force quit it.
    static let showsDockIcon = true
    static var isStorePreview: Bool {
        #if DEBUG
        CommandLine.arguments.contains("--store-preview")
        #else
        false
        #endif
    }
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static func applyDefaultActivationPolicy() {
        NSApp.setActivationPolicy(showsDockIcon ? .regular : .accessory)
    }
}

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
        AppPresentation.applyDefaultActivationPolicy()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppPresentation.applyDefaultActivationPolicy()
        LicenseManager.shared.start()
        panelController.show()
        #if DEBUG
        if CommandLine.arguments.contains("--show-pricing") {
            DispatchQueue.main.async {
                UtilityWindows.showPricing()
            }
        }
        if CommandLine.arguments.contains("--show-pomodoro") {
            DispatchQueue.main.async {
                PomodoroWindowManager.shared.show()
            }
        }
        if CommandLine.arguments.contains("--show-settings") {
            DispatchQueue.main.async {
                UtilityWindows.showSettings()
            }
        }
        if AppPresentation.isStorePreview {
            let layout = NotchCustomization.shared
            layout.leftShoulder = .search
            layout.rightShoulder = .clock
            layout.showFullscreenShoulders = true
            layout.showMonitoring = true
            layout.showCPUStat = true
            layout.showMemoryStat = true
            layout.showDiskStat = true
            layout.showBattery = true
            layout.showNetwork = true
            layout.showProcesses = false
            layout.showCalendar = true
            layout.showWeather = true
            layout.showNowPlaying = true
            layout.showAppSlots = true
            layout.showSearch = true
            layout.showStatusStrip = false
            layout.showDevices = false
            layout.enableAnimations = true
            ThemeManager.shared.theme = .midnight
            for index in 0..<AppSlotStore.slotCount {
                AppSlotStore.shared.clear(index: index)
            }
            DispatchQueue.main.async { [weak self] in
                self?.panelController.expandForStorePreview()
            }
        }
        #endif
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
        NotchCustomization.shared.overlayLevel.nsLevel
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
    private var spaceHeartbeat: Timer?
    private var collapseWork: DispatchWorkItem?
    private var didInstallObservers = false
    private var didInstallMonitors = false
    private var lastSpaceRestick: TimeInterval = 0
    private var revealedByTopBar = false
    private var lastAppliedFrame: NSRect = .zero
    private var didRequestInitialWidgetPermissions = false

    func show() {
        state.geometry = NotchGeometry.current()
        stats.start(interval: NotchCustomization.shared.refreshInterval)
        OutputVolume.shared.start()
        SystemHUDController.shared.start()
        if NotchCustomization.shared.assignsSearch { SearchService.shared.start() }
        if LicenseManager.isPro {
            if NotchCustomization.shared.showCalendar { calendar.start() }
            if NotchCustomization.shared.showWeather { weather.start() }
            requestInitialWidgetPermissionsIfNeeded()
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
            .environment(NotchAnimationManager.shared)
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
        if !AppPresentation.isRunningTests {
            nowPlaying.start()
        }
    }

    func keepVisible() {
        guard let panel else { return }
        OverlayChrome.apply(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    #if DEBUG
    func expandForStorePreview() {
        state.isExpanded = true
        applyFrame(expanded: true, animated: false, bringForward: true)
    }
    #endif

    private func bindOverlay() {
        flyout.notchPanel = panel
        flyout.stats = stats
        flyout.calendar = calendar
        flyout.weather = weather
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
        startSpaceHeartbeat()
    }

    private func startSpaceHeartbeat() {
        guard spaceHeartbeat == nil else { return }
        let timer = Timer(timeInterval: 1.0, target: self, selector: #selector(pollSpace), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        spaceHeartbeat = timer
    }

    @objc private func pollSpace() {
        let next = NotchGeometry.current()
        if next != state.geometry {
            state.geometry = next
            applyFrame(expanded: state.isExpanded, animated: false)
        }
        restickIfOffActiveSpace()
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
                cancelCollapse()
                if !overPeek, !overPanel { peek.dismiss() }
                setExpanded(true)
                return
            }
            ignoreActivationUntilExit = overIsland
            scheduleCollapse()
            return
        }

        if flyout.isVisible || peek.isVisible {
            if overFlyout || overPeek || overBridge || overIsland {
                cancelCollapse()
                return
            }
            scheduleCollapse()
            return
        }

        if ignoreActivationUntilExit {
            if !overIsland {
                ignoreActivationUntilExit = false
            }
            return
        }

        if overIsland {
            cancelCollapse()
            setExpanded(true)
        }
    }

    /// Bring the island onto this Space while the pointer is in the menu-bar strip.
    private func revealForTopBarHover() {
        guard let panel else { return }
        if !revealedByTopBar {
            revealedByTopBar = true
            lastSpaceRestick = ProcessInfo.processInfo.systemUptime
            OverlayChrome.followActiveSpace(panel)
            applyFrame(expanded: state.isExpanded, animated: false, bringForward: true)
            return
        }
        restickIfOffActiveSpace()
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
            scheduleCollapse()
            return
        }
        cancelCollapse()
        guard !state.isExpanded else { return }
        NotchAnimationManager.shared.applyExpandAnimation()
        setOverlayFront()
        state.isExpanded = true
        applyFrame(expanded: true, animated: true, bringForward: true)
    }

    private func scheduleCollapse() {
        guard collapseWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.collapseWork = nil
            self?.collapseNow()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: work)
    }

    private func cancelCollapse() {
        collapseWork?.cancel()
        collapseWork = nil
    }

    private func collapseNow() {
        #if DEBUG
        guard !AppPresentation.isStorePreview else { return }
        #endif
        cancelCollapse()
        isPointerInside = false
        flyout.dismiss()
        peek.dismiss()
        guard state.isExpanded else { return }
        NotchAnimationManager.shared.applyContractAnimation()
        state.isExpanded = false
        applyFrame(expanded: false, animated: true)
    }

    private func setOverlayFront() {
        guard let panel else { return }
        OverlayChrome.apply(panel)
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        flyout.applyLevel(OverlayChrome.resolvedLevel())
        peek.applyLevel(OverlayChrome.resolvedLevel())
        UtilityWindows.keepAboveOverlay()
    }

    private func applyFrame(expanded: Bool, animated: Bool, bringForward: Bool = false) {
        guard let panel else { return }
        let header = expanded ? state.geometry.wideCollapsedSize.height : state.geometry.collapsedSize.height
        let height = NotchCustomization.shared.expandedPanelHeight(
            collapsedBar: state.geometry.wideCollapsedSize.height,
            isPro: LicenseManager.isPro
        )
        let frame = state.geometry.frame(expanded: expanded, expandedHeight: height)
        let frameChanged = !lastAppliedFrame.equalTo(frame)
        if bringForward || !panel.isVisible {
            OverlayChrome.apply(panel)
        }
        if frameChanged {
            let shouldAnimate = animated
                && NotchAnimationManager.shared.enabled
                && lastAppliedFrame.width > 1
            lastAppliedFrame = frame
            if shouldAnimate {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = NotchAnimationManager.shared.expandDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    context.allowsImplicitAnimation = true
                    panel.animator().setFrame(frame, display: true)
                }
            } else {
                panel.setFrame(frame, display: true, animate: false)
            }
        }
        panel.alphaValue = 1
        if bringForward || !panel.isVisible {
            panel.orderFrontRegardless()
        }
        if let container = panel.contentView as? DragAwareContainer {
            container.isExpanded = expanded
            container.collapsedBarHeight = header
            container.hidesCollapsedShoulders = state.geometry.hidesCollapsedShoulders && !expanded
            container.notchHeight = state.geometry.notchHeight
            container.needsLayout = true
            container.layoutSubtreeIfNeeded()
        }
        SystemHUDController.shared.place(under: panel.frame)
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
        if NotchCustomization.shared.assignsSearch { SearchService.shared.start() }
        if LicenseManager.isPro {
            if NotchCustomization.shared.showCalendar {
                calendar.start()
            } else {
                calendar.stop()
            }
            if NotchCustomization.shared.showWeather {
                weather.start()
            } else {
                weather.stop()
            }
            requestInitialWidgetPermissionsIfNeeded()
        } else {
            calendar.stop()
            weather.stop()
        }
    }

    private func requestInitialWidgetPermissionsIfNeeded() {
        let layout = NotchCustomization.shared
        guard LicenseManager.isPro,
              !didRequestInitialWidgetPermissions,
              !AppPresentation.isRunningTests,
              !AppPresentation.isStorePreview,
              layout.showCalendar || layout.showWeather
        else { return }

        didRequestInitialWidgetPermissions = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self else { return }
            if layout.showCalendar {
                await calendar.requestAccessFromUser()
            }
            if layout.showWeather {
                weather.requestAccessIfNeeded()
            }
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
        let operation = dropOperation(for: sender)
        guard !operation.isEmpty else { return [] }
        peek?.dismiss()
        onDragging?(true)
        needsLayout = true
        layoutSubtreeIfNeeded()
        window?.orderFrontRegardless()
        return operation
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = dropOperation(for: sender)
        guard !operation.isEmpty else {
            onDragging?(false)
            return []
        }
        onDragging?(true)
        needsLayout = true
        layoutSubtreeIfNeeded()
        return operation
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
        let local = convert(sender.draggingLocation, from: nil)
        if let slotsRow, !slotsRow.isHidden, slotsRow.frame.insetBy(dx: -8, dy: -8).contains(local) {
            return slotsRow.acceptDrop(sender)
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

    private func dropOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        store?.canHandle(sender.draggingPasteboard) == true
            ? PasteboardApps.dropOperation(for: sender)
            : []
    }
}
