import AppKit

/// A window as reported by the window server.
struct CGWin {
    let id: CGWindowID
    let pid: pid_t
    let frame: CGRect
    let isOnScreen: Bool
}

/// A window snapshot that can be persisted (contexts, layouts).
struct WindowSnapshot: Codable, Hashable {
    var windowID: CGWindowID
    var pid: pid_t
    var bundleID: String?
    var appName: String
    var title: String
    var frame: CGRect
}

/// A window the switcher can show.
struct WindowItem {
    let id: CGWindowID
    let pid: pid_t
    let app: NSRunningApplication
    let title: String
    let frame: CGRect
    let isMinimized: Bool
    let isOnScreen: Bool
    let isFullScreen: Bool
    let element: AXUIElement
}

enum Windows {
    static let ownPID = ProcessInfo.processInfo.processIdentifier

    static func regularApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ownPID && !$0.isTerminated
        }
    }

    /// Apps whose windows the switcher lists: regular apps, plus menu-bar ("accessory") apps that
    /// currently own a real window — Docker Desktop, for example, registers as an accessory app.
    /// System UI agents (AutoFill, Control Centre, input helpers...) are left out.
    static func windowOwningApps(_ big: [pid_t: [CGWin]]) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != ownPID, !app.isTerminated else { return false }
            switch app.activationPolicy {
            case .regular: return true
            case .accessory: return !(app.bundleIdentifier ?? "").hasPrefix("com.apple.") && big[app.processIdentifier] != nil
            default: return false
            }
        }
    }

    /// Normal (layer 0) windows, front to back.
    static func cgWindows(onScreenOnly: Bool) -> [CGWin] {
        let opts: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { d in
            guard (d[kCGWindowLayer as String] as? Int) == 0,
                  let id = d[kCGWindowNumber as String] as? CGWindowID,
                  let pid = d[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  (d[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let b = d[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: b as CFDictionary),
                  frame.width >= 120, frame.height >= 80 else { return nil }
            return CGWin(id: id, pid: pid, frame: frame, isOnScreen: d[kCGWindowIsOnscreen as String] as? Bool ?? false)
        }
    }

    /// Windows the user can actually see right now (not hidden behind others), front to back.
    static func visibleWindowIDs(minVisibleFraction: CGFloat = 0.2) -> [CGWin] {
        let screens = NSScreen.screens.map(Screens.fullFrame)
        var covered: [CGRect] = []
        var result: [CGWin] = []
        for w in cgWindows(onScreenOnly: true) {
            let step = max(16, min(w.frame.width, w.frame.height) / 12)
            var total = 0, visible = 0
            var y = w.frame.minY + step / 2
            while y < w.frame.maxY {
                var x = w.frame.minX + step / 2
                while x < w.frame.maxX {
                    let p = CGPoint(x: x, y: y)
                    if screens.contains(where: { $0.contains(p) }) {
                        total += 1
                        if !covered.contains(where: { $0.contains(p) }) { visible += 1 }
                    }
                    x += step
                }
                y += step
            }
            if total > 0, CGFloat(visible) / CGFloat(total) >= minVisibleFraction { result.append(w) }
            covered.append(w.frame)
        }
        return result
    }

    /// All switchable windows on every Space, ordered by recency.
    ///
    /// kAXWindows only reports windows on the Spaces currently shown, so windows on other desktops
    /// and in full screen (which is its own Space) are invisible to it, exactly like in App Exposé.
    /// For apps where the window server knows more windows than AX reports, the remaining ones are
    /// found by enumerating AX element tokens (~30 ms per app, only done for those apps).
    static func items() -> [WindowItem] {
        let zOrder = Dictionary(cgWindows(onScreenOnly: true).enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let bigByPID = Dictionary(grouping: cgWindows(onScreenOnly: false).filter { $0.frame.width >= 250 && $0.frame.height >= 200 }, by: \.pid)
        var items: [WindowItem] = []
        for app in windowOwningApps(bigByPID) {
            var els = AX.windows(app.processIdentifier)
            let known = Set(els.compactMap(AX.windowID))
            let missing = Set((bigByPID[app.processIdentifier] ?? []).map(\.id)).subtracting(known)
            if !missing.isEmpty {
                els += AX.bruteForceWindows(app.processIdentifier).filter { AX.windowID($0).map(missing.contains) ?? false }
            }
            for el in els {
                guard let id = AX.windowID(el) else { continue }
                let title = AX.string(el, kAXTitleAttribute) ?? ""
                items.append(WindowItem(
                    id: id, pid: app.processIdentifier, app: app,
                    title: title.isEmpty ? (app.localizedName ?? "") : title,
                    frame: AX.frame(el) ?? .zero,
                    isMinimized: AX.bool(el, kAXMinimizedAttribute) ?? false,
                    isOnScreen: zOrder[id] != nil, isFullScreen: AX.bool(el, "AXFullScreen") ?? false, element: el))
            }
        }
        return items.sorted { (zOrder[$0.id] ?? Int.max, $0.isMinimized ? 1 : 0) < (zOrder[$1.id] ?? Int.max, $1.isMinimized ? 1 : 0) }
    }

    /// Big windows of `pid` that the window server knows about but that are not on a visible Space.
    static func offSpaceWindows(_ pid: pid_t) -> [CGWin] {
        cgWindows(onScreenOnly: false).filter { $0.pid == pid && !$0.isOnScreen && $0.frame.width >= 250 && $0.frame.height >= 200 }
    }

    static func snapshot(_ wins: [CGWin]) -> [WindowSnapshot] {
        var axByPID: [pid_t: [AXUIElement]] = [:]
        return wins.compactMap { w in
            let els = axByPID[w.pid] ?? AX.windows(w.pid)
            axByPID[w.pid] = els
            guard let el = els.first(where: { AX.windowID($0) == w.id }),
                  let app = NSRunningApplication(processIdentifier: w.pid) else { return nil }
            return WindowSnapshot(windowID: w.id, pid: w.pid, bundleID: app.bundleIdentifier,
                                  appName: app.localizedName ?? "?", title: AX.string(el, kAXTitleAttribute) ?? "",
                                  frame: w.frame)
        }
    }
}
