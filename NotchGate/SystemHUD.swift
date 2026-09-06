import AppKit
import CoreGraphics
import IOKit
import SwiftUI

enum DisplayBrightness {
    static func current() -> Double? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        guard let getBrightness else { return nil }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var value: Float = 0
            let status = getBrightness(service, 0, "brightness" as CFString, &value)
            IOObjectRelease(service)
            if status == KERN_SUCCESS {
                return Double(value)
            }
            service = IOIteratorNext(iterator)
        }
        return nil
    }

    private static let getBrightness: GetBrightnessFn? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let symbol = dlsym(handle, "IODisplayGetFloatParameter")
        else { return nil }
        return unsafeBitCast(symbol, to: GetBrightnessFn.self)
    }()
}

private typealias GetBrightnessFn = @convention(c) (io_service_t, IOOptionBits, CFString, UnsafeMutablePointer<Float>) -> kern_return_t

@MainActor
final class SystemHUDController {
    static let shared = SystemHUDController()

    private var panel: NSPanel?
    private var hosting: NSHostingView<SystemHUDView>?
    private var hideWork: DispatchWorkItem?
    private var keyMonitor: Any?
    private var localKeyMonitor: Any?
    private var lastVolume: Double?
    private var lastMuted: Bool?
    private var lastKind: SystemHUDKind?

    func start() {
        OutputVolume.shared.onHardwareChange = { [weak self] in
            self?.showVolume()
        }
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            self?.handleSystemKey(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            self?.handleSystemKey(event)
            return event
        }
    }

    func place(under island: NSRect) {
        guard let panel, panel.isVisible else { return }
        panel.setFrame(frame(under: island), display: true)
    }

    private func handleSystemKey(_ event: NSEvent) {
        guard NotchCustomization.shared.showSystemHUDs else { return }
        let key = Int32((event.data1 & 0xFFFF0000) >> 16)
        let isDown = ((event.data1 & 0x0000FF00) >> 8) == 0x0A
        guard isDown else { return }
        switch key {
        case 0, 1, 7: // sound up / down / mute
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                OutputVolume.shared.readFromHardware()
                self?.showVolume()
            }
        case 2, 3: // brightness up / down
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.showBrightness()
            }
        default:
            break
        }
    }

    private func showVolume() {
        guard NotchCustomization.shared.showSystemHUDs else { return }
        let volume = OutputVolume.shared
        if lastVolume == volume.level, lastMuted == volume.isMuted, lastKind == .volume { return }
        lastVolume = volume.level
        lastMuted = volume.isMuted
        lastKind = .volume
        present(.volume, value: volume.isMuted ? 0 : volume.level, symbol: volume.symbol)
    }

    private func showBrightness() {
        guard NotchCustomization.shared.showSystemHUDs else { return }
        let value = DisplayBrightness.current() ?? 0
        lastKind = .brightness
        present(.brightness, value: value, symbol: "sun.max.fill")
    }

    private func present(_ kind: SystemHUDKind, value: Double, symbol: String) {
        let view = SystemHUDView(kind: kind, value: value, symbol: symbol)
        if panel == nil {
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .canJoinAllApplications]
            panel.isFloatingPanel = true
            panel.level = OverlayChrome.resolvedLevel()
            let hosting = NSHostingView(rootView: view)
            hosting.safeAreaRegions = []
            panel.contentView = hosting
            self.panel = panel
            self.hosting = hosting
        } else {
            hosting?.rootView = view
            panel?.level = OverlayChrome.resolvedLevel()
        }
        guard let panel else { return }
        OverlaySpace.stickToAllSpaces(panel)
        panel.setFrame(frame(under: NSApp.windows.first(where: { $0 is NotchPanel })?.frame ?? .zero), display: true)
        panel.orderFrontRegardless()
        panel.alphaValue = 1
        scheduleHide()
    }

    private func frame(under island: NSRect) -> NSRect {
        let size = NSSize(width: 228, height: 44)
        let screen = NSScreen.screens.first { $0.frame.intersects(island) } ?? NSScreen.main
        let fallback = screen?.frame ?? .zero
        let x: CGFloat
        let y: CGFloat
        if island.width > 1 {
            x = island.midX - size.width / 2
            y = island.minY - size.height - 10
        } else {
            x = fallback.midX - size.width / 2
            y = fallback.maxY - 80
        }
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                self?.panel?.animator().alphaValue = 0
            } completionHandler: {
                self?.panel?.orderOut(nil)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15, execute: work)
    }
}

private enum SystemHUDKind {
    case volume
    case brightness
}

private struct SystemHUDView: View {
    let kind: SystemHUDKind
    let value: Double
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 22)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(Color.white)
                        .frame(width: max(8, proxy.size.width * CGFloat(min(max(value, 0), 1))))
                }
            }
            .frame(height: 6)
            Text("\(Int((min(max(value, 0), 1) * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.92), in: Capsule())
    }
}
