import AppKit
import CoreGraphics
import SwiftUI

enum AppPresentation {
    /// Keep NotchGate visible in the Dock while it is running, including the App Store build.
    static var showsDockIcon: Bool {
        true
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
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    UtilityWindows.toggleSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .appTermination) {
                Button("Quit NotchGate") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
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
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController.show()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if UtilityWindows.isBlockingIsland { return }
        panelController.show()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Menu-bar overlays do not have a normal document close cycle. Hide
        // them immediately so Dock > Quit gives visible confirmation before
        // AppKit finishes terminating the process.
        NSApp.windows.forEach { $0.orderOut(nil) }
        return .terminateNow
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
        if let cached = screenSaverCache, now - cached.at < 1.2 {
            return cached.value
        }
        // Avoid system-wide window enumeration; the public overlay levels are
        // sufficient and do not inspect unrelated windows.
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

enum AutoHidePolicy {
    static func shouldExpandOnIslandHover(
        enabled: Bool,
        style: AutoHideRevealStyle,
        pointerInExpansionZone: Bool = true
    ) -> Bool {
        pointerInExpansionZone && (!enabled || style == .open)
    }

    static func showsExpandControl(
        enabled: Bool, style: AutoHideRevealStyle, expanded: Bool
    ) -> Bool {
        enabled && style == .closed && !expanded
    }

    static func shouldHide(
        enabled: Bool,
        expanded: Bool,
        flyoutVisible: Bool,
        utilityBlocking: Bool,
        pointerInRevealZone: Bool
    ) -> Bool {
        enabled && !expanded && !flyoutVisible && !utilityBlocking && !pointerInRevealZone
    }
}

@MainActor
final class NotchPanelController: NSObject {
    private var panel: NotchPanel?
    private let state = NotchState()
    private let stats = SystemMonitor()
    private let calendar = CalendarService()
    private let weather = WeatherService()
    private let apps = AppSlotStore.shared
    private let flyout = WidgetFlyoutController()
    private var isPointerInside = false
    private var ignoreActivationUntilExit = false
    private var isEvaluatingPointer = false
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var spaceHeartbeat: Timer?
    private var pointerHeartbeat: Timer?
    private var collapseWork: DispatchWorkItem?
    private var autoHideWork: DispatchWorkItem?
    private var isAutoHidden = false
    private var didInstallObservers = false
    private var didInstallMonitors = false
    private var lastSpaceRestick: TimeInterval = 0
    private var revealedByTopBar = false
    private var lastAppliedFrame: NSRect = .zero

    func show() {
        flyout.configure(stats: stats, calendar: calendar, weather: weather, apps: apps)
        stats.onRefresh = { stats in
            NotificationService.shared.evaluate(stats: stats)
        }
        state.geometry = NotchGeometry.current()
        stats.start(interval: NotchCustomization.shared.refreshInterval)
        OutputVolume.shared.start()
        SystemHUDController.shared.start()
        MusicService.shared.start()
        if NotchCustomization.shared.assignsSearch { SearchService.shared.start() }
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
                apps: apps,
                flyout: flyout,
                onHoverChange: { _ in },
                
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
        container.hosting = hosting
        container.addSubview(hosting)

        let gear = SettingsGearView()
        container.gear = gear
        container.addSubview(gear)

        let expandControl = ExpandControlView()
        expandControl.target = self
        expandControl.action = #selector(expandFromControl)
        container.expandControl = expandControl
        container.addSubview(expandControl)

        let slotsRow = AppSlotsRowView()
        slotsRow.store = apps
        slotsRow.reload()
        container.slotsRow = slotsRow
        container.addSubview(slotsRow)


        panel.contentView = container
        panel.orderFrontRegardless()
        panel.alphaValue = 1
        self.panel = panel
        bindOverlay()
        applyFrame(expanded: false, animated: false)
        startMouseTracking()
        if NotchCustomization.shared.autoHide { scheduleAutoHide() }
        installObservers()
    }

    func keepVisible() {
        guard let panel else { return }
        OverlayChrome.apply(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    private func bindOverlay() {
        // Feature details stay in the main notch panel. There is no secondary
        // dropdown window to bind or manage.
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
            let clicked = event.type == .leftMouseDown
            DispatchQueue.main.async {
                // Queued events can lag behind the heartbeat during a resize.
                // Evaluate the current pointer, not an obsolete edge crossing.
                self?.evaluatePointer(NSEvent.mouseLocation)
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
        // A transparent overlay can miss mouseMoved callbacks while another
        // app owns the active space. Polling the pointer location keeps the
        // top-edge reveal reliable without requiring the user to click first.
        pointerHeartbeat = Timer.scheduledTimer(
            timeInterval: 0.08,
            target: self,
            selector: #selector(pollPointer),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(pointerHeartbeat!, forMode: .common)
        startSpaceHeartbeat()
    }

    @objc private func pollPointer() {
        evaluatePointer(NSEvent.mouseLocation)
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
            // The flyout itself is a blocking utility window, but it must not
            // be dismissed by the pointer pass that notices it just opened.
            // Settings/Pro still use the normal dismissal path.
            collapseNow(dismissFlyout: !flyout.isVisible)
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
        let overBridge = flyout.bridgeContains(point, island: panelFrame)
        let overTopBar = state.geometry.topBarRevealZone.contains(point)
        let overIsland = state.geometry.closestActivationZone.contains(point)
        let autoHideEnabled = NotchCustomization.shared.autoHide
        let overExpansionZone = state.geometry.autoHideExpansionZone.contains(point)

        if overTopBar {
            cancelAutoHide()
            revealForTopBarHover()
        } else if revealedByTopBar, !state.isExpanded,
                  !panelFrame.insetBy(dx: -6, dy: -6).contains(point) {
            revealedByTopBar = false
        }

        if state.isExpanded {
            let overPanel = state.geometry.holdZone(panelFrame: panelFrame).contains(point)
            if overPanel || overFlyout || overBridge {
                ignoreActivationUntilExit = false
                cancelCollapse()
                setExpanded(true)
                return
            }
            ignoreActivationUntilExit = overIsland
            scheduleCollapse()
            return
        }

        if flyout.isVisible {
            // A flyout is a user-opened utility window. Once it is open, do
            // not let the island's hover-collapse timer dismiss it just
            // because the pointer moved over another app or toward the
            // flyout. It remains available until toggled or closed.
            cancelCollapse()
            return
        }

        if !isAutoHidden && panelFrame.insetBy(dx: -6, dy: -6).contains(point) {
            cancelAutoHide()
        } else if autoHideEnabled && !state.isExpanded && !overTopBar {
            scheduleAutoHide()
        }

        if ignoreActivationUntilExit {
            if !overIsland {
                ignoreActivationUntilExit = false
            }
            return
        }

        if overIsland {
            cancelCollapse()
            if AutoHidePolicy.shouldExpandOnIslandHover(
                enabled: autoHideEnabled,
                style: NotchCustomization.shared.autoHideRevealStyle,
                pointerInExpansionZone: !autoHideEnabled || overExpansionZone
            ) {
                setExpanded(true)
            }
        }
    }

    @objc private func expandFromControl() {
        guard AutoHidePolicy.showsExpandControl(
            enabled: NotchCustomization.shared.autoHide,
            style: NotchCustomization.shared.autoHideRevealStyle,
            expanded: state.isExpanded
        ) else { return }
        setExpanded(true)
    }

    /// Bring the island onto this Space while the pointer is in the menu-bar strip.
    private func revealForTopBarHover() {
        guard let panel else { return }
        isAutoHidden = false
        panel.alphaValue = 1
        if !revealedByTopBar {
            revealedByTopBar = true
            // Reassigning Spaces on every edge entry can briefly recompose
            // the closed island. Only move it when it actually lost its Space.
            if !panel.isOnActiveSpace || !panel.isVisible {
                lastSpaceRestick = ProcessInfo.processInfo.systemUptime
                OverlayChrome.followActiveSpace(panel)
            }
            applyFrame(expanded: state.isExpanded, animated: false, bringForward: true)
            return
        }
        restickIfOffActiveSpace()
    }

    private func setExpanded(_ expanded: Bool) {
        isPointerInside = expanded
        guard expanded else {
            scheduleCollapse()
            return
        }
        cancelAutoHide()
        isAutoHidden = false
        panel?.alphaValue = 1
        cancelCollapse()
        guard !state.isExpanded else { return }
        NotchAnimationManager.shared.applyExpandAnimation()
        setOverlayFront()
        state.isExpanded = true
        applyFrame(expanded: true, animated: true, bringForward: true)
    }

    private func scheduleCollapse() {
        guard collapseWork == nil else { return }
        let preserveFlyout = flyout.isVisible
        let work = DispatchWorkItem { [weak self] in
            self?.collapseWork = nil
            self?.collapseNow(dismissFlyout: !preserveFlyout)
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func cancelCollapse() {
        collapseWork?.cancel()
        collapseWork = nil
    }

    private func scheduleAutoHide() {
        guard !isAutoHidden, autoHideWork == nil,
              AutoHidePolicy.shouldHide(
                enabled: NotchCustomization.shared.autoHide,
                expanded: state.isExpanded,
                flyoutVisible: flyout.isVisible,
                utilityBlocking: UtilityWindows.isBlockingIsland,
                pointerInRevealZone: pointerKeepsIslandVisible
              ) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, AutoHidePolicy.shouldHide(
                enabled: NotchCustomization.shared.autoHide,
                expanded: self.state.isExpanded,
                flyoutVisible: self.flyout.isVisible,
                utilityBlocking: UtilityWindows.isBlockingIsland,
                pointerInRevealZone: self.pointerKeepsIslandVisible
            ) else {
                self?.autoHideWork = nil
                return
            }
            self.autoHideWork = nil
            self.isAutoHidden = true
            self.revealedByTopBar = false
            self.panel?.alphaValue = 0
        }
        autoHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func cancelAutoHide() {
        autoHideWork?.cancel()
        autoHideWork = nil
    }

    private var pointerKeepsIslandVisible: Bool {
        let point = NSEvent.mouseLocation
        return state.geometry.topBarRevealZone.contains(point)
            || (!isAutoHidden && panel?.frame.insetBy(dx: -6, dy: -6).contains(point) == true)
    }

    private func collapseNow(dismissFlyout: Bool = true) {
        cancelCollapse()
        isPointerInside = false
        if dismissFlyout {
            flyout.dismiss()
        }
        guard state.isExpanded else { return }
        NotchAnimationManager.shared.applyContractAnimation()
        state.isExpanded = false
        applyFrame(expanded: false, animated: true)
        if NotchCustomization.shared.autoHide { scheduleAutoHide() }
    }

    private func setOverlayFront() {
        guard let panel else { return }
        OverlayChrome.apply(panel)
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        flyout.applyLevel(OverlayChrome.resolvedLevel())
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
        panel.alphaValue = isAutoHidden ? 0 : 1
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
        if !NotchCustomization.shared.autoHide {
            cancelAutoHide()
            isAutoHidden = false
            panel?.alphaValue = 1
        } else if !state.isExpanded {
            scheduleAutoHide()
        }
        bindOverlay()
        if NotchCustomization.shared.assignsSearch { SearchService.shared.start() }
        if LicenseManager.isPro {
            if NotchCustomization.shared.showCalendar { calendar.start() }
            if NotchCustomization.shared.showWeather { weather.start() }
        }
    }

    @objc private func slotsChanged() {
        guard let container = panel?.contentView as? DragAwareContainer else { return }
        container.slotsRow?.store = apps
        container.slotsRow?.reload()
        container.needsLayout = true
    }

    @objc private func utilityWindowsChanged() {
        if UtilityWindows.isBlockingIsland {
            ignoreActivationUntilExit = true
            // A newly opened flyout is itself a blocking utility window, but
            // it must remain visible until the user toggles it or closes it.
            collapseNow(dismissFlyout: !flyout.isVisible)
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

final class ExpandControlView: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Open NotchGate panel")
        imagePosition = .imageOnly
        bezelStyle = .inline
        isBordered = false
        contentTintColor = NSColor.white.withAlphaComponent(0.92)
        toolTip = "Open NotchGate panel"
        setAccessibilityLabel("Open NotchGate panel")
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class DragAwareContainer: NSView {
    var store: AppSlotStore?
    var hosting: NSView?
    var gear: SettingsGearView?
    var expandControl: ExpandControlView?
    var slotsRow: AppSlotsRowView?
    var isExpanded = false
    var collapsedBarHeight: CGFloat = 40
    var notchHeight: CGFloat = 32
    var hidesCollapsedShoulders = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
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

        let showExpand = AutoHidePolicy.showsExpandControl(
            enabled: NotchCustomization.shared.autoHide,
            style: NotchCustomization.shared.autoHideRevealStyle,
            expanded: isExpanded
        )
        expandControl?.isHidden = !showExpand
        expandControl?.frame = NSRect(
            x: 8,
            y: bounds.height - notchHeight / 2 - 12,
            width: 24,
            height: 24
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
        if let expandControl, !expandControl.isHidden, expandControl.frame.contains(point) {
            return expandControl
        }
        if let gear, !gear.isHidden, gear.frame.contains(point) {
            return gear
        }
        if let slotsRow, !slotsRow.isHidden, slotsRow.frame.contains(point) {
            return slotsRow.hitTest(point) ?? slotsRow
        }
        return hosting?.hitTest(point) ?? super.hitTest(point)
    }

}
