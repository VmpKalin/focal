import AppKit

/// Apps on disk, so the switcher can also launch what isn't running (Spotlight-style).
@MainActor
enum InstalledApps {
    struct App {
        let name: String
        let url: URL
        let searchable: String

        var item: SwitchItem {
            SwitchItem(id: "i\(url.path)", kind: .launch(url), title: name, subtitle: tr("not running", "не запущено"),
                       icon: NSWorkspace.shared.icon(forFile: url.path), symbol: nil, badges: [tr("launch", "запустити")])
        }
    }

    nonisolated private static let roots = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                                NSHomeDirectory() + "/Applications"]
    private static var cache: [App] = []
    private static var scannedAt = Date.distantPast

    /// Never blocks: a scan takes ~0.3 s, too slow for ⌘Tab, so a stale list is
    /// refreshed in the background (at most once a minute) and used next time.
    static func all() -> [App] {
        if Date().timeIntervalSince(scannedAt) > 60 {
            scannedAt = Date()
            Task.detached(priority: .utility) {
                let apps = scan()
                await MainActor.run { cache = apps }
            }
        }
        return cache
    }

    /// The name Finder and the Dock show. Some apps call themselves something shorter
    /// inside (Visual Studio Code is "Code"), so search needs both.
    static func fileName(_ app: NSRunningApplication) -> String {
        app.bundleURL?.deletingPathExtension().lastPathComponent ?? ""
    }

    nonisolated private static func scan() -> [App] {
        let fm = FileManager.default
        var seen = Set<URL>()
        var apps: [App] = []
        func add(_ url: URL) {
            let url = url.standardizedFileURL
            guard seen.insert(url).inserted else { return }
            let file = url.deletingPathExtension().lastPathComponent
            let bundleName = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String ?? file
            let name = fm.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            apps.append(App(name: name, url: url, searchable: "\(name) \(file) \(bundleName)".lowercased()))
        }
        for root in roots {
            for url in (try? fm.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isDirectoryKey])) ?? [] {
                if url.pathExtension == "app" {
                    add(url)
                } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    // Vendor folders like "Adobe Premiere Pro 2025/".
                    for inner in (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [] where inner.pathExtension == "app" {
                        add(inner)
                    }
                }
            }
        }
        return apps
    }
}
