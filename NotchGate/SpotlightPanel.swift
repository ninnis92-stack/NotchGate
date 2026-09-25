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

    var isVisible: Bool { panel?.isVisible == true }

    func show(service: SearchService) {
        UtilityWindows.prepareForStoreKit()
        let root = SpotlightPanelView(service: service)
        if let panel, let hosting {
            hosting.rootView = root
            UtilityWindows.raiseUtilityWindow(panel)
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
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        panel.center()
        UtilityWindows.raiseUtilityWindow(panel)
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
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search This Mac", text: Binding(
                    get: { service.query },
                    set: { service.query = $0; service.search($0) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($fieldFocused)
                .onSubmit { submitFirst() }
                if !service.query.isEmpty {
                    Button { service.query = ""; service.search("") } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.quaternary.opacity(0.65))
            HStack {
                Picker("Scope", selection: Binding(
                    get: { NotchCustomization.shared.searchScope },
                    set: { service.setScope($0) }
                )) {
                    ForEach(SearchScope.allCases.filter { $0 != .web }) { scope in
                        Text(scope == .thisMac ? "This Mac" : scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Spacer()
                Text(resultSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
            if service.results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: service.query.isEmpty ? "magnifyingglass" : "folder.badge.questionmark")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text(service.query.isEmpty ? "Search This Mac" : "No results")
                        .font(.headline)
                    Text(service.query.isEmpty ? "Search by file name or content." : "Try a different name or search term.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(service.results) { hit in
                    SearchResultRow(hit: hit)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { service.submit(hit) }
                        .contextMenu {
                            if hit.url != nil {
                                Button("Open") { service.submit(hit) }
                                Button("Show in Finder") { service.reveal(hit) }
                            }
                            if hit.kind == .calculator {
                                Button("Copy Result") { service.submit(hit) }
                            }
                        }
                        .onTapGesture {
                            if hit.kind == .history {
                                service.query = hit.title
                                service.search(hit.title)
                                fieldFocused = true
                            }
                        }
                }
                .listStyle(.inset)
                .overlay(alignment: .bottom) {
                    Text("Double-click to open · Right-click for Finder actions")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 520)
        .onAppear {
            service.search(service.query)
            fieldFocused = true
        }
    }

    private var resultSummary: String {
        let count = service.results.filter { $0.kind != .history }.count
        return count == 1 ? "1 result" : "\(count) results"
    }

    private func submitFirst() {
        if let first = service.results.first(where: { $0.kind != .history }) {
            service.submit(first)
        } else {
            service.remember(service.query)
        }
    }
}

private struct SearchResultRow: View {
    let hit: SearchHit

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(hit.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(hit.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 3) {
                Text(kindLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let modified = hit.modified {
                    Text(modified, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if let size = hit.size {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(hit.title), \(kindLabel), \(hit.subtitle)")
    }

    private var icon: NSImage {
        if let url = hit.url { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSImage(systemSymbolName: hit.kind == .history ? "clock" : "doc", accessibilityDescription: nil) ?? NSImage()
    }

    private var kindLabel: String {
        if hit.kind == .history { return "Recent search" }
        if hit.isDirectory { return "Folder" }
        if hit.kind == .app { return "Application" }
        if hit.kind == .calculator { return "Calculator" }
        if hit.kind == .web { return "Web" }
        return "File"
    }
}
