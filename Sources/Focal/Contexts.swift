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
    /// While stepping with back/forward: the history index on screen now. History is not
    /// reordered during navigation, like a browser; doing something new ends it.
    @Published private(set) var navIndex: Int?
    /// What the screen looked like right after the last back/forward; any change ends navigation.
    private var navScreen: [CGWindowID: CGRect] = [:]
    private let maxHistory = 25
    private let url = Prefs.supportDirectory.appendingPathComponent("contexts.json")

    /// In-memory tracker that is never started or saved (README screenshots).
    static func demo() -> ContextTracker { ContextTracker() }

    func start() {
        Recency.shared.start()
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
        if navIndex != nil {
            if sameScreen(visible) { return }
            navIndex = nil
        }
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

    /// Index we are viewing via back/forward, if the screen still shows it.
    private var stillNavigating: Int? {
        guard let n = navIndex, history.indices.contains(n), sameScreen(Windows.visibleWindowIDs()) else { return nil }
        return n
    }

    private func sameScreen(_ visible: [CGWin]) -> Bool {
        guard visible.count == navScreen.count else { return false }
        return visible.allSatisfy { w in
            guard let f = navScreen[w.id] else { return false }
            return abs(f.minX - w.frame.minX) + abs(f.minY - w.frame.minY) + abs(f.width - w.frame.width) + abs(f.height - w.frame.height) <= 40
        }
    }

    /// The set is on screen as it was: every window visible at (about) its saved position.
    /// Comparing positions matters: "B on the right half" and "B full screen" are different sets.
    private func isShowing(_ ctx: WindowContext, _ visible: [CGWin]) -> Bool {
        let frames = Dictionary(visible.map { ($0.id, $0.frame) }, uniquingKeysWith: { a, _ in a })
        return ctx.windows.allSatisfy { w in
            guard let f = frames[w.windowID] else { return false }
            return abs(f.minX - w.frame.minX) + abs(f.minY - w.frame.minY) + abs(f.width - w.frame.width) + abs(f.height - w.frame.height) <= 40
        }
    }

    /// ⌥`: one step back in history (keeps going further on repeated presses).
    func goBack() async {
        let from: Int
        if let n = stillNavigating {
            from = n + 1
        } else {
            navIndex = nil
            captureNow()
            prune()
            from = 0
        }
        let now = Windows.visibleWindowIDs()
        guard let i = history.indices.dropFirst(from).first(where: { !isShowing(history[$0], now) }) else {
            NSSound.beep(); return
        }
        log.notice("back -> #\(i, privacy: .public) \(self.history[i].label, privacy: .public)")
        await navigate(to: i)
    }

    /// ⌥⇧`: one step forward, back towards the most recent set.
    func goForward() async {
        guard let n = stillNavigating, n > 0 else { NSSound.beep(); return }
        let now = Windows.visibleWindowIDs()
        guard let i = (0..<n).reversed().first(where: { !isShowing(history[$0], now) }) else { NSSound.beep(); return }
        log.notice("forward -> #\(i, privacy: .public) \(self.history[i].label, privacy: .public)")
        await navigate(to: i)
    }

    var canGoForward: Bool { (stillNavigating ?? 0) > 0 }

    private func navigate(to i: Int) async {
        let ctx = history[i]
        await undoPulls(since: ctx)
        await Actions.restore(ctx.windows, applyFrames: true, launchMissing: false)
        try? await Task.sleep(nanoseconds: 300_000_000) // let the last raise/resize settle
        candidate = nil
        navIndex = i
        navScreen = Dictionary(Windows.visibleWindowIDs().map { ($0.id, $0.frame) }, uniquingKeysWith: { a, _ in a })
    }

    /// Sends windows Focal pulled over since `ctx` was on screen back to where they were.
    private func undoPulls(since ctx: WindowContext) async {
        for (id, pull) in Actions.pulled where pull.date >= ctx.date.addingTimeInterval(-1) || ctx.key.contains(id) {
            Actions.pulled[id] = nil
            guard !ctx.key.contains(id), let el = AX.window(pid: pull.pid, id: id) else { continue }
            await Snap.setFrame(el, pull.from)
        }
    }

    /// Opening a specific set (switcher, menu) makes it the most recent one.
    func restore(_ ctx: WindowContext) async {
        navIndex = nil
        captureNow()
        await undoPulls(since: ctx)
        await Actions.restore(ctx.windows, applyFrames: true, launchMissing: false)
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

    func clear() { history.removeAll(); navIndex = nil; save() }
}
