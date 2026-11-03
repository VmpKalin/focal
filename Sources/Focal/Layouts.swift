import AppKit

/// A named, saved set of windows with positions ("Work", "Series", ...). Restoring one launches
/// missing apps, opens windows, puts every window back in place and raises them in order.
struct Layout: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var windows: [WindowSnapshot]
}

@MainActor
final class LayoutStore: ObservableObject {
    @Published private(set) var layouts: [Layout] = []
    private let url = Prefs.supportDirectory.appendingPathComponent("layouts.json")
    private var persistent = true

    /// In-memory store with fixed layouts (README screenshots); never touches disk.
    init(demo: [Layout]) {
        layouts = demo
        persistent = false
    }

    init() {
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([Layout].self, from: data) {
            layouts = saved
        }
    }

    private func save() {
        guard persistent else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(layouts) { try? data.write(to: url) }
    }

    /// Saves what is visible on screen now.
    @discardableResult
    func saveCurrent(named name: String) -> Layout? {
        let snaps = Windows.snapshot(Windows.visibleWindowIDs())
        guard !snaps.isEmpty else { return nil }
        if let i = layouts.firstIndex(where: { $0.name == name }) {
            layouts[i].windows = snaps
            save()
            return layouts[i]
        }
        let layout = Layout(name: name, windows: snaps)
        layouts.append(layout)
        save()
        return layout
    }

    func rename(_ layout: Layout, to name: String) {
        guard let i = layouts.firstIndex(where: { $0.id == layout.id }) else { return }
        layouts[i].name = name
        save()
    }

    func delete(_ layout: Layout) {
        layouts.removeAll { $0.id == layout.id }
        save()
    }

    func move(from: IndexSet, to: Int) {
        layouts.move(fromOffsets: from, toOffset: to)
        save()
    }

    func restore(_ layout: Layout) async {
        await Actions.restore(layout.windows, applyFrames: true, launchMissing: true)
    }

    func restore(at index: Int) async {
        guard layouts.indices.contains(index) else { NSSound.beep(); return }
        await restore(layouts[index])
    }

    /// Asks for a name and saves the current screen as a layout.
    func promptAndSaveCurrent() {
        let alert = NSAlert()
        alert.messageText = "Зберегти поточний набір вікон"
        alert.informativeText = "Усі вікна, які зараз видно на екранах, і їхні позиції. Відновлення: ⌃⌥1…9 (за порядком у списку)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Наприклад: Робота, Серіал"
        field.stringValue = "Набір \(layouts.count + 1)"
        alert.accessoryView = field
        alert.addButton(withTitle: "Зберегти")
        alert.addButton(withTitle: "Скасувати")
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        if saveCurrent(named: name.isEmpty ? "Набір \(layouts.count + 1)" : name) == nil { NSSound.beep() }
    }
}
