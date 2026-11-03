import AppKit

/// A "context" is the set of windows you were actually looking at, e.g. Chrome + a series player.
struct WindowContext: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    /// Front to back.
    var windows: [WindowSnapshot]

    var key: Set<CGWindowID> { Set(windows.map(\.windowID)) }
    /// Which windows, on which display. Moving a window to another display makes a different context.
    var signature: Set<WinSig> { Set(windows.map { WinSig($0.windowID, $0.frame) }) }

    var label: String {
        var seen = Set<String>()
        return windows.map(\.appName).filter { seen.insert($0).inserted }.joined(separator: " + ")
    }

    var detail: String { windows.map { $0.title.isEmpty ? $0.appName : $0.title }.joined(separator: " · ") }
}

struct WinSig: Hashable {
    let id: CGWindowID
    let screen: Int

    init(_ id: CGWindowID, _ frame: CGRect) {
        self.id = id
        screen = Screens.screen(for: frame).flatMap { s in NSScreen.screens.firstIndex(of: s) } ?? -1
    }
}

extension Array where Element == CGWin {
    var signature: Set<WinSig> { Set(map { WinSig($0.id, $0.frame) }) }
}

/// Remembers which windows were on screen together, so ⌥` can bring back the previous set
/// in one keystroke (like ⌘Tab, but for a whole group of windows).
@MainActor
final class ContextTracker: ObservableObject {
    @Published private(set) var history: [WindowContext] = []
    private var timer: Timer?
    private var candidate: (key: Set<WinSig>, since: Date)?
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
        let key = visible.signature
        guard !key.isEmpty else { return }
        if candidate?.key != key { candidate = (key, Date()); return }
        guard let c = candidate, Date().timeIntervalSince(c.since) >= Prefs.contextDwell else { return }
        if let top = history.first, top.signature == key {
            // Same windows on the same displays; just refresh positions/titles occasionally.
            if Date().timeIntervalSince(top.date) > 30 { commit(visible) }
            return
        }
        commit(visible)
    }

    private func commit(_ visible: [CGWin]) {
        let snaps = Windows.snapshot(visible)
        guard !snaps.isEmpty else { return }
        let ctx = WindowContext(windows: snaps)
        log.notice("context \(snaps.map { "\($0.appName)#\($0.windowID)@\(Int($0.frame.minX))" }.joined(separator: ","), privacy: .public)")
        history.removeAll { $0.signature == ctx.signature }
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
        var seen = Set<Set<WinSig>>()
        history = Array(history.filter { seen.insert($0.signature).inserted }.prefix(maxHistory))
    }

    private func save() {
        if let data = try? JSONEncoder().encode(history) { try? data.write(to: url) }
    }

    /// The context before the one on screen now.
    var previous: WindowContext? {
        let now = Windows.visibleWindowIDs().signature
        return history.first(where: { !$0.signature.isSubset(of: now) })
    }

    /// Records what is on screen right now without waiting for the dwell time.
    func captureNow() {
        let visible = Windows.visibleWindowIDs()
        guard !visible.isEmpty, history.first?.signature != visible.signature else { return }
        commit(visible)
    }

    func goBack() async {
        captureNow()
        prune()
        guard let ctx = previous else { NSSound.beep(); return }
        log.notice("back -> \(ctx.label, privacy: .public) \(ctx.windows.map { "\($0.windowID)@\(Int($0.frame.minX))" }.joined(separator: ","), privacy: .public)")
        await restore(ctx)
    }

    func restore(_ ctx: WindowContext) async {
        captureNow()
        // Send windows Focal pulled over since then back to where they were.
        for (id, pull) in Actions.pulled where pull.date >= ctx.date.addingTimeInterval(-1) || ctx.key.contains(id) {
            Actions.pulled[id] = nil
            guard !ctx.key.contains(id), let el = AX.window(pid: pull.pid, id: id) else { continue }
            await Snap.setFrame(el, pull.from)
        }
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
