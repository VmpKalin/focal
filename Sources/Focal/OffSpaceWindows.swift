import AppKit

/// Windows on other Spaces and in full screen (its own Space), which kAXWindows never reports.
///
/// They can only be found by walking an app's AX element ids, and an app open for days is deep into
/// them (Chrome after a week: seconds of walking). So the walk runs off the main thread, the windows it
/// finds are remembered, and `didFind` tells the switcher to pick them up.
final class OffSpaceWindows: @unchecked Sendable {
    static let shared = OffSpaceWindows()
    static let didFind = Notification.Name("FocalOffSpaceWindowsFound")

    private struct AppState {
        var found: [CGWindowID: AXUIElement] = [:]
        /// Big window-server windows a full walk showed aren't AX windows (Chrome's popups etc.).
        var notWindows: Set<CGWindowID> = []
        var searching = false
    }

    private let lock = NSLock()
    private var apps: [pid_t: AppState] = [:]
    private let queue = DispatchQueue(label: "focal.offspace-windows", qos: .utility)

    func cached(pid: pid_t, id: CGWindowID) -> AXUIElement? {
        lock.withLock { apps[pid]?.found[id] }
    }

    /// The windows among `missing` found so far; starts a background walk for any not looked for yet.
    func windows(pid: pid_t, missing: Set<CGWindowID>) -> [AXUIElement] {
        lock.withLock {
            var st = apps[pid, default: AppState()]
            // Ids the window server no longer lists are closed (or back on this Space, where AX sees them).
            st.found = st.found.filter { missing.contains($0.key) }
            st.notWindows.formIntersection(missing)
            let unknown = missing.subtracting(st.found.keys).subtracting(st.notWindows)
            if !unknown.isEmpty, !st.searching {
                st.searching = true
                queue.async { self.search(pid: pid, for: unknown) }
            }
            apps[pid] = st
            return missing.compactMap { st.found[$0] }
        }
    }

    func forget(exceptRunning pids: Set<pid_t>) {
        lock.withLock { apps = apps.filter { pids.contains($0.key) } }
    }

    private func search(pid: pid_t, for wanted: Set<CGWindowID>) {
        var remaining = wanted
        var found: [CGWindowID: AXUIElement] = [:]
        AX.forEachWindowElement(pid) { el, _ in
            if let id = AX.windowID(el), remaining.remove(id) != nil { found[id] = el }
            return !remaining.isEmpty
        }
        lock.withLock {
            var st = apps[pid, default: AppState()]
            st.found.merge(found) { _, new in new }
            st.notWindows.formUnion(remaining)
            st.searching = false
            apps[pid] = st
        }
        if !found.isEmpty {
            DispatchQueue.main.async { NotificationCenter.default.post(name: Self.didFind, object: nil) }
        }
    }
}
