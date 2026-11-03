import AppKit

/// Watches app switches (⌘Tab, Dock, Spotlight, clicking a link...). When the app that just became
/// active has nothing visible where you are, its window is brought to the display under the mouse.
///
/// This fixes the classic macOS failure where an app "activates" but you see nothing because its
/// window is minimized, on another display, on another Space, off-screen, or it has no window at all.
@MainActor
final class AutoSummon {
    private var observer: NSObjectProtocol?
    private var pending: Task<Void, Never>?

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.appActivated(app) }
        }
    }

    private func appActivated(_ app: NSRunningApplication) {
        pending?.cancel()
        guard Prefs.bool(Prefs.Key.autoSummon), AX.isTrusted, !Actions.isBusy,
              app.activationPolicy == .regular, app.processIdentifier != Windows.ownPID,
              !Prefs.ignoredBundleIDs.contains(app.bundleIdentifier ?? "") else { return }
        // Let macOS finish its own Space switch / un-hide animation first.
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, !Actions.isBusy,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
            await fix(app)
        }
    }

    private func fix(_ app: NSRunningApplication) async {
        let pid = app.processIdentifier
        let here = Screens.current
        let onScreen = Windows.cgWindows(onScreenOnly: true).filter { $0.pid == pid }
        let axApp = AX.app(pid)
        let focused = AX.element(axApp, kAXFocusedWindowAttribute) ?? AX.element(axApp, kAXMainWindowAttribute)

        if !onScreen.isEmpty {
            // Something is visible. Is it where I am?
            if onScreen.contains(where: { Screens.screen(for: $0.frame) === here }) { return }
            let el = focused ?? AX.windows(pid).first
            guard let el else { return }
            let isLost = AX.frame(el).map { Screens.screen(for: $0) == nil } ?? false
            if isLost || Prefs.bool(Prefs.Key.pullFromOtherDisplay) {
                await Actions.bringHere(el, pid: pid)
            }
            return
        }

        // Nothing visible on any current Space.
        let local = AX.windows(pid)
        if let minimized = local.first(where: { AX.bool($0, kAXMinimizedAttribute) == true }) {
            await Actions.bringHere(minimized, pid: pid)
            return
        }
        if let off = Windows.offSpaceWindows(pid).first {
            guard Prefs.bool(Prefs.Key.pullFromOtherSpace), let el = AX.window(pid: pid, id: off.id) else { return }
            await Actions.bringHere(el, pid: pid)
            return
        }
        if local.isEmpty, !app.isHidden, Prefs.bool(Prefs.Key.reopenWhenNoWindows) {
            Actions.reopen(app)
        }
    }
}
