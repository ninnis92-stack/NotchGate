import Foundation
import SwiftUI

enum SearchTrigger: String, CaseIterable, Identifiable {
    case click
    case keyboard
    case hover

    var id: String { rawValue }

    var title: String {
        switch self {
        case .click: return "Click"
        case .keyboard: return "Shortcut"
        case .hover: return "Hover"
        }
    }
}

enum SearchScope: String, CaseIterable, Identifiable {
    case thisMac
    case files
    case apps
    case web

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thisMac: return "This Mac"
        case .files: return "Files"
        case .apps: return "Apps"
        case .web: return "Web"
        }
    }
}

struct SearchOptions: View {
    @Bindable var layout: NotchCustomization

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Open with", selection: $layout.searchTrigger) {
                ForEach(SearchTrigger.allCases) { trigger in
                    Text(trigger.title).tag(trigger)
                }
            }
            .pickerStyle(.segmented)
            Picker("Default scope", selection: $layout.searchScope) {
                ForEach(SearchScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            Toggle("Show search history", isOn: $layout.searchShowHistory)
            Toggle("Remember recent searches", isOn: $layout.searchRememberHistory)
            Text("Click the search shoulder to open. Cmd+Space stays with system Spotlight. NotchGate search is ⌘⇧F.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 30)
    }
}
