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
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let icon: NSImage?
    let symbol: String?
    let badges: [String]

    var searchable: String { "\(title) \(subtitle)" }
}

@MainActor
final class SwitcherModel: ObservableObject {
    @Published var query = "" { didSet { refilter() } }
    @Published private(set) var visible: [SwitchItem] = []
    @Published var selection = 0
    @Published var focusToken = UUID()

    private var all: [SwitchItem] = []
    let contexts: ContextTracker
    let layouts: LayoutStore

    init(contexts: ContextTracker, layouts: LayoutStore) {
        self.contexts = contexts
        self.layouts = layouts
    }

    func reload() {
        query = ""
        let here = Screens.current
        let windows = Windows.items()
        var items: [SwitchItem] = windows.map { w in
            var badges: [String] = []
            if w.isMinimized { badges.append("згорнуте") }
            else if !w.isOnScreen { badges.append("сховане") }
            else if let s = Screens.screen(for: w.frame), s !== here { badges.append(s.localizedName) }
            else if Screens.screen(for: w.frame) == nil { badges.append("за межами екрана") }
            return SwitchItem(id: "w\(w.id)", kind: .window(w), title: w.title,
                              subtitle: w.app.localizedName ?? "", icon: w.app.icon, symbol: nil, badges: badges)
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
        let withWindows = Set(windows.map(\.pid))
        for app in Windows.regularApps() where !withWindows.contains(app.processIdentifier) {
            let hasOff = !Windows.offSpaceWindows(app.processIdentifier).isEmpty
            items.append(SwitchItem(id: "a\(app.processIdentifier)", kind: hasOff ? .offSpace(app) : .noWindows(app),
                                    title: app.localizedName ?? "?", subtitle: hasOff ? "вікна на іншому робочому столі (Space)" : "немає відкритих вікон",
                                    icon: app.icon, symbol: nil, badges: [hasOff ? "інший Space" : "нове вікно"]))
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
            visible = all.compactMap { item in score(item.searchable.lowercased(), q).map { (item, $0) } }
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

    func move(_ delta: Int) {
        guard !visible.isEmpty else { return }
        selection = (selection + delta + visible.count) % visible.count
    }

    var selected: SwitchItem? { visible.indices.contains(selection) ? visible[selection] : nil }
}

// MARK: View

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
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
        .frame(width: 680, height: 460)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .onChange(of: model.focusToken) { _, _ in fieldFocused = true }
        .onAppear { fieldFocused = true }
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
    var onNeedsPermission: () -> Void = {}

    init(model: SwitcherModel) { self.model = model }

    var isShown: Bool { panel?.isVisible == true }

    func toggle() { isShown ? hide() : show() }

    func show() {
        guard AX.isTrusted else { onNeedsPermission(); return }
        model.reload()
        let panel = self.panel ?? makePanel()
        self.panel = panel
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
        p.contentView = NSHostingView(rootView: SwitcherView(model: model) { [weak self] item in
            self?.activate(item, flipPlacement: false)
        })
        return p
    }

    private func handle(_ e: NSEvent) -> NSEvent? {
        guard isShown, e.window === panel else { return e }
        let cmd = e.modifierFlags.contains(.command)
        switch Int(e.keyCode) {
        case 125: model.move(1)                                  // ↓
        case 126: model.move(-1)                                 // ↑
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
