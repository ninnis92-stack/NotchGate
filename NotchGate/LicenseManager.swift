import AppKit
import Foundation
import Security
import StoreKit
import SwiftUI

enum ProFeature: String, CaseIterable, Identifiable {
    case calendar
    case weather
    case advancedMonitoring
    case customThemes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar: return "Calendar"
        case .weather: return "Weather"
        case .advancedMonitoring: return "Advanced monitoring"
        case .customThemes: return "Custom themes"
        }
    }

    var detail: String {
        switch self {
        case .calendar: return "Next event beside the notch"
        case .weather: return "Live local conditions"
        case .advancedMonitoring: return "Battery, disk, and network meters"
        case .customThemes: return "Accent palettes for the expanded panel"
        }
    }

    var symbol: String {
        switch self {
        case .calendar: return "calendar"
        case .weather: return "cloud.sun"
        case .advancedMonitoring: return "waveform.path.ecg"
        case .customThemes: return "paintpalette"
        }
    }

    var isUnlocked: Bool { LicenseManager.isPro }
}

@Observable
@MainActor
final class LicenseManager {
    static let shared = LicenseManager()
    static let productID = "com.notchlens.pro"
    /// Debug Run on this Mac unlocks Pro for preview. Release / Archive stays locked.
    static let bypassPaidGate: Bool = {
        #if DEBUG
        true
        #else
        false
        #endif
    }()
    static var isPro: Bool { shared.isPro }

    private(set) var isPro = false
    private(set) var product: Product?
    private(set) var displayPrice = "$5.99"
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var isStoreAvailable = true
    private(set) var statusMessage: String?

    private var updatesTask: Task<Void, Never>?
    private var hasStarted = false

    private init() {
        isPro = Self.resolvedPro(false)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        // StoreKit is authoritative in Release. Do not trust a locally cached
        // entitlement, which could survive a refund or revocation.
        isPro = Self.resolvedPro(false)
        Task { await loadStore() }
        updatesTask?.cancel()
        updatesTask = Task { await listenForTransactions() }
    }

    func purchase() async {
        statusMessage = nil
        guard let product else {
            statusMessage = isStoreAvailable
                ? "Pro is not available yet. Try Restore Purchases, or check App Store Connect."
                : "The App Store is offline. NotchGate Pro will be available after purchase verification succeeds."
            return
        }

        isPurchasing = true
        UtilityWindows.prepareForStoreKit()
        defer {
            isPurchasing = false
            // StoreKit owns the authentication sheet. Once it dismisses,
            // return focus to the NotchGate window so the result is visible.
            UtilityWindows.prepareForStoreKit()
        }

        do {
            // Give AppKit one turn to finish activating the regular utility
            // window before StoreKit presents its system purchase sheet.
            await Task.yield()
            let result = try await purchaseWithTimeout(product)
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await grant(from: transaction)
                await transaction.finish()
                statusMessage = "NotchGate Pro is unlocked. Thank you."
            case .userCancelled:
                statusMessage = "Purchase cancelled. You can try again or use Restore Purchases."
            case .pending:
                statusMessage = "This purchase is pending approval."
            @unknown default:
                statusMessage = "Purchase could not be completed."
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func purchaseWithTimeout(_ product: Product) async throws -> Product.PurchaseResult {
        try await withThrowingTaskGroup(of: Product.PurchaseResult.self) { group in
            group.addTask {
                try await product.purchase()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 60_000_000_000)
                throw PurchaseFlowError.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw PurchaseFlowError.noResult
            }
            return result
        }
    }

    func restorePurchases() async {
        statusMessage = nil
        isRestoring = true
        UtilityWindows.prepareForStoreKit()
        defer {
            isRestoring = false
            // AppStore.sync() may present an Apple-owned sign-in prompt.
            // Re-raise our utility window after the prompt completes so the
            // user can immediately see the restore result.
            UtilityWindows.prepareForStoreKit()
        }

        do {
            try await AppStore.sync()
            let entitled = await storeEntitlement()
            if let entitled {
                applyLicense(entitled, persist: true)
            }
            if isPro {
                statusMessage = "Purchases restored."
            } else {
                statusMessage = "No NotchGate Pro purchase was found for this Apple ID."
            }
        } catch {
            statusMessage = "Could not restore purchases. \(error.localizedDescription)"
        }
    }

    private func loadStore() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
            if let product {
                displayPrice = product.displayPrice
            }
            isStoreAvailable = true
            if let entitled = await storeEntitlement() {
                applyLicense(entitled, persist: true)
            }
        } catch {
            isStoreAvailable = false
            isPro = Self.resolvedPro(false)
            statusMessage = "StoreKit is unavailable. NotchGate Pro requires purchase verification."
        }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            do {
                let transaction = try checkVerified(result)
                await grant(from: transaction)
                await transaction.finish()
            } catch {
                statusMessage = "Could not verify a store transaction."
            }
        }
    }

    private func grant(from transaction: StoreKit.Transaction) async {
        let entitled = transaction.productID == Self.productID && transaction.revocationDate == nil
        applyLicense(entitled, persist: true)
    }

    private func storeEntitlement() async -> Bool? {
        do {
            var entitled = false
            for await result in Transaction.currentEntitlements {
                let transaction = try checkVerified(result)
                if transaction.productID == Self.productID, transaction.revocationDate == nil {
                    entitled = true
                }
            }
            return entitled
        } catch {
            return nil
        }
    }

    private func applyLicense(_ entitled: Bool, persist: Bool) {
        isPro = Self.resolvedPro(entitled)
        if persist {
            KeychainLicense.isPro = entitled
        }
        NotificationCenter.default.post(name: NotchCustomization.layoutChanged, object: nil)
    }

    private static func resolvedPro(_ entitled: Bool) -> Bool {
        bypassPaidGate || entitled
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}

private enum PurchaseFlowError: LocalizedError {
    case timedOut
    case noResult

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "The purchase sheet did not respond. Check your Apple ID sandbox sign-in and try again."
        case .noResult:
            return "The purchase did not return a result. Try again or use Restore Purchases."
        }
    }
}

enum KeychainLicense {
    private static let service = "com.notchlens.pro.license"
    private static let account = "notchlens-pro"

    static var isPro: Bool {
        get { load() }
        set { save(newValue) }
    }

    private static func load() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return false
        }
        return value == "pro"
    }

    private static func save(_ entitled: Bool) {
        let data = Data((entitled ? "pro" : "free").utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(base as CFDictionary)
        guard entitled else { return }

        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

enum Persistence {
    static func flush() {
        UserDefaults.standard.synchronize()
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
    }
}

@MainActor
enum UtilityWindows {
    enum PopupQuadrant: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    /// Positions a utility window in one of four predictable screen quadrants.
    /// Existing NotchGate windows are treated as obstacles so opening another
    /// popup does not put it directly underneath the previous one.
    static func popupFrame(
        screen: NSRect,
        size: NSSize,
        occupied: [NSRect],
        anchor: NSRect? = nil,
        margin: CGFloat = 24
    ) -> (frame: NSRect, quadrant: PopupQuadrant) {
        let area = screen.insetBy(dx: margin, dy: margin)
        let halfWidth = area.width / 2
        let halfHeight = area.height / 2
        let candidates: [(PopupQuadrant, NSRect)] = [
            (.topLeft, NSRect(x: area.minX, y: area.midY, width: halfWidth, height: halfHeight)),
            (.topRight, NSRect(x: area.midX, y: area.midY, width: halfWidth, height: halfHeight)),
            (.bottomLeft, NSRect(x: area.minX, y: area.minY, width: halfWidth, height: halfHeight)),
            (.bottomRight, NSRect(x: area.midX, y: area.minY, width: halfWidth, height: halfHeight))
        ].map { quadrant, region in
            let x = region.midX - size.width / 2
            let y = region.midY - size.height / 2
            return (quadrant, NSRect(
                x: min(max(x, area.minX), area.maxX - size.width),
                y: min(max(y, area.minY), area.maxY - size.height),
                width: size.width,
                height: size.height
            ))
        }

        func overlap(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
            let intersection = lhs.intersection(rhs)
            guard !intersection.isNull else { return 0 }
            return intersection.width * intersection.height
        }

        let ranked = candidates.enumerated().map { index, candidate in
            let obstacleCost = occupied.reduce(CGFloat.zero) { $0 + overlap(candidate.1, $1) }
            let anchorCost = anchor.map { overlap(candidate.1, $0) * 2 } ?? 0
            return (index, candidate, obstacleCost + anchorCost)
        }.sorted { lhs, rhs in
            if lhs.2 != rhs.2 { return lhs.2 < rhs.2 }
            return lhs.0 < rhs.0
        }
        return (frame: ranked[0].1.1, quadrant: ranked[0].1.0)
    }

    static let blockingChanged = Notification.Name("notchgate.utilityBlockingChanged")

    /// Above the notch overlay so Settings/Pro remain usable.
    static let windowLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 2)
    static let utilityCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllApplications,
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .ignoresCycle
    ]

    private static var pricingWindow: NSWindow?
    private static var settingsWindow: NSWindow?
    private static var lastSettingsToggle = Date.distantPast
    private static var isPostingBlockingChange = false

    private static let utilityTitles: Set<String> = [
        "NotchGate Settings", "NotchGate Pro", "Search", "Pomodoro",
        "System Load", "Processor", "Memory", "Battery", "Disk",
        "Network", "Calendar", "Weather", "Status"
    ]

    static var folderPanelParent: NSWindow? {
        if settingsWindow?.isVisible == true { return settingsWindow }
        if pricingWindow?.isVisible == true { return pricingWindow }
        return nil
    }

    static var isBlockingIsland: Bool {
        NSApp.windows.contains { window in
            window.isVisible && utilityTitles.contains(window.title)
        }
    }

    static func keepAboveOverlay() {
        guard !NotchCustomization.shared.overlaySettingsWindows else { return }
        let floor = OverlayChrome.resolvedLevel().rawValue + 1
        let level = NSWindow.Level(rawValue: max(windowLevel.rawValue, floor))
        func raise(_ window: NSWindow?) {
            guard let window, window.isVisible else { return }
            window.level = level
            if let sheet = window.attachedSheet {
                sheet.level = NSWindow.Level(rawValue: level.rawValue + 8)
                sheet.orderFrontRegardless()
                return
            }
            window.orderFrontRegardless()
        }
        raise(settingsWindow)
        raise(pricingWindow)
        for window in NSApp.windows where window.isVisible && (window.isSheet || window.attachedSheet != nil) {
            if window.title == "NotchGate Settings" || window.title == "NotchGate Pro" || window.isSheet {
                window.level = level
                window.orderFrontRegardless()
            }
        }
    }

    static func prepareForStoreKit() {
        let window = pricingWindow?.isVisible == true ? pricingWindow : settingsWindow
        guard let window, window.isVisible else { return }
        raiseUtilityWindow(window)
    }

    /// Make a user-facing utility window visible above other apps and Spaces.
    /// This is intentionally shared by every popup so the interaction model is
    /// consistent whether it was opened from the shoulder, menu bar, or a
    /// keyboard shortcut.
    static func raiseUtilityWindow(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.level = windowLevel
        window.collectionBehavior = utilityCollectionBehavior
        window.hidesOnDeactivate = false
        window.orderFrontRegardless()
        window.makeKey()
    }

    static func restoreAccessoryIfIdle() {
        if !isBlockingIsland {
            AppPresentation.applyDefaultActivationPolicy()
        }
        postBlockingChanged()
    }

    static func postBlockingChanged() {
        // Window dismissal can synchronously trigger another state change
        // notification. Do not allow NotificationCenter delivery to re-enter
        // itself through the overlay's collapse path.
        guard !isPostingBlockingChange else { return }
        isPostingBlockingChange = true
        defer { isPostingBlockingChange = false }
        NotificationCenter.default.post(name: blockingChanged, object: nil)
    }


    static func showPricing() {
        prepareForStoreKit()
        pricingWindow = present(
            existing: pricingWindow,
            title: "NotchGate Pro",
            size: NSSize(width: 440, height: 620),
            root: PricingView()
                .environment(LicenseManager.shared)
                .environment(ThemeManager.shared)
                .environment(NotchCustomization.shared),
            activateApp: true
        )
    }

    static func showSettings() {
        settingsWindow = present(
            existing: settingsWindow,
            title: "NotchGate Settings",
            size: NSSize(width: 420, height: 720),
            root: SettingsView()
                .environment(LicenseManager.shared)
                .environment(ThemeManager.shared)
                .environment(NotchCustomization.shared),
            activateApp: true
        )
    }

    static func toggleSettings() {
        let now = Date()
        if now.timeIntervalSince(lastSettingsToggle) < 0.18 { return }
        lastSettingsToggle = now
        if settingsWindow?.isVisible == true {
            settingsWindow?.orderOut(nil)
            restoreAccessoryIfIdle()
            return
        }
        showSettings()
    }

    private static func present<V: View>(
        existing: NSWindow?,
        title: String,
        size: NSSize,
        root: V,
        activateApp: Bool
    ) -> NSWindow {
        if activateApp {
            NSApp.activate(ignoringOtherApps: true)
        }
        if let existing {
            existing.setContentSize(size)
            place(existing, size: size)
            raiseUtilityWindow(existing)
            return existing
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: root)
        place(window, size: size)
        raiseUtilityWindow(window)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                restoreAccessoryIfIdle()
            }
        }
        return window
    }

    private static func place(_ window: NSWindow, size: NSSize) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let occupied = NSApp.windows.compactMap { candidate -> NSRect? in
            guard candidate !== window,
                  candidate.isVisible,
                  utilityTitles.contains(candidate.title) else { return nil }
            return candidate.frame
        }
        let anchor = NSApp.windows.first(where: { $0 is NotchPanel })?.frame
        let choice = popupFrame(
            screen: screen.visibleFrame,
            size: size,
            occupied: occupied,
            anchor: anchor
        )
        window.setFrame(choice.frame, display: false)
    }
}
