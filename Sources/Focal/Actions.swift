import AppKit

/// Everything that moves, raises or restores windows.
@MainActor
enum Actions {
    /// True while Focal itself is rearranging windows, so the auto-summon observer stays out of the way.
    static private(set) var isBusy = false
    private static var busyGeneration = 0

    private static func sleep(_ ms: UInt64) async { try? await Task.sleep(nanoseconds: ms * 1_000_000) }

    /// Windows Focal pulled to another display, with where they were, so "back" can undo it.
    struct Pull { let pid: pid_t; let from: CGRect; let date: Date }
    static var pulled: [CGWindowID: Pull] = [:]

    static func beginBusy() { busyGeneration += 1; isBusy = true }
    static func endBusy(after ms: UInt64 = 700) {
        let gen = busyGeneration
        Task { @MainActor in
            await sleep(ms)
            if gen == busyGeneration { isBusy = false }
        }
    }

    // MARK: Primitives

    static func activate(_ pid: pid_t) {
        AX.set(AX.app(pid), kAXFrontmostAttribute, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
    }

    static func raise(_ el: AXUIElement, pid: pid_t) {
        if AX.bool(el, kAXMinimizedAttribute) == true { AX.set(el, kAXMinimizedAttribute, kCFBooleanFalse) }
        AX.set(el, kAXMainAttribute, kCFBooleanTrue)
        AX.perform(el, kAXRaiseAction)
        activate(pid)
        AX.perform(el, kAXRaiseAction)
    }

    /// Moves a window to `screen` unless it is already there (or is a full-screen window).
    static func move(_ el: AXUIElement, to screen: NSScreen) async {
        guard AX.bool(el, "AXFullScreen") != true, let f = AX.frame(el) else { return }
        if Screens.screen(for: f) === screen { return }
        await Snap.setFrame(el, Screens.translate(f, to: screen))
    }

    static func isOnScreen(_ id: CGWindowID) -> Bool {
        Windows.cgWindows(onScreenOnly: true).contains { $0.id == id }
    }

    /// Asks the app to open a window, exactly like clicking its Dock icon.
    static func reopen(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else { app.activate(options: []); return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg)
    }

    /// Reopens the app and then brings the window it creates to the display I am on.
    static func reopenHere(_ app: NSRunningApplication, moveToCurrentDisplay: Bool = true) async {
        let target = Screens.current
        reopen(app)
        for _ in 0..<20 {
            await sleep(150)
            if let el = AX.windows(app.processIdentifier).first(where: { AX.bool($0, kAXMinimizedAttribute) != true }) {
                if moveToCurrentDisplay, let f = AX.frame(el), Screens.screen(for: f) !== target {
                    await bringHere(el, pid: app.processIdentifier)
                }
                return
            }
        }
    }

    // MARK: High-level

    /// Brings a window to the display under the mouse: un-minimizes it, pulls it from another
    /// Space if needed, moves it to this display and puts it on top.
    static func bringHere(_ el: AXUIElement, pid: pid_t, moveToCurrentDisplay: Bool = true) async {
        beginBusy(); defer { endBusy() }
        let target = Screens.current
        let id = AX.windowID(el)
        let originalFrame = AX.frame(el)
        log.notice("bringHere id=\(id ?? 0, privacy: .public) pid=\(pid, privacy: .public) from=\(String(describing: originalFrame), privacy: .public) to=\(target.localizedName, privacy: .public)")
        if let id, !isOnScreen(id), AX.bool(el, kAXMinimizedAttribute) != true {
            // On another Space: a minimize/restore round trip re-opens the window on the active Space.
            AX.set(el, kAXMinimizedAttribute, kCFBooleanTrue)
            await sleep(450)
        }
        if AX.bool(el, kAXMinimizedAttribute) == true {
            AX.set(el, kAXMinimizedAttribute, kCFBooleanFalse)
            await sleep(350)
        }
        if moveToCurrentDisplay { await move(el, to: target) }
        if let id, let originalFrame, pulled[id] == nil, Screens.screen(for: originalFrame) !== target,
           AX.frame(el).flatMap(Screens.screen(for:)) === target {
            pulled[id] = Pull(pid: pid, from: originalFrame, date: Date())
        }
        pulled = pulled.filter { Date().timeIntervalSince($0.value.date) < 3600 }
        raise(el, pid: pid)
    }

    /// Hotkey "summon": take the frontmost app's window and put it in front of me.
    static func summonFrontmost() async {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != Windows.ownPID else { return }
        await summon(app)
    }

    static func summon(_ app: NSRunningApplication) async {
        let pid = app.processIdentifier
        let axApp = AX.app(pid)
        if let el = AX.element(axApp, kAXFocusedWindowAttribute) ?? AX.element(axApp, kAXMainWindowAttribute) ?? AX.windows(pid).first {
            await bringHere(el, pid: pid)
        } else if let off = Windows.offSpaceWindows(pid).first, let el = AX.window(pid: pid, id: off.id) {
            await bringHere(el, pid: pid)
        } else {
            await reopenHere(app)
        }
    }

    // MARK: Restoring contexts and layouts

    /// Raises the given windows so that the first one ends up on top. Optionally puts them back
    /// at their saved positions. Launches apps that are not running when `launchMissing` is set.
    static func restore(_ snaps: [WindowSnapshot], applyFrames: Bool, launchMissing: Bool) async {
        beginBusy(); defer { endBusy(after: 1200) }
        log.notice("restore \(snaps.map { "\($0.appName)#\($0.windowID)" }.joined(separator: ","), privacy: .public)")
        var used = Set<CGWindowID>()
        var raised: [(AXUIElement, pid_t)] = []
        for s in snaps.reversed() {
            guard let app = await resolveApp(s, launch: launchMissing) else { continue }
            let pid = app.processIdentifier
            guard let el = await resolveWindow(s, pid: pid, used: used, app: app, reopenIfNone: launchMissing) else { continue }
            if let id = AX.windowID(el) { used.insert(id) }
            if AX.bool(el, kAXMinimizedAttribute) == true {
                AX.set(el, kAXMinimizedAttribute, kCFBooleanFalse)
                await sleep(250)
            }
            if applyFrames, let f = AX.frame(el), Screens.screen(for: s.frame) != nil,
               abs(f.minX - s.frame.minX) + abs(f.minY - s.frame.minY) + abs(f.width - s.frame.width) + abs(f.height - s.frame.height) > 4 {
                await Snap.setFrame(el, s.frame)
            }
            raise(el, pid: pid)
            raised.append((el, pid))
            await sleep(90)
        }
        // Activation of an app can drag its other windows forward; re-assert the intended order.
        for (el, _) in raised { AX.perform(el, kAXRaiseAction) }
        if let (el, pid) = raised.last { raise(el, pid: pid) }
    }

    private static func resolveApp(_ s: WindowSnapshot, launch: Bool) async -> NSRunningApplication? {
        if let app = NSRunningApplication(processIdentifier: s.pid), !app.isTerminated,
           s.bundleID == nil || app.bundleIdentifier == s.bundleID { return app }
        guard let bid = s.bundleID else { return nil }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first { return app }
        guard launch, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else { return nil }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        guard let app = try? await NSWorkspace.shared.openApplication(at: url, configuration: cfg) else { return nil }
        for _ in 0..<40 where AX.windows(app.processIdentifier).isEmpty { await sleep(150) }
        return app
    }

    private static func resolveWindow(_ s: WindowSnapshot, pid: pid_t, used: Set<CGWindowID>, app: NSRunningApplication, reopenIfNone: Bool) async -> AXUIElement? {
        if pid == s.pid, let el = AX.window(pid: pid, id: s.windowID) { return el }
        let candidates = AX.windows(pid).filter { AX.windowID($0).map { !used.contains($0) } ?? false }
        if let el = candidates.first(where: { AX.string($0, kAXTitleAttribute) == s.title }) { return el }
        if !s.title.isEmpty, let el = candidates.first(where: { (AX.string($0, kAXTitleAttribute) ?? "").hasPrefix(String(s.title.prefix(12))) }) { return el }
        if let el = candidates.first { return el }
        if reopenIfNone {
            reopen(app)
            for _ in 0..<20 {
                await sleep(150)
                if let el = AX.windows(pid).first(where: { AX.windowID($0).map { !used.contains($0) } ?? false }) { return el }
            }
        }
        return nil
    }
}
