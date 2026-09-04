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
                SearchService.shared.search(SearchService.shared.query)
            }
        }
    }
}

struct SearchFlyout: View {
    @Bindable var service: SearchService
    var accent: Color
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                TextField("Search files, apps, or calculate", text: Binding(
                    get: { service.query },
                    set: { service.query = $0; service.search($0) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .focused($fieldFocused)
                .onSubmit { submitFirst() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if service.results.isEmpty {
                        Text(service.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? "Type to search this Mac."
                             : "No results on this Mac.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.vertical, 8)
                    } else {
                        ForEach(service.results) { hit in
                            Button {
                                if hit.kind == .history {
                                    service.query = hit.title
                                    service.search(hit.title)
                                    fieldFocused = true
                                } else {
                                    service.submit(hit)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.title)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.92))
                                        .lineLimit(1)
                                    Text(hit.subtitle)
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.4))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .onAppear {
            service.search(service.query)
            DispatchQueue.main.async {
                fieldFocused = true
            }
        }
    }

    private func submitFirst() {
        if let first = service.results.first(where: { $0.kind != .history }) {
            service.submit(first)
        } else {
            service.remember(service.query)
        }
    }
}

@MainActor
final class SpotlightPanelController {
    static let shared = SpotlightPanelController()
    private var panel: NSPanel?
    private var hosting: NSHostingView<SpotlightPanelView>?

    func show(service: SearchService) {
        UtilityWindows.prepareForStoreKit()
        let root = SpotlightPanelView(service: service)
        if let panel, let hosting {
            hosting.rootView = root
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingView(rootView: root)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 460),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Search"
        panel.isFloatingPanel = true
        panel.level = UtilityWindows.windowLevel
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.hosting = hosting
        self.panel = panel
        service.search(service.query)
    }

    func hide() {
        panel?.orderOut(nil)
        UtilityWindows.restoreAccessoryIfIdle()
    }
}

struct SpotlightPanelView: View {
    @Bindable var service: SearchService
    @Environment(\.controlActiveState) private var active

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search files, apps, or calculate", text: Binding(
                    get: { service.query },
                    set: { service.query = $0; service.search($0) }
                ))
                .textFieldStyle(.plain)
                .onSubmit { submitFirst() }
            }
            .padding(12)
            Divider()
            if service.results.isEmpty {
                Text("No results on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(service.results) { hit in
                    Button {
                        if hit.kind == .history {
                            service.search(hit.title)
                        } else {
                            service.submit(hit)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hit.title)
                                .foregroundStyle(.primary)
                            Text(hit.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.sidebar)
            }
        }
        .frame(minWidth: 380, minHeight: 420)
        .onAppear {
            service.search(service.query)
        }
    }

    private func submitFirst() {
        if let first = service.results.first(where: { $0.kind != .history }) {
            service.submit(first)
        } else {
            service.remember(service.query)
        }
    }
}
