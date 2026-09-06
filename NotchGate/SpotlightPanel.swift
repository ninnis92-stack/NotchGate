import AppKit
import SwiftUI

struct SearchWidget: View {
    var service: SearchService
    var accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
            Text(service.history.first ?? "Search")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            if NotchCustomization.shared.searchTrigger != .hover {
                SearchService.shared.open()
            }
        }
    }
}

struct SearchFlyout: View {
    @Bindable var service: SearchService
    var accent: Color
    @FocusState private var fieldFocused: Bool

    var body: some View {
        SearchSessionView(service: service, accent: accent, compact: true, fieldFocused: $fieldFocused)
            .onAppear {
                service.search(service.query)
                DispatchQueue.main.async { fieldFocused = true }
            }
    }
}

struct SearchSessionView: View {
    @Bindable var service: SearchService
    var accent: Color
    var compact: Bool
    var fieldFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: compact ? 13 : 18, weight: .semibold))
                    .foregroundStyle(accent)
                TextField("Search this Mac", text: Binding(
                    get: { service.query },
                    set: { service.search($0) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: compact ? 13 : 22, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .focused(fieldFocused)
                .onSubmit { service.submitSelected() }
            }
            .padding(.horizontal, compact ? 10 : 18)
            .padding(.vertical, compact ? 8 : 16)
            .background {
                if compact {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                }
            }

            if !compact {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if service.results.isEmpty {
                            Text(service.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                 ? "Search names and contents on this Mac."
                                 : "No matching apps or files.")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.4))
                                .padding(.vertical, 12)
                                .padding(.horizontal, compact ? 8 : 14)
                        } else {
                            ForEach(Array(service.results.enumerated()), id: \.element.id) { index, hit in
                                SearchHitRow(
                                    hit: hit,
                                    accent: accent,
                                    selected: index == service.selectedIndex
                                ) {
                                    service.selectedIndex = index
                                    if hit.kind == .history {
                                        service.search(hit.title)
                                        fieldFocused.wrappedValue = true
                                    } else {
                                        service.submit(hit)
                                    }
                                }
                                .id(hit.id)
                            }
                        }
                    }
                    .padding(.horizontal, compact ? 0 : 8)
                    .padding(.vertical, compact ? 0 : 8)
                }
                .onChange(of: service.selectedIndex) { _, index in
                    guard service.results.indices.contains(index) else { return }
                    proxy.scrollTo(service.results[index].id, anchor: .center)
                }
            }
            .frame(maxHeight: .infinity)

            if !compact {
                HStack(spacing: 12) {
                    hint("↩", "Open")
                    hint("⌘↩", "Finder")
                    hint("esc", "Close")
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
        }
        .onKeyPress(.downArrow) {
            service.moveSelection(1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            service.moveSelection(-1)
            return .handled
        }
        .onKeyPress(.escape) {
            service.close()
            return .handled
        }
        .onKeyPress { press in
            if press.key == .return, press.modifiers.contains(.command) {
                service.revealSelected()
                return .handled
            }
            return .ignored
        }
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

private struct SearchHitRow: View {
    let hit: SearchHit
    var accent: Color
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SearchHitIcon(hit: hit)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(1)
                    Text(hit.subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? accent.opacity(0.28) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SearchHitIcon: View {
    let hit: SearchHit

    var body: some View {
        Group {
            if let url = hit.url, url.isFileURL {
                Image(nsImage: AppIconCache.image(for: url))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    private var symbol: String {
        switch hit.kind {
        case .web: return "globe"
        case .calculator: return "plus.forwardslash.minus"
        case .history: return "clock"
        case .app: return "app.fill"
        case .file: return "doc"
        }
    }
}

@MainActor
final class SpotlightPanelController {
    static let shared = SpotlightPanelController()
    private var panel: SpotlightSearchPanel?
    private var hosting: NSHostingView<SpotlightPanelView>?
    private var resignObserver: NSObjectProtocol?

    func show(service: SearchService) {
        UtilityWindows.prepareForStoreKit()
        let root = SpotlightPanelView(service: service)
        if let panel, let hosting {
            hosting.rootView = root
            position(panel)
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingView(rootView: root)
        let panel = SpotlightSearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = UtilityWindows.windowLevel
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentView = hosting
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.hosting = hosting
        self.panel = panel

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if SearchService.shared.isOpen {
                    SearchService.shared.close()
                }
            }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        UtilityWindows.restoreAccessoryIfIdle()
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let size = NSSize(width: 560, height: 460)
        panel.setFrame(
            NSRect(
                x: screen.midX - size.width / 2,
                y: screen.midY + 36,
                width: size.width,
                height: size.height
            ),
            display: true
        )
    }
}

final class SpotlightSearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        SearchService.shared.close()
    }
}

struct SpotlightPanelView: View {
    @Bindable var service: SearchService
    @FocusState private var fieldFocused: Bool

    var body: some View {
        SearchSessionView(service: service, accent: Color.white.opacity(0.92), compact: false, fieldFocused: $fieldFocused)
            .frame(minWidth: 520, minHeight: 420)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.96))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.45), radius: 28, y: 12)
            }
            .padding(10)
            .onAppear {
                DispatchQueue.main.async { fieldFocused = true }
            }
    }
}
