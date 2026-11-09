import AppKit

@_silgen_name("CGSSetSymbolicHotKeyEnabled")
@discardableResult
private func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ isEnabled: Bool) -> CGError

/// Takes ⌘Tab / ⌘⇧Tab away from the system app switcher so Focal can register them.
/// WindowServer handles them before any app sees the keys, so a plain hotkey never fires.
enum CommandTab {
    // CGSSymbolicHotKey ids: 1 = ⌘Tab, 2 = ⌘⇧Tab.
    private static let systemHotKeys: [Int32] = [1, 2]
    private static var signalSources: [DispatchSourceSignal] = []

    /// The setting outlives Focal's process, so it has to be put back on every exit path.
    static func setSystemSwitcherEnabled(_ on: Bool) {
        for id in systemHotKeys { CGSSetSymbolicHotKeyEnabled(id, on) }
    }

    /// Turns `kill`/Ctrl-C into a normal quit so applicationWillTerminate restores ⌘Tab.
    /// A crash or `kill -9` still leaves it off until Focal runs again or you log out.
    static func quitCleanlyOnSignals() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { NSApp.terminate(nil) }
            src.resume()
            signalSources.append(src)
        }
    }
}
