import AppKit

/// Remembers when each window was last the focused one, so the switcher can list windows in
/// most-recently-used order like ⌘Tab / Alt+Tab. Screen stacking order alone is not enough:
/// a window in full screen or on another desktop has no place in it and would sink to the end.
@MainActor
final class Recency {
    static let shared = Recency()

    private(set) var lastFocused: [CGWindowID: Date] = [:]
    private var current: CGWindowID?
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    func start() {
        guard timer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteFocusedWindow() }
        }
        // Window changes inside one app (⌘`, clicking another Chrome window) send no notification.
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteFocusedWindow() }
        }
    }

    private func noteFocusedWindow() {
        guard AX.isTrusted, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != Windows.ownPID,
              let el = AX.element(AX.app(app.processIdentifier), kAXFocusedWindowAttribute),
              let id = AX.windowID(el), id != current else { return }
        current = id
        lastFocused[id] = Date()
        if lastFocused.count > 500 {
            // Forget the oldest half; closed windows never come back with the same id.
            let keep = lastFocused.sorted { $0.value > $1.value }.prefix(250)
            lastFocused = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }
}
