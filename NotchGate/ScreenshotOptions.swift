import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum ScreenshotSaveLocation: String, CaseIterable, Identifiable {
    case desktop
    case documents
    case notchgate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop: return "Desktop"
        case .documents: return "Documents"
        case .notchgate: return "NotchGate folder"
        }
    }

    var directory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .desktop:
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? home.appendingPathComponent("Desktop")
        case .documents:
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? home.appendingPathComponent("Documents")
        case .notchgate:
            return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("NotchGate", isDirectory: true)
                .appendingPathComponent("SavedScreenshots", isDirectory: true)
                ?? home.appendingPathComponent("Pictures/NotchGate/SavedScreenshots", isDirectory: true)
        }
    }
}

enum ScreenshotImageFormat: String, CaseIterable, Identifiable {
    case png
    case jpeg
    case webp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .webp: return "WebP"
        }
    }

    var pathExtension: String { rawValue }

    var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .webp: return UTType("org.webmproject.webp") ?? .png
        }
    }
}

struct ScreenshotOptions: View {
    @Bindable var layout: NotchCustomization

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Save to", selection: $layout.screenshotSaveLocation) {
                ForEach(ScreenshotSaveLocation.allCases) { location in
                    Text(location.title).tag(location)
                }
            }
            Toggle("Show screenshot preview in notch", isOn: $layout.screenshotShowPreview)
            Toggle("Include cursor", isOn: $layout.screenshotIncludeCursor)
            Toggle("Show window shadows", isOn: $layout.screenshotWindowShadows)
            Picker("Format", selection: $layout.screenshotFormat) {
                ForEach(ScreenshotImageFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .pickerStyle(.segmented)
            Text("Screen Recording is requested only when you capture. Images stay on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 30)
    }
}
