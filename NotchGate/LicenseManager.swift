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
        case .advancedMonitoring: return "Battery, disk, network, and per-app load"
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
    #if DEBUG
    static let bypassPaidGate = true
    #else
    static let bypassPaidGate = false
    #endif
    static var isPro: Bool { shared.isPro }

    private(set) var isPro = false
    private(set) var product: Product?
    private(set) var displayPrice = "$4.99"
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var isStoreAvailable = true
    private(set) var statusMessage: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        isPro = Self.resolvedPro(KeychainLicense.isPro || LicenseBackup.isPro)
    }

    func start() {
        isPro = Self.resolvedPro(KeychainLicense.isPro || LicenseBackup.isPro)
        Task { await loadStore() }
        updatesTask?.cancel()
        updatesTask = Task { await listenForTransactions() }
    }

    func purchase() async {
        statusMessage = nil
        guard let product else {
            statusMessage = isStoreAvailable
                ? "Pro is not available yet. Try Restore Purchases, or check App Store Connect."
                : "The App Store is offline. Your saved license still applies if you already purchased."
            return
        }

        isPurchasing = true
        UtilityWindows.prepareForStoreKit()
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await grant(from: transaction)
                await transaction.finish()
                statusMessage = "NotchGate Pro is unlocked. Thank you."
            case .userCancelled:
                break
            case .pending:
                statusMessage = "This purchase is pending approval."
            @unknown default:
                statusMessage = "Purchase could not be completed."
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        statusMessage = nil
        isRestoring = true
        UtilityWindows.prepareForStoreKit()
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            let entitled = await storeEntitlement()
            if let entitled {
                applyLicense(entitled, persist: entitled || !KeychainLicense.isPro)
            }
            if isPro {
                statusMessage = "Purchases restored."
            } else {
                statusMessage = "No NotchGate Pro purchase was found for this Apple ID."
            }
        } catch {
            applyLicense(KeychainLicense.isPro, persist: false)
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
            // Empty entitlements must not wipe a Keychain license when the product
            // is missing from App Store Connect (typical on the first local builds).
            if let entitled = await storeEntitlement() {
                if entitled {
                    applyLicense(true, persist: true)
                } else if product != nil, !KeychainLicense.isPro, !LicenseBackup.isPro {
                    applyLicense(false, persist: false)
                } else {
                    applyLicense(KeychainLicense.isPro || LicenseBackup.isPro, persist: false)
                }
            }
        } catch {
            isStoreAvailable = false
            applyLicense(KeychainLicense.isPro || LicenseBackup.isPro, persist: false)
            statusMessage = "StoreKit is unavailable. Using the saved license if one exists."
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
            LicenseBackup.isPro = entitled
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

enum LicenseBackup {
    private static let key = "notchgate.license.pro"

    static var isPro: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            Persistence.flush()
        }
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
    static let blockingChanged = Notification.Name("notchgate.utilityBlockingChanged")

    /// Above the notch overlay so Settings/Pro never sit under app slots or peeks.
    static let windowLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 2)

    private static var pricingWindow: NSWindow?
    private static var settingsWindow: NSWindow?
    private static var lastSettingsToggle = Date.distantPast

    static var isBlockingIsland: Bool {
        pricingWindow?.isVisible == true
            || settingsWindow?.isVisible == true
            || NSApp.windows.contains { window in
                window.isVisible && (
                    window.title == "NotchGate Settings"
                        || window.title == "NotchGate Pro"
                )
            }
    }

    static func keepAboveOverlay() {
        guard !NotchCustomization.shared.overlaySettingsWindows else { return }
        let floor = OverlayChrome.resolvedLevel().rawValue + 1
        let level = NSWindow.Level(rawValue: max(windowLevel.rawValue, floor))
        func raise(_ window: NSWindow?) {
            guard let window, window.isVisible else { return }
            window.level = level
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
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func restoreAccessoryIfIdle() {
        if !isBlockingIsland {
            NSApp.setActivationPolicy(.accessory)
        }
        postBlockingChanged()
    }

    static func postBlockingChanged() {
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
            existing.level = windowLevel
            existing.setContentSize(size)
            existing.makeKeyAndOrderFront(nil)
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
        window.level = windowLevel
        window.hidesOnDeactivate = false
        window.contentView = NSHostingView(rootView: root)
        window.center()
        window.makeKeyAndOrderFront(nil)
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
}
