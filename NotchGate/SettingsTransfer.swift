import AppKit
import Foundation
import UniformTypeIdentifiers

enum SettingsTransfer {
    private static let fileExtension = "json"

    static func export() -> String? {
        let values = UserDefaults.standard.dictionaryRepresentation().reduce(into: [String: Any]()) { result, entry in
            guard entry.key.hasPrefix("notch."), JSONSerialization.isValidJSONObject([entry.key: entry.value]) else { return }
            result[entry.key] = entry.value
        }
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]) else {
            return "Could not create the settings file."
        }

        let panel = NSSavePanel()
        panel.title = "Export NotchGate Settings"
        panel.nameFieldStringValue = "NotchGate Settings.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            return "Settings exported."
        } catch {
            return "Could not export settings. (error.localizedDescription)"
        }
    }

    static func `import`() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Import NotchGate Settings"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let data = try Data(contentsOf: url)
            guard let values = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return "That file is not a NotchGate settings export."
            }
            for (key, value) in values where key.hasPrefix("notch.") {
                UserDefaults.standard.set(value, forKey: key)
            }
            UserDefaults.standard.synchronize()
            NotificationCenter.default.post(name: NotchCustomization.layoutChanged, object: nil)
            return "Settings imported. Reopen Settings to review them."
        } catch {
            return "Could not import settings. (error.localizedDescription)"
        }
    }
}
