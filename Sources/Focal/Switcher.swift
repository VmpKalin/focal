import AppKit
import SwiftUI

// MARK: Model

struct SwitchItem: Identifiable {
    enum Kind {
        case window(WindowItem)
        case offSpace(NSRunningApplication)
        case noWindows(NSRunningApplication)
        case context(WindowContext)
        case layout(Layout, index: Int)
        case launch(URL)
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let icon: NSImage?
    let symbol: String?
    let badges: [String]
    /// Fixed preview image (demo renders); live windows use Thumbnails instead.
    var preview: NSImage? = nil
    /// Extra text the search matches but the UI doesn't show.
    var keywords = ""

    var searchable: String { "\(title) \(subtitle) \(keywords)" }

    var windowID: CGWindowID? {
        if case .window(let w) = kind { return w.id }
        return nil
    }
}

enum SwitcherStyle: String {
    case list, grid

    static var current: SwitcherStyle { SwitcherStyle(rawValue: UserDefaults.standard.string(forKey: Prefs.Key.switcherStyle) ?? "") ?? .list }

    var size: NSSize { self == .list ? NSSize(width: 680, height: 460) : NSSize(width: 980, height: 640) }
    /// Cards per row in the grid; arrow ↑/↓ moves by this much.
    static let gridColumns = 4
}

@MainActor
final class SwitcherModel: ObservableObject {
    @Published var query = "" { didSet { refilter() } }
    @Published private(set) var visible: [SwitchItem] = []
    @Published var selection = 0
    @Published var focusToken = UUID()
    @Published private(set) var style = SwitcherStyle.current
    @Published private(set) var isDemo = false
    let thumbnails = Thumbnails()

    private var all: [SwitchItem] = []
    /// Apps that aren't running; offered only while searching, like Spotlight.
    private var installed: [InstalledApps.App] = []
    let contexts: ContextTracker
    let layouts: LayoutStore

    init(contexts: ContextTracker, layouts: LayoutStore) {
        self.contexts = contexts
        self.layouts = layouts
    }

    func reload() {
        query = ""
        style = SwitcherStyle.current
        let here = Screens.current
        let windows = Windows.items()
        var items: [SwitchItem] = windows.map { w in
            var badges: [String] = []
            if w.isFullScreen { badges.append("повний екран") }
            if w.isMinimized { badges.append("згорнуте") }
            else if !w.isOnScreen { badges.append(w.isFullScreen ? "окремий Space" : "інший робочий стіл") }
            else if let s = Screens.screen(for: w.frame), s !== here { badges.append(s.localizedName) }
            else if Screens.screen(for: w.frame) == nil { badges.append("за межами екрана") }
            return SwitchItem(id: "w\(w.id)", kind: .window(w), title: w.title,
                              subtitle: w.app.localizedName ?? "", icon: w.app.icon, symbol: nil, badges: badges,
                              keywords: InstalledApps.fileName(w.app))
        }

        contexts.prune()
        let now = Windows.visibleWindowIDs().signature
        for ctx in contexts.history.filter({ !$0.signature.isSubset(of: now) }).prefix(6) {
            items.append(SwitchItem(id: "c\(ctx.id)", kind: .context(ctx), title: ctx.label, subtitle: ctx.detail,
                                    icon: nil, symbol: "clock.arrow.circlepath", badges: ["попередній набір"]))
        }
        for (i, layout) in layouts.layouts.enumerated() {
            items.append(SwitchItem(id: "l\(layout.id)", kind: .layout(layout, index: i), title: layout.name,
                                    subtitle: layout.windows.map(\.appName).joined(separator: " + "),
                                    icon: nil, symbol: "square.grid.2x2", badges: i < 9 ? ["⌃⌥\(i + 1)"] : []))
        }
        // Windows.items() already includes other Spaces, so apps left here really have no windows.
        let withWindows = Set(windows.map(\.pid))
        for app in Windows.regularApps() where !withWindows.contains(app.processIdentifier) {
            items.append(SwitchItem(id: "a\(app.processIdentifier)", kind: .noWindows(app),
                                    title: app.localizedName ?? "?", subtitle: "немає відкритих вікон",
                                    icon: app.icon, symbol: nil, badges: ["нове вікно"],
                                    keywords: InstalledApps.fileName(app)))
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.standardizedFileURL })
        installed = InstalledApps.all().filter { !running.contains($0.url) }
        if style == .grid {
            thumbnails.forget(except: Set(windows.map(\.id)))
            thumbnails.load(windows.map(\.id))
        }
        all = items
        refilter()
        // Like ⌘Tab: the first row is what you are looking at, so start on the second one.
        if let first = visible.first, case .window(let w) = first.kind,
           w.pid == NSWorkspace.shared.frontmostApplication?.processIdentifier, visible.count > 1 {
            selection = 1
        }
        focusToken = UUID()
    }

    private func refilter() {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            visible = all
        } else {
            // On a tie an open window or running app wins over launching another one.
            let launchable = installed.compactMap { app in
                score(app.searchable, q).map { (app.item, $0 - 1) }
            }.sorted { $0.1 > $1.1 }.prefix(8)
            visible = (all.compactMap { item in score(item.searchable.lowercased(), q).map { (item, $0) } } + launchable)
                .enumerated()
                .sorted { ($0.element.1, -$0.offset) > ($1.element.1, -$1.offset) }
                .map(\.element.0)
        }
        selection = 0
    }

    /// Substring matches beat word-prefix matches beat loose subsequence matches.
    private func score(_ text: String, _ q: String) -> Int? {
        if let r = text.range(of: q) {
            let start = text.distance(from: text.startIndex, to: r.lowerBound)
            let wordStart = start == 0 || text[text.index(before: r.lowerBound)] == " "
            return 1000 + (wordStart ? 500 : 0) - start
        }
        var it = text.makeIterator()
        var gaps = 0
        for ch in q {
            var matched = false
            while let c = it.next() {
                if c == ch { matched = true; break }
                gaps += 1
            }
            if !matched { return nil }
        }
        return max(1, 500 - gaps)
    }

    /// Shows fixed items instead of live windows (README screenshots).
    func showDemo(_ items: [SwitchItem], style: SwitcherStyle, query: String = "", selection: Int = 0) {
        self.style = style
        isDemo = true
        all = items
        visible = items
        self.query = query
        if !query.isEmpty { visible = items }
        self.selection = selection
    }

    func move(_ delta: Int) {
        guard !visible.isEmpty else { return }
        if abs(delta) > 1 {
            // Grid rows: stop at the edges instead of wrapping into another column.
            let next = selection + delta
            if visible.indices.contains(next) { selection = next }
            return
        }
        selection = (selection + delta + visible.count) % visible.count
    }

    var selected: SwitchItem? { visible.indices.contains(selection) ? visible[selection] : nil }
}

// MARK: View

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    @ObservedObject var thumbs: Thumbnails
    var onActivate: (SwitchItem) -> Void
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 18))
                TextField("Вікно, застосунок або набір…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($fieldFocused)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    if model.style == .grid {
                        if !Thumbnails.hasPermission && !model.isDemo {
                            HStack {
                                Image(systemName: "eye.slash")
                                Text("Щоб бачити вміст вікон, дозволь Focal «Запис екрана».")
                                Spacer()
                                Button("Дозволити…") { Thumbnails.requestPermission() }
                            }
                            .font(.system(size: 12)).padding(.horizontal, 14).padding(.top, 10)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(224), spacing: 12), count: SwitcherStyle.gridColumns), spacing: 12) {
                            ForEach(Array(model.visible.enumerated()), id: \.element.id) { i, item in
                                Card(item: item, image: item.preview ?? item.windowID.flatMap { thumbs.images[$0] }, selected: i == model.selection)
                                    .id(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.selection = i; onActivate(item) }
                            }
                        }
                        .padding(12)
                    } else {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(model.visible.enumerated()), id: \.element.id) { i, item in
                                Row(item: item, selected: i == model.selection)
                                    .id(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.selection = i; onActivate(item) }
                            }
                        }
                        .padding(6)
                    }
                }
                .onChange(of: model.selection) { _, new in
                    if model.visible.indices.contains(new) { proxy.scrollTo(model.visible[new].id) }
                }
            }
            if model.visible.isEmpty {
                Text("Нічого не знайдено").foregroundStyle(.secondary).padding()
                Spacer()
            }
            Divider()
            Text("↩ відкрити тут   ⌘↩ відкрити на своєму місці   ⌘W закрити   ⌘M згорнути   esc")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.vertical, 7)
        }
        .frame(width: model.style.size.width, height: model.style.size.height)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .onChange(of: model.focusToken) { _, _ in fieldFocused = true }
        .onAppear { fieldFocused = true }
    }

    /// A grid card: live preview of the window (or the app icon), title and badges.
    struct Card: View {
        let item: SwitchItem
        let image: NSImage?
        let selected: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25))
                    if let image {
                        Image(nsImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 6)).padding(4)
                    } else if let icon = item.icon {
                        Image(nsImage: icon).resizable().frame(width: 64, height: 64).opacity(0.9)
                    } else {
                        Image(systemName: item.symbol ?? "macwindow").font(.system(size: 40)).foregroundStyle(Color.accentColor)
                    }
                    if image != nil, let icon = item.icon {
                        Image(nsImage: icon).resizable().frame(width: 30, height: 30)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(6)
                    }
                }
                .frame(width: 216, height: 136)
                HStack(spacing: 4) {
                    Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 4) {
                    Text(item.subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    if let b = item.badges.first {
                        Text(b).font(.system(size: 9.5, weight: .medium)).lineLimit(1)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.2)))
                    }
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 11).fill(selected ? Color.accentColor.opacity(0.25) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2.5))
            .help(item.title)
        }
    }

    struct Row: View {
        let item: SwitchItem
        let selected: Bool

        var body: some View {
            HStack(spacing: 12) {
                Group {
                    if let icon = item.icon {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: item.symbol ?? "macwindow").resizable().scaledToFit().padding(5)
                            .foregroundStyle(selected ? .white : .accentColor)
                    }
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    Text(item.subtitle).font(.system(size: 11.5)).lineLimit(1)
                        .foregroundStyle(selected ? .white.opacity(0.8) : .secondary)
                }
                Spacer(minLength: 8)
                ForEach(item.badges, id: \.self) { b in
                    Text(b).font(.system(size: 10.5, weight: .medium))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(selected ? .white.opacity(0.22) : .secondary.opacity(0.15)))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(selected ? .white : .primary)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor : .clear))
        }
    }
}

// MARK: Panel

private final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SwitcherController: NSObject, NSWindowDelegate {
    let model: SwitcherModel
    private var panel: SwitcherPanel?
    private var keyMonitor: Any?
    private var flagsMonitors: [Any] = []
    /// Opened with ⌘Tab: letting go of ⌘ opens the selection, like the system switcher.
    private var commitOnCommandUp = false
    var onNeedsPermission: () -> Void = {}

    init(model: SwitcherModel) {
        self.model = model
        super.init()
        NotificationCenter.default.addObserver(forName: OffSpaceWindows.didFind, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshKeepingQuery() }
        }
    }

    var isShown: Bool { panel?.isVisible == true }

    /// Adds windows found in the background without losing what the user typed or picked.
    private func refreshKeepingQuery() {
        guard isShown else { return }
        let query = model.query, selectedID = model.selected?.id
        model.reload()
        model.query = query
        if let selectedID, let i = model.visible.firstIndex(where: { $0.id == selectedID }) { model.selection = i }
    }

    func toggle() { isShown ? hide() : show() }

    /// ⌘Tab / ⌘⇧Tab: the first press opens the switcher, further presses move the selection.
    func cycle(backward: Bool) {
        if isShown {
            model.move(backward ? -1 : 1)
            return
        }
        show()
        guard isShown else { return }
        if backward { model.selection = max(0, model.visible.count - 1) }
        commitOnCommandUp = true
        if flagsMonitors.isEmpty {
            let onFlags: (NSEvent) -> Void = { [weak self] e in
                MainActor.assumeIsolated { if !e.modifierFlags.contains(.command) { self?.commandReleased() } }
            }
            flagsMonitors = [
                NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { onFlags($0); return $0 },
                NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: onFlags),
            ].compactMap { $0 }
        }
        // A quick tap can let go of ⌘ before the hotkey even reached us.
        if !CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand) { commandReleased() }
    }

    private func commandReleased() {
        guard commitOnCommandUp, isShown else { return }
        commitOnCommandUp = false
        if let s = model.selected { activate(s, flipPlacement: false) } else { hide() }
    }

    func show() {
        commitOnCommandUp = false
        guard AX.isTrusted else { onNeedsPermission(); return }
        model.reload()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setContentSize(model.style.size)
        let screen = Screens.current.frame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2, y: screen.maxY - screen.height * 0.22 - size.height))
        panel.makeKeyAndOrderFront(nil)
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                MainActor.assumeIsolated { self?.handle(e) ?? e }
            }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
        flagsMonitors.forEach(NSEvent.removeMonitor)
        flagsMonitors = []
        commitOnCommandUp = false
    }

    func windowDidResignKey(_ notification: Notification) { hide() }

    private func makePanel() -> SwitcherPanel {
        let p = SwitcherPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
                              styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView], backing: .buffered, defer: false)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.delegate = self
        p.contentView = NSHostingView(rootView: SwitcherView(model: model, thumbs: model.thumbnails) { [weak self] item in
            self?.activate(item, flipPlacement: false)
        })
        return p
    }

    private func handle(_ e: NSEvent) -> NSEvent? {
        guard isShown, e.window === panel else { return e }
        let cmd = e.modifierFlags.contains(.command)
        switch Int(e.keyCode) {
        case 125: model.move(model.style == .grid ? SwitcherStyle.gridColumns : 1)   // ↓
        case 126: model.move(model.style == .grid ? -SwitcherStyle.gridColumns : -1) // ↑
        case 123 where model.style == .grid: model.move(-1)     // ←
        case 124 where model.style == .grid: model.move(1)      // →
        case 48: model.move(e.modifierFlags.contains(.shift) ? -1 : 1) // tab
        case 36, 76: if let s = model.selected { activate(s, flipPlacement: cmd) } // return
        case 53: hide()                                          // esc
        case 13 where cmd: closeSelected()                       // ⌘W
        case 46 where cmd: minimizeSelected()                    // ⌘M
        default: return e
        }
        return nil
    }

    private func activate(_ item: SwitchItem, flipPlacement: Bool) {
        hide()
        let bringHere = Prefs.bool(Prefs.Key.switcherBringsHere) != flipPlacement
        Task { @MainActor in
            switch item.kind {
            case .window(let w):
                if bringHere || !w.isOnScreen {
                    await Actions.bringHere(w.element, pid: w.pid, moveToCurrentDisplay: bringHere)
                } else {
                    Actions.raise(w.element, pid: w.pid)
                }
            case .offSpace(let app):
                await Actions.summon(app)
            case .noWindows(let app):
                await Actions.reopenHere(app, moveToCurrentDisplay: bringHere)
            case .launch(let url):
                _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            case .context(let ctx):
                await model.contexts.restore(ctx)
            case .layout(let layout, _):
                await model.layouts.restore(layout)
            }
        }
    }

    private func closeSelected() {
        guard let s = model.selected, case .window(let w) = s.kind else { NSSound.beep(); return }
        if let btn = AX.element(w.element, kAXCloseButtonAttribute) { AX.perform(btn, kAXPressAction) }
        refreshSoon()
    }

    private func minimizeSelected() {
        guard let s = model.selected, case .window(let w) = s.kind else { NSSound.beep(); return }
        AX.set(w.element, kAXMinimizedAttribute, kCFBooleanTrue)
        refreshSoon()
    }

    private func refreshSoon() {
        let keep = model.selection
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard isShown else { return }
            model.reload()
            model.selection = min(keep, max(0, model.visible.count - 1))
        }
    }
}
