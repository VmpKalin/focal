import AppKit
import SwiftUI

/// Renders README screenshots with demo data (`open "focal://render-docs?dir=/path"`), so no real
/// window titles end up in the docs. Views are drawn offscreen; no screen-recording permission needed.
@MainActor
enum DocsRender {
    static func renderAll(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let contexts = ContextTracker.demo()
        let layouts = LayoutStore(demo: [
            Layout(name: "Робота", windows: demoSnaps(["Mail", "Calendar", "Terminal"])),
            Layout(name: "Серіал", windows: demoSnaps(["Safari", "Notes"])),
        ])
        let model = SwitcherModel(contexts: contexts, layouts: layouts)

        model.showDemo(demoItems(), style: .list, selection: 1)
        save(scene(SwitcherView(model: model, thumbs: model.thumbnails) { _ in }), dir, "switcher-list.png")

        model.showDemo(demoItems(), style: .grid, selection: 1)
        save(scene(SwitcherView(model: model, thumbs: model.thumbnails) { _ in }), dir, "switcher-grid.png")

        save(scene(SnapDiagram(), padding: 0), dir, "snapping.png")
        save(SettingsView(layouts: layouts, contexts: contexts, failedHotKeys: []).environment(\.colorScheme, .dark)
                .background(Color(nsColor: .windowBackgroundColor)), dir, "settings.png")
    }

    // MARK: Rendering

    private static func scene<V: View>(_ content: V, padding: CGFloat = 56) -> some View {
        content
            .padding(padding)
            .background(LinearGradient(colors: [Color(red: 0.16, green: 0.12, blue: 0.32), Color(red: 0.05, green: 0.27, blue: 0.42)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .environment(\.colorScheme, .dark)
    }

    private static func save<V: View>(_ view: V, _ dir: URL, _ name: String) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: host.frame.width, height: host.frame.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
        window.contentView = nil
    }

    // MARK: Demo data

    private static func demoSnaps(_ apps: [String]) -> [WindowSnapshot] {
        apps.enumerated().map { WindowSnapshot(windowID: CGWindowID($0.offset), pid: 0, bundleID: nil, appName: $0.element, title: "", frame: .zero) }
    }

    private static func icon(_ path: String) -> NSImage { NSWorkspace.shared.icon(forFile: path) }

    private static func demoItems() -> [SwitchItem] {
        let me = NSRunningApplication.current
        func w(_ id: String, _ title: String, _ app: String, _ path: String, _ badges: [String], _ color: NSColor) -> SwitchItem {
            SwitchItem(id: id, kind: .noWindows(me), title: title, subtitle: app, icon: icon(path), symbol: nil,
                       badges: badges, preview: fakeWindow(color: color, title: title))
        }
        return [
            w("1", "Release notes — Pages", "Pages", "/Applications/Pages.app", [], .systemOrange),
            w("2", "Серіал — сезон 1, серія 4", "Safari", "/Applications/Safari.app", ["повний екран"], .black),
            w("3", "focal — zsh — 120×40", "Terminal", "/System/Applications/Utilities/Terminal.app", ["інший робочий стіл"], NSColor(white: 0.12, alpha: 1)),
            w("4", "Ідеї для відпустки", "Notes", "/System/Applications/Notes.app", ["U28 Display"], .systemYellow),
            w("5", "Робоча пошта", "Mail", "/System/Applications/Mail.app", [], .systemBlue),
            w("6", "Тиждень", "Calendar", "/System/Applications/Calendar.app", ["згорнуте"], .systemRed),
            w("7", "Музика — Плейлист «Фокус»", "Music", "/System/Applications/Music.app", [], .systemPink),
            SwitchItem(id: "c1", kind: .noWindows(me), title: "Safari + Notes", subtitle: "Серіал — сезон 1 · Ідеї для відпустки",
                       icon: nil, symbol: "clock.arrow.circlepath", badges: ["попередній набір"]),
            SwitchItem(id: "l1", kind: .noWindows(me), title: "Робота", subtitle: "Mail + Calendar + Terminal",
                       icon: nil, symbol: "square.grid.2x2", badges: ["⌃⌥1"]),
        ]
    }

    /// A schematic window: title bar, sidebar and content blocks in the app's colour.
    private static func fakeWindow(color: NSColor, title: String) -> NSImage {
        NSImage(size: NSSize(width: 520, height: 330), flipped: true) { r in
            NSColor(white: 0.95, alpha: 1).setFill(); NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
            NSColor(white: 0.85, alpha: 1).setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: r.width, height: 30)).fill()
            for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                c.setFill(); NSBezierPath(ovalIn: NSRect(x: 12 + i * 18, y: 10, width: 11, height: 11)).fill()
            }
            color.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: NSRect(x: 130, y: 46, width: 374, height: 170), xRadius: 6, yRadius: 6).fill()
            color.withAlphaComponent(0.25).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 30, width: 114, height: r.height - 30)).fill()
            NSColor(white: 0.75, alpha: 1).setFill()
            for i in 0..<4 { NSBezierPath(roundedRect: NSRect(x: 130, y: 232 + i * 22, width: 374 - i * 60, height: 10), xRadius: 4, yRadius: 4).fill() }
            for i in 0..<6 { NSBezierPath(roundedRect: NSRect(x: 14, y: 48 + i * 24, width: 84, height: 9), xRadius: 4, yRadius: 4).fill() }
            return true
        }
    }
}

/// Illustration of the ⌃⌥ arrow keys for the README.
private struct SnapDiagram: View {
    var body: some View {
        HStack(spacing: 28) {
            display(name: "Built-in", width: 360) {
                region("⌃⌥←", x: 0, y: 0, w: 0.5, h: 1, tint: .blue)
                region("⌃⌥↑ з половини", x: 0.5, y: 0, w: 0.5, h: 0.5, tint: .purple)
                region("⌃⌥↓ з половини", x: 0.5, y: 0.5, w: 0.5, h: 0.5, tint: .teal)
            }
            VStack(spacing: 10) {
                Text("⌃⌥⇧← / →").font(.system(size: 15, weight: .semibold, design: .monospaced))
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 30))
                Text("на інший дисплей\nі одразу на весь екран").font(.system(size: 12)).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            display(name: "Монітор", width: 440) {
                region("⌃⌥↑  на весь екран", x: 0, y: 0, w: 1, h: 1, tint: .green)
            }
        }
        .padding(40)
        .foregroundStyle(.white)
    }

    private func display<C: View>(name: String, width: CGFloat, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35))
                content()
            }
            .frame(width: width, height: width * 0.62)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.5), lineWidth: 2))
            Text(name).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private func region(_ label: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, tint: Color) -> some View {
        GeometryReader { g in
            RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.45))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(tint, lineWidth: 2))
                .overlay(Text(label).font(.system(size: 13, weight: .semibold, design: .monospaced)))
                .frame(width: g.size.width * w - 8, height: g.size.height * h - 8)
                .offset(x: g.size.width * x + 4, y: g.size.height * y + 4)
        }
    }
}
