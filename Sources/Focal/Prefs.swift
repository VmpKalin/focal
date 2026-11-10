import Foundation
import os

let log = Logger(subsystem: "dev.focal.app", category: "focal")

/// User preferences (UserDefaults keys shared with the SwiftUI settings via @AppStorage).
enum Prefs {
    enum Key {
        static let autoSummon = "autoSummon"
        static let pullFromOtherDisplay = "pullFromOtherDisplay"
        static let pullFromOtherSpace = "pullFromOtherSpace"
        static let reopenWhenNoWindows = "reopenWhenNoWindows"
        static let switcherBringsHere = "switcherBringsHere"
        static let trackContexts = "trackContexts"
        static let contextDwell = "contextDwell"
        static let ignoredApps = "ignoredApps"
        static let maximizeOnDisplayMove = "maximizeOnDisplayMove"
        static let switcherStyle = "switcherStyle"
        static let replaceCommandTab = "replaceCommandTab"
        static let language = "language"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.autoSummon: true,
            Key.pullFromOtherDisplay: true,
            Key.pullFromOtherSpace: true,
            Key.reopenWhenNoWindows: true,
            Key.switcherBringsHere: true,
            Key.trackContexts: true,
            Key.contextDwell: 1.5,
            Key.ignoredApps: "com.apple.finder",
            Key.maximizeOnDisplayMove: true,
            Key.switcherStyle: "list",
            Key.replaceCommandTab: true,
            Key.language: "system",
        ])
    }

    static func bool(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
    static var contextDwell: Double { max(0.5, UserDefaults.standard.double(forKey: Key.contextDwell)) }

    static var ignoredBundleIDs: Set<String> {
        Set((UserDefaults.standard.string(forKey: Key.ignoredApps) ?? "")
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
    }

    static var supportDirectory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Focal")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
