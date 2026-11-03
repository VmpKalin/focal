import AppKit

/// A "context" is the set of windows you were actually looking at, e.g. Chrome + a series player.
struct WindowContext: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    /// Front to back.
    var windows: [WindowSnapshot]

    var key: Set<CGWindowID> { Set(windows.map(\.windowID)) }

    var label: String {
        var seen = Set<String>()
        return windows.map(\.appName).filter { seen.insert($0).inserted }.joined(separator: " + ")
    }

    var detail: String { windows.map { $0.title.isEmpty ? $0.appName : $0.title }.joined(separator: " · ") }
}

/// Remembers which windows were on screen together, so ⌥` can bring back the previous set
/// in one keystroke (like ⌘Tab, but for a whole group of windows).
@MainActor
final class ContextTracker: ObservableObject {
    @Published private(set) var history: [WindowContext] = []
    private var timer: Timer?
    private var candidate: (key: [CGWindowID], since: Date)?
    private let maxHistory = 25
    private let url = Prefs.supportDirectory.appendingPathComponent("contexts.json")

    func start() {
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([WindowContext].self, from: data) {
            history = saved
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard Prefs.bool(Prefs.Key.trackContexts), AX.isTrusted, !Actions.isBusy else { return }
        let visible = Windows.visibleWindowIDs()
        let key = visible.map(\.id)
        guard !key.isEmpty else { return }
        if candidate?.key != key { candidate = (key, Date()); return }
        guard let c = candidate, Date().timeIntervalSince(c.since) >= Prefs.contextDwell else { return }
        if let top = history.first, top.key == Set(key) {
            // Same windows; just refresh positions/titles occasionally.
            if Date().timeIntervalSince(top.date) > 30 { commit(visible) }
            return
        }
        commit(visible)
    }

    private func commit(_ visible: [CGWin]) {
        let snaps = Windows.snapshot(visible)
        guard !snaps.isEmpty else { return }
        let ctx = WindowContext(windows: snaps)
        history.removeAll { $0.key == ctx.key }
        history.insert(ctx, at: 0)
        prune()
        save()
    }

    /// Drops windows that no longer exist and contexts that became empty.
    func prune() {
        let alive = Set(Windows.cgWindows(onScreenOnly: false).map(\.id))
        history = history.compactMap { c in
            var c = c
            c.windows = c.windows.filter { alive.contains($0.windowID) }
            return c.windows.isEmpty ? nil : c
        }
        var seen = Set<Set<CGWindowID>>()
        history = Array(history.filter { seen.insert($0.key).inserted }.prefix(maxHistory))
    }

    private func save() {
        if let data = try? JSONEncoder().encode(history) { try? data.write(to: url) }
    }

    /// The context before the one on screen now.
    var previous: WindowContext? {
        let now = Set(Windows.visibleWindowIDs().map(\.id))
        return history.first(where: { $0.key != now && !$0.key.isSubset(of: now) })
    }

    /// Records what is on screen right now without waiting for the dwell time.
    func captureNow() {
        let visible = Windows.visibleWindowIDs()
        guard !visible.isEmpty, history.first?.key != Set(visible.map(\.id)) else { return }
        commit(visible)
    }

    func goBack() async {
        captureNow()
        prune()
        guard let ctx = previous else { NSSound.beep(); return }
        await restore(ctx)
    }

    func restore(_ ctx: WindowContext) async {
        captureNow()
        await Actions.restore(ctx.windows, applyFrames: true, launchMissing: false)
        // Make the restored context the most recent immediately, so pressing ⌥` again toggles back.
        candidate = nil
        let current = history.first
        history.removeAll { $0.id == ctx.id }
        var updated = ctx
        updated.date = Date()
        history.insert(updated, at: 0)
        if let current, current.id != ctx.id {
            history.removeAll { $0.id == current.id }
            history.insert(current, at: 1)
        }
        save()
    }

    func clear() { history.removeAll(); save() }
}
