import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let contexts = ContextTracker()
    private let layouts = LayoutStore()
    private let autoSummon = AutoSummon()
    private lazy var switcher = SwitcherController(model: SwitcherModel(contexts: contexts, layouts: layouts))
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var failedHotKeys: [String] = []
    private var commandTabHotKeys: [UInt32] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        // A hung app must not freeze Focal for the default 6 s per AX call.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Focal")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        switcher.onNeedsPermission = { [weak self] in self?.showSettings() }
        registerHotKeys()
        CommandTab.quitCleanlyOnSignals()
        // Undo a previous run that crashed while holding ⌘Tab.
        CommandTab.setSystemSwitcherEnabled(true)
        applyCommandTab()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyCommandTab() }
        }
        contexts.start()
        autoSummon.start()
        _ = InstalledApps.all() // warm the list before the first search
        if AX.isTrusted { _ = Windows.items() } // starts looking for windows on other Spaces

        if !AX.isTrusted {
            AX.requestTrust()
            showSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        CommandTab.setSystemSwitcherEnabled(true)
    }

    /// Hands ⌘Tab to Focal's switcher or back to the system one, following the setting.
    private func applyCommandTab() {
        let wanted = Prefs.bool(Prefs.Key.replaceCommandTab)
        guard wanted == commandTabHotKeys.isEmpty else { return }
        if wanted {
            CommandTab.setSystemSwitcherEnabled(false)
            commandTabHotKeys = [
                HotKeys.shared.register(.commandTab) { [weak self] in MainActor.assumeIsolated { self?.switcher.cycle(backward: false) } },
                HotKeys.shared.register(.commandShiftTab) { [weak self] in MainActor.assumeIsolated { self?.switcher.cycle(backward: true) } },
            ].compactMap { $0 }
            if commandTabHotKeys.count < 2 {
                commandTabHotKeys.forEach(HotKeys.shared.unregister)
                commandTabHotKeys = []
                CommandTab.setSystemSwitcherEnabled(true)
                if !failedHotKeys.contains(HotKeys.Combo.commandTab.display) { failedHotKeys.append(HotKeys.Combo.commandTab.display) }
            }
        } else {
            commandTabHotKeys.forEach(HotKeys.shared.unregister)
            commandTabHotKeys = []
            CommandTab.setSystemSwitcherEnabled(true)
        }
    }

    private func registerHotKeys() {
        let hk = HotKeys.shared
        func reg(_ combo: HotKeys.Combo, _ action: @escaping @MainActor () -> Void) {
            if hk.register(combo, { MainActor.assumeIsolated { action() } }) == nil { failedHotKeys.append(combo.display) }
        }
        reg(.switcher) { [weak self] in self?.switcher.toggle() }
        reg(.back) { [weak self] in self?.goBack() }
        reg(.forward) { [weak self] in self?.goForward() }
        reg(.summon) { Task { await Actions.summonFrontmost() } }
        reg(.saveLayout) { [weak self] in self?.layouts.promptAndSaveCurrent() }
        for a in SnapAction.allCases {
            reg(.snap(a)) { Task { await Snap.perform(a) } }
        }
        for i in 0..<9 {
            reg(.layout(i)) { [weak self] in Task { await self?.layouts.restore(at: i) } }
        }
    }

    private func goBack() {
        guard AX.isTrusted else { showSettings(); return }
        Task { await contexts.goBack() }
    }

    private func goForward() {
        guard AX.isTrusted else { showSettings(); return }
        Task { await contexts.goForward() }
    }

    // MARK: URL scheme (Shortcuts, Raycast, scripts): focal://switcher, back, summon, save?name=X, layout?n=1, dump

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "focal" {
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            switch url.host {
            case "switcher": switcher.toggle()
            case "back": goBack()
            case "forward": goForward()
            case "summon": Task { await Actions.summonFrontmost() }
            case "save": _ = layouts.saveCurrent(named: q.first { $0.name == "name" }?.value ?? "Набір \(layouts.layouts.count + 1)")
            case "layout": Task { await layouts.restore(at: (Int(q.first { $0.name == "n" }?.value ?? "") ?? 0) - 1) }
            case "settings": showSettings()
            case "dump": dump()
            case "render-docs":
                if let dir = q.first(where: { $0.name == "dir" })?.value {
                    DocsRender.renderAll(to: URL(fileURLWithPath: dir))
                }
            case "inspect": inspect(bundleID: q.first { $0.name == "app" }?.value ?? "com.google.Chrome")
            case "snap":
                if let a = q.first(where: { $0.name == "to" })?.value.flatMap(SnapAction.init(rawValue:)) {
                    Task { await Snap.perform(a) }
                }
            case "focus":
                if let id = q.first(where: { $0.name == "id" })?.value.flatMap(CGWindowID.init),
                   let w = Windows.items().first(where: { $0.id == id }) {
                    Task { await Actions.bringHere(w.element, pid: w.pid, moveToCurrentDisplay: false) }
                }
            default: NSSound.beep()
            }
        }
    }

    /// Writes Focal's view of the world to Application Support/Focal/state.json (for debugging).
    private func dump() {
        contexts.prune()
        let state: [String: Any] = [
            "trusted": AX.isTrusted,
            "mouseScreen": Screens.current.localizedName,
            "windows": Windows.items().map { w in
                ["id": w.id, "app": w.app.localizedName ?? "", "title": w.title, "minimized": w.isMinimized,
                 "onScreen": w.isOnScreen, "screen": Screens.screen(for: w.frame)?.localizedName ?? "none",
                 "frame": [w.frame.minX, w.frame.minY, w.frame.width, w.frame.height]] as [String: Any]
            },
            "visible": Windows.visibleWindowIDs().map(\.id),
            "navIndex": contexts.navIndex ?? -1,
            "contexts": contexts.history.map { ["label": $0.label, "ids": $0.windows.map(\.windowID)] as [String: Any] },
            "layouts": layouts.layouts.map(\.name),
            "failedHotKeys": failedHotKeys,
        ]
        let url = Prefs.supportDirectory.appendingPathComponent("state.json")
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }

    /// Everything macOS reports about one app's windows (debugging "missing window" reports).
    private func inspect(bundleID: String) {
        var out: [[String: Any]] = []
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            let pid = app.processIdentifier
            func ax(_ el: AXUIElement) -> [String: Any] {
                ["id": AX.windowID(el) ?? 0, "title": AX.string(el, kAXTitleAttribute) ?? "",
                 "subrole": AX.string(el, kAXSubroleAttribute) ?? "", "minimized": AX.bool(el, kAXMinimizedAttribute) ?? false,
                 "fullscreen": AX.bool(el, "AXFullScreen") ?? false,
                 "frame": AX.frame(el).map { [$0.minX, $0.minY, $0.width, $0.height] } ?? []]
            }
            let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
            let cg = list.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid }.map { d -> [String: Any] in
                ["id": d[kCGWindowNumber as String] ?? 0, "layer": d[kCGWindowLayer as String] ?? 0,
                 "onScreen": d[kCGWindowIsOnscreen as String] ?? false, "alpha": d[kCGWindowAlpha as String] ?? 0,
                 "bounds": d[kCGWindowBounds as String] ?? [:]]
            }
            let axRaw = (AX.value(AX.app(pid), kAXWindowsAttribute) as? [AXUIElement] ?? []).map(ax)
            let t0 = Date()
            var brute: [[String: Any]] = []
            AX.forEachWindowElement(pid) { el, eid in
                brute.append(ax(el).merging(["elementID": eid]) { a, _ in a }); return true
            }
            out.append(["pid": pid, "cgWindows": cg, "axWindows": axRaw, "bruteForce": brute,
                        "bruteForceMs": Int(Date().timeIntervalSince(t0) * 1000)])
        }
        let url = Prefs.supportDirectory.appendingPathComponent("inspect.json")
        if let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url) }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !AX.isTrusted {
            menu.addItem(item("⚠️ Надати доступ Accessibility…") { [weak self] in self?.showSettings() })
            menu.addItem(.separator())
        }
        menu.addItem(item("Перемикач вікон", key: commandTabHotKeys.isEmpty ? "⌥Space" : "⌘Tab / ⌥Space") { [weak self] in self?.switcher.show() })
        menu.addItem(item("Назад до попереднього набору", key: "⌥`") { [weak self] in self?.goBack() })
        let fwd = item("Вперед до наступного набору", key: "⌥⇧`") { [weak self] in self?.goForward() }
        fwd.isEnabled = contexts.canGoForward
        menu.addItem(fwd)
        menu.addItem(item("Притягнути активне вікно сюди", key: "⌥⇧Space") { Task { await Actions.summonFrontmost() } })
        let windowMenu = NSMenu()
        let names: [(SnapAction, String)] = [
            (.left, "Ліва половина"), (.right, "Права половина"), (.up, "Розгорнути / верхня чверть"),
            (.down, "Відновити / нижня чверть / згорнути"), (.maximize, "Заповнити екран"), (.center, "По центру"),
            (.restore, "Попередній розмір"), (.fullscreen, "Повноекранний режим"),
            (.displayLeft, "На дисплей ліворуч"), (.displayRight, "На дисплей праворуч"),
        ]
        for (a, title) in names {
            // Runs after the menu closes, so the user's app is frontmost again.
            windowMenu.addItem(item(title, key: HotKeys.Combo.snap(a).display) { Task { try? await Task.sleep(nanoseconds: 150_000_000); await Snap.perform(a) } })
        }
        let windowItem = NSMenuItem(title: "Активне вікно", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        menu.addItem(.separator())

        let recent = NSMenu()
        contexts.prune()
        for ctx in contexts.history.prefix(10) {
            let mi = item(ctx.label) { [weak self] in Task { await self?.contexts.restore(ctx) } }
            mi.toolTip = ctx.detail
            recent.addItem(mi)
        }
        if recent.items.isEmpty { recent.addItem(disabled("Поки порожньо")) }
        let recentItem = NSMenuItem(title: "Попередні набори", action: nil, keyEquivalent: "")
        recentItem.submenu = recent
        menu.addItem(recentItem)

        let saved = NSMenu()
        for (i, layout) in layouts.layouts.enumerated() {
            saved.addItem(item(layout.name, key: i < 9 ? "⌃⌥\(i + 1)" : nil) { [weak self] in Task { await self?.layouts.restore(layout) } })
        }
        if !saved.items.isEmpty { saved.addItem(.separator()) }
        saved.addItem(item("Зберегти поточний набір…", key: "⌃⌥S") { [weak self] in self?.layouts.promptAndSaveCurrent() })
        saved.addItem(item("Керувати…") { [weak self] in self?.showSettings() })
        let savedItem = NSMenuItem(title: "Збережені набори", action: nil, keyEquivalent: "")
        savedItem.submenu = saved
        menu.addItem(savedItem)

        menu.addItem(.separator())
        let auto = item("Притягувати вікна автоматично") {
            UserDefaults.standard.set(!Prefs.bool(Prefs.Key.autoSummon), forKey: Prefs.Key.autoSummon)
        }
        auto.state = Prefs.bool(Prefs.Key.autoSummon) ? .on : .off
        menu.addItem(auto)
        menu.addItem(item("Налаштування…") { [weak self] in self?.showSettings() })
        menu.addItem(.separator())
        menu.addItem(item("Вийти з Focal") { NSApp.terminate(nil) })
    }

    private func item(_ title: String, key: String? = nil, _ action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let mi = ClosureMenuItem(title: title, action: action)
        if let key {
            // Show the global shortcut as plain trailing text; real key equivalents only work while the menu is open.
            mi.attributedTitle = NSAttributedString(string: title + "\t" + key, attributes: [
                .paragraphStyle: { let p = NSMutableParagraphStyle(); p.tabStops = [NSTextTab(textAlignment: .right, location: 300)]; return p }(),
            ])
        }
        return mi
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.isEnabled = false
        return mi
    }

    // MARK: Settings

    func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView:
                SettingsView(layouts: layouts, contexts: contexts, failedHotKeys: failedHotKeys)))
            w.title = "Focal"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, action: @escaping @MainActor () -> Void) {
        handler = action
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { MainActor.assumeIsolated { handler() } }
}
