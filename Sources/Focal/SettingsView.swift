import AppKit
import Combine
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var layouts: LayoutStore
    @ObservedObject var contexts: ContextTracker
    let failedHotKeys: [String]

    @AppStorage(Prefs.Key.autoSummon) private var autoSummon = true
    @AppStorage(Prefs.Key.pullFromOtherDisplay) private var pullFromOtherDisplay = true
    @AppStorage(Prefs.Key.pullFromOtherSpace) private var pullFromOtherSpace = true
    @AppStorage(Prefs.Key.reopenWhenNoWindows) private var reopenWhenNoWindows = true
    @AppStorage(Prefs.Key.switcherBringsHere) private var switcherBringsHere = true
    @AppStorage(Prefs.Key.trackContexts) private var trackContexts = true
    @AppStorage(Prefs.Key.contextDwell) private var contextDwell = 1.5
    @AppStorage(Prefs.Key.ignoredApps) private var ignoredApps = "com.apple.finder"
    @AppStorage(Prefs.Key.maximizeOnDisplayMove) private var maximizeOnDisplayMove = true

    @State private var trusted = AX.isTrusted
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var diag = MacSettings.read()
    private let tick = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Доступ") {
                HStack {
                    Image(systemName: trusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    VStack(alignment: .leading) {
                        Text(trusted ? "Доступ до Accessibility надано" : "Потрібен доступ до Accessibility")
                        if !trusted {
                            Text("Без нього Focal не може рухати й піднімати вікна. Увімкни Focal у списку і повернись сюди.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !trusted {
                        Button("Надати доступ…") {
                            AX.requestTrust()
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                Toggle("Запускати при вході в систему", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() } catch { NSSound.beep() }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
            }

            Section {
                Toggle("Притягувати вікно, коли перемикаюсь на застосунок", isOn: $autoSummon)
                Group {
                    Toggle("…навіть якщо воно відкрите на іншому дисплеї", isOn: $pullFromOtherDisplay)
                    Toggle("…навіть якщо воно на іншому робочому столі (Space)", isOn: $pullFromOtherSpace)
                    Toggle("Відкривати нове вікно, якщо в застосунку немає жодного", isOn: $reopenWhenNoWindows)
                }
                .disabled(!autoSummon)
                .padding(.leading, 16)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Не чіпати ці застосунки (bundle id через кому)")
                    TextField("com.apple.finder, com.example.app", text: $ignoredApps)
                }
            } header: {
                Text("Вікна приходять до тебе")
            } footer: {
                Text("Спрацьовує при ⌘Tab, кліку в Dock, Spotlight, відкритті посилання тощо. Вікно з'являється на дисплеї, де зараз курсор, а не «десь там».")
            }

            Section {
                Toggle("↩ у перемикачі переносить вікно на мій дисплей", isOn: $switcherBringsHere)
                Toggle("Запам'ятовувати набори вікон, які я переглядаю разом", isOn: $trackContexts)
                HStack {
                    Text("Набір запам'ятовується через")
                    Slider(value: $contextDwell, in: 0.5...5, step: 0.5).frame(width: 160)
                    Text(String(format: "%.1f с", contextDwell)).monospacedDigit()
                }
                .disabled(!trackContexts)
                HStack {
                    Text("Попередніх наборів у пам'яті: \(contexts.history.count)")
                    Spacer()
                    Button("Очистити") { contexts.clear() }
                }
            } header: {
                Text("Перемикач і набори")
            }

            Section {
                if layouts.layouts.isEmpty {
                    Text("Ще немає. Розклади вікна як треба і натисни ⌃⌥S.").foregroundStyle(.secondary)
                }
                List {
                    ForEach(Array(layouts.layouts.enumerated()), id: \.element.id) { i, layout in
                        LayoutRow(layout: layout, index: i, store: layouts)
                    }
                    .onMove { layouts.move(from: $0, to: $1) }
                }
                .frame(minHeight: layouts.layouts.isEmpty ? 0 : CGFloat(min(layouts.layouts.count, 6)) * 44)
                Button("Зберегти те, що зараз на екрані…") { layouts.promptAndSaveCurrent() }
            } header: {
                Text("Збережені набори")
            } footer: {
                Text("Відновлення запускає потрібні застосунки, розставляє вікна по місцях і піднімає їх нагору. Порядок у списку = ⌃⌥1…9 (перетягни, щоб змінити).")
            }

            Section {
                ShortcutRow(keys: "⌃⌥← / →", text: "Ліва / права половина. Ще раз — на сусідній дисплей")
                ShortcutRow(keys: "⌃⌥↑", text: "Розгорнути на весь екран (з половини — верхня чверть)")
                ShortcutRow(keys: "⌃⌥↓", text: "Відновити розмір (з половини — нижня чверть), інакше згорнути")
                ShortcutRow(keys: "⌃⌥⇧← / →", text: "Перекинути на дисплей ліворуч / праворуч")
                ShortcutRow(keys: "⌃⌥↩", text: "Заповнити екран")
                ShortcutRow(keys: "⌃⌥⌫", text: "Повернути розмір, який був до прилипання")
                ShortcutRow(keys: "⌃⌥F", text: "Справжній повноекранний режим macOS (вкл/викл)")
                ShortcutRow(keys: "⌃⌥C", text: "Поставити по центру")
                Toggle("При перекиданні на інший дисплей розгортати на весь екран", isOn: $maximizeOnDisplayMove)
            } header: {
                Text("Активне вікно (як Win + стрілки у Windows)")
            } footer: {
                Text("⌃⌥ замість клавіші Windows: ⌘+стрілки на Mac — це рух курсора по тексту, а ⌥⌘+стрілки перемикають вкладки в браузерах.")
            }

            Section("Гарячі клавіші") {
                ShortcutRow(keys: "⌥Space", text: "Перемикач: усі вікна, набори і застосунки з пошуком")
                ShortcutRow(keys: "⌥`", text: "Назад до попереднього набору вікон (ще раз — повернутись)")
                ShortcutRow(keys: "⌥⇧Space", text: "Притягнути вікно активного застосунку на мій дисплей")
                ShortcutRow(keys: "⌃⌥S", text: "Зберегти поточний набір вікон")
                ShortcutRow(keys: "⌃⌥1…9", text: "Відновити збережений набір")
                if !failedHotKeys.isEmpty {
                    Text("Зайняті іншою програмою: \(failedHotKeys.joined(separator: ", "))").foregroundStyle(.orange)
                }
            }

            Section {
                DiagRow(ok: !diag.rearrangeSpaces,
                        title: "Автоматично переставляти робочі столи (Spaces)",
                        value: diag.rearrangeSpaces ? "увімкнено" : "вимкнено",
                        advice: "macOS сам міняє порядок Spaces за останнім використанням — через це вікна «губляться». Краще вимкнути.",
                        fixTitle: diag.rearrangeSpaces ? "Вимкнути" : nil) {
                    MacSettings.disableSpaceRearranging { diag = MacSettings.read() }
                }
                DiagRow(ok: true,
                        title: "При перемиканні на застосунок переходити на Space з його вікнами",
                        value: diag.switchToSpaceWithWindows ? "увімкнено" : "вимкнено",
                        advice: diag.switchToSpaceWithWindows
                            ? "macOS перекине тебе на інший робочий стіл. Якщо хочеш, щоб вікна завжди приходили до тебе, вимкни це — Focal сам притягне вікно."
                            : "Ти лишаєшся на місці, а Focal притягує вікно сюди.",
                        fixTitle: nil) {}
                DiagRow(ok: !diag.stageManager,
                        title: "Stage Manager",
                        value: diag.stageManager ? "увімкнено" : "вимкнено",
                        advice: "Stage Manager сам групує і ховає вікна, що конфліктує з наборами Focal.",
                        fixTitle: nil) {}
                DiagRow(ok: true,
                        title: "Окремі Spaces для кожного дисплея",
                        value: diag.separateSpaces ? "так" : "ні",
                        advice: "Focal працює в обох режимах; вікно переїжджає на дисплей під курсором.",
                        fixTitle: nil) {}
                Button("Відкрити «Робочий стіл і Dock»") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
                }
            } header: {
                Text("Налаштування macOS, що заважають")
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 760)
        .onReceive(tick) { _ in
            trusted = AX.isTrusted
            diag = MacSettings.read()
        }
    }
}

private struct ShortcutRow: View {
    let keys: String
    let text: String
    var body: some View {
        HStack {
            Text(keys).font(.system(.body, design: .monospaced)).frame(width: 90, alignment: .leading)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

private struct DiagRow: View {
    let ok: Bool
    let title: String
    let value: String
    let advice: String
    let fixTitle: String?
    let fix: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: ok ? "checkmark.circle" : "exclamationmark.circle").foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary) }
                Text(advice).font(.caption).foregroundStyle(.secondary)
            }
            if let fixTitle { Button(fixTitle, action: fix) }
        }
    }
}

private struct LayoutRow: View {
    let layout: Layout
    let index: Int
    @ObservedObject var store: LayoutStore
    @State private var name = ""

    var body: some View {
        HStack {
            Text(index < 9 ? "⌃⌥\(index + 1)" : "").font(.system(.caption, design: .monospaced)).frame(width: 34)
            VStack(alignment: .leading) {
                TextField("Назва", text: $name).textFieldStyle(.plain)
                    .onSubmit { store.rename(layout, to: name) }
                Text(layout.windows.map(\.appName).joined(separator: " + ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Button("Відкрити") { Task { await store.restore(layout) } }
            Button(role: .destructive) { store.delete(layout) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
        }
        .onAppear { name = layout.name }
    }
}

/// Reads the macOS window-management settings that cause "lost" windows.
enum MacSettings {
    struct State {
        var rearrangeSpaces: Bool
        var switchToSpaceWithWindows: Bool
        var stageManager: Bool
        var separateSpaces: Bool
    }

    private static func bool(_ key: String, _ domain: String, default def: Bool) -> Bool {
        (CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? Bool) ?? def
    }

    static func read() -> State {
        State(rearrangeSpaces: bool("mru-spaces", "com.apple.dock", default: true),
              switchToSpaceWithWindows: bool("workspaces-auto-swoosh", "com.apple.dock", default: true),
              stageManager: bool("GloballyEnabled", "com.apple.WindowManager", default: false),
              separateSpaces: !bool("spans-displays", "com.apple.spaces", default: false))
    }

    /// Same as unticking "Automatically rearrange Spaces based on most recent use" in System Settings.
    static func disableSpaceRearranging(done: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Вимкнути автоматичне переставляння Spaces?"
        alert.informativeText = "Це той самий перемикач, що й у Системних параметрах → Робочий стіл і Dock. Dock перезапуститься (вікна не закриються)."
        alert.addButton(withTitle: "Вимкнути")
        alert.addButton(withTitle: "Скасувати")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        run("/usr/bin/defaults", ["write", "com.apple.dock", "mru-spaces", "-bool", "false"])
        run("/usr/bin/killall", ["Dock"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { done() }
    }

    private static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
    }
}
