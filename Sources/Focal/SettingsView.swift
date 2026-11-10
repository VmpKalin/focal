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
    @AppStorage(Prefs.Key.switcherStyle) private var switcherStyle = "list"
    @AppStorage(Prefs.Key.replaceCommandTab) private var replaceCommandTab = true
    @AppStorage(Prefs.Key.language) private var language = Language.system.rawValue
    @State private var canRecord = Thumbnails.hasPermission

    @State private var trusted = AX.isTrusted
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var diag = MacSettings.read()
    private let tick = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section(tr("Access", "Доступ")) {
                HStack {
                    Image(systemName: trusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    VStack(alignment: .leading) {
                        Text(trusted ? tr("Accessibility access granted", "Доступ до Accessibility надано") : tr("Accessibility access needed", "Потрібен доступ до Accessibility"))
                        if !trusted {
                            Text(tr("Without it Focal can't move or raise windows. Turn Focal on in the list and come back here.", "Без нього Focal не може рухати й піднімати вікна. Увімкни Focal у списку і повернись сюди."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !trusted {
                        Button(tr("Grant access…", "Надати доступ…")) {
                            AX.requestTrust()
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                Toggle(tr("Launch at login", "Запускати при вході в систему"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() } catch { NSSound.beep() }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                // Names stay in their own language so you can find yours whatever is selected.
                Picker(tr("Language", "Мова"), selection: $language) {
                    Text(tr("System", "Як у системі")).tag(Language.system.rawValue)
                    Text("English").tag(Language.en.rawValue)
                    Text("Українська").tag(Language.uk.rawValue)
                }
            }

            Section {
                Toggle(tr("Bring the window to me when I switch to an app", "Притягувати вікно, коли перемикаюсь на застосунок"), isOn: $autoSummon)
                Group {
                    Toggle(tr("…even if it is open on another display", "…навіть якщо воно відкрите на іншому дисплеї"), isOn: $pullFromOtherDisplay)
                    Toggle(tr("…even if it is on another desktop (Space)", "…навіть якщо воно на іншому робочому столі (Space)"), isOn: $pullFromOtherSpace)
                    Toggle(tr("Open a new window if the app has none", "Відкривати нове вікно, якщо в застосунку немає жодного"), isOn: $reopenWhenNoWindows)
                }
                .disabled(!autoSummon)
                .padding(.leading, 16)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Leave these apps alone (bundle ids, comma-separated)", "Не чіпати ці застосунки (bundle id через кому)"))
                    TextField("", text: $ignoredApps, prompt: Text("com.apple.finder, com.example.app"))
                        .labelsHidden()
                }
            } header: {
                Text(tr("Windows come to you", "Вікна приходять до тебе"))
            } footer: {
                Text(tr("Works with ⌘Tab, Dock clicks, Spotlight, opening links and so on. The window appears on the display under your cursor, not “somewhere else”.", "Спрацьовує при ⌘Tab, кліку в Dock, Spotlight, відкритті посилання тощо. Вікно з'являється на дисплеї, де зараз курсор, а не «десь там»."))
            }

            Section {
                Picker(tr("Switcher style", "Вигляд перемикача"), selection: $switcherStyle) {
                    Text(tr("List", "Список")).tag("list")
                    Text(tr("Window previews", "Мініатюри вікон")).tag("grid")
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(tr("⌘Tab opens Focal's switcher instead of the system one", "⌘Tab відкриває перемикач Focal замість системного"), isOn: $replaceCommandTab)
                    Text(tr("Hold ⌘ and press Tab (⇧Tab goes back), release ⌘ to open. Search is still on ⌥Space.", "Тримай ⌘ і тисни Tab (⇧Tab — назад), відпусти ⌘, щоб відкрити. Пошук — як і раніше, на ⌥Space."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if switcherStyle == "grid" {
                    HStack {
                        Image(systemName: canRecord ? "checkmark.seal.fill" : "eye.slash").foregroundStyle(canRecord ? .green : .orange)
                        Text(canRecord ? tr("Previews show what's in each window right now", "Мініатюри показують, що зараз у вікні") : tr("Window contents need the Screen Recording permission (app icons without it)", "Для вмісту вікон потрібен дозвіл «Запис екрана» (без нього — іконки)"))
                        Spacer()
                        if !canRecord { Button(tr("Allow…", "Дозволити…")) { Thumbnails.requestPermission() } }
                    }
                }
                Toggle(tr("↩ in the switcher moves the window to my display", "↩ у перемикачі переносить вікно на мій дисплей"), isOn: $switcherBringsHere)
                Toggle(tr("Remember sets of windows I look at together", "Запам'ятовувати набори вікон, які я переглядаю разом"), isOn: $trackContexts)
                HStack {
                    Text(tr("Remember a set after", "Набір запам'ятовується через"))
                    Slider(value: $contextDwell, in: 0.5...5, step: 0.5).frame(width: 160)
                    Text(String(format: tr("%.1f s", "%.1f с"), contextDwell)).monospacedDigit()
                }
                .disabled(!trackContexts)
                HStack {
                    Text(tr("Sets remembered: \(contexts.history.count)", "Попередніх наборів у пам'яті: \(contexts.history.count)"))
                    Spacer()
                    Button(tr("Clear", "Очистити")) { contexts.clear() }
                }
            } header: {
                Text(tr("Switcher and sets", "Перемикач і набори"))
            }

            Section {
                if layouts.layouts.isEmpty {
                    Text(tr("None yet. Arrange your windows and press ⌃⌥S.", "Ще немає. Розклади вікна як треба і натисни ⌃⌥S.")).foregroundStyle(.secondary)
                }
                List {
                    ForEach(Array(layouts.layouts.enumerated()), id: \.element.id) { i, layout in
                        LayoutRow(layout: layout, index: i, store: layouts)
                    }
                    .onMove { layouts.move(from: $0, to: $1) }
                }
                .frame(minHeight: layouts.layouts.isEmpty ? 0 : CGFloat(min(layouts.layouts.count, 6)) * 44)
                Button(tr("Save what's on screen now…", "Зберегти те, що зараз на екрані…")) { layouts.promptAndSaveCurrent() }
            } header: {
                Text(tr("Saved sets", "Збережені набори"))
            } footer: {
                Text(tr("Restoring launches the apps, puts every window in place and brings them to the front. List order = ⌃⌥1…9 (drag to reorder).", "Відновлення запускає потрібні застосунки, розставляє вікна по місцях і піднімає їх нагору. Порядок у списку = ⌃⌥1…9 (перетягни, щоб змінити)."))
            }

            Section {
                ShortcutRow(keys: "⌃⌥← / →", text: tr("Left / right half. Again: onto the next display", "Ліва / права половина. Ще раз — на сусідній дисплей"))
                ShortcutRow(keys: "⌃⌥↑", text: tr("Maximize (from a half: top quarter)", "Розгорнути на весь екран (з половини — верхня чверть)"))
                ShortcutRow(keys: "⌃⌥↓", text: tr("Restore size (from a half: bottom quarter), otherwise minimize", "Відновити розмір (з половини — нижня чверть), інакше згорнути"))
                ShortcutRow(keys: "⌃⌥⇧← / →", text: tr("Move to the display on the left / right", "Перекинути на дисплей ліворуч / праворуч"))
                ShortcutRow(keys: "⌃⌥↩", text: tr("Fill screen", "Заповнити екран"))
                ShortcutRow(keys: "⌃⌥⌫", text: tr("Size before snapping", "Повернути розмір, який був до прилипання"))
                ShortcutRow(keys: "⌃⌥F", text: tr("Native macOS full screen (on/off)", "Справжній повноекранний режим macOS (вкл/викл)"))
                ShortcutRow(keys: "⌃⌥C", text: tr("Center", "Поставити по центру"))
                Toggle(tr("Maximize when moving to another display", "При перекиданні на інший дисплей розгортати на весь екран"), isOn: $maximizeOnDisplayMove)
            } header: {
                Text(tr("Active window (like Win + arrows on Windows)", "Активне вікно (як Win + стрілки у Windows)"))
            } footer: {
                Text(tr("⌃⌥ instead of the Windows key: on a Mac ⌘+arrows move the text cursor and ⌥⌘+arrows switch browser tabs.", "⌃⌥ замість клавіші Windows: ⌘+стрілки на Mac — це рух курсора по тексту, а ⌥⌘+стрілки перемикають вкладки в браузерах."))
            }

            Section(tr("Shortcuts", "Гарячі клавіші")) {
                ShortcutRow(keys: "⌥Space", text: tr("Switcher: every window, set and app, with search", "Перемикач: усі вікна, набори і застосунки з пошуком"))
                ShortcutRow(keys: "⌥`", text: tr("Back to the previous set of windows (again: further back)", "Назад до попереднього набору вікон (ще раз — ще далі назад)"))
                ShortcutRow(keys: "⌥⇧`", text: tr("Forward, towards the current set", "Вперед — назад до поточного набору"))
                ShortcutRow(keys: "⌥⇧Space", text: tr("Bring the active app's window to my display", "Притягнути вікно активного застосунку на мій дисплей"))
                ShortcutRow(keys: "⌃⌥S", text: tr("Save the current set of windows", "Зберегти поточний набір вікон"))
                ShortcutRow(keys: "⌃⌥1…9", text: tr("Restore a saved set", "Відновити збережений набір"))
                if !failedHotKeys.isEmpty {
                    Text(tr("Taken by another app: ", "Зайняті іншою програмою: ") + failedHotKeys.joined(separator: ", ")).foregroundStyle(.orange)
                }
            }

            Section {
                DiagRow(ok: !diag.rearrangeSpaces,
                        title: tr("Automatically rearrange Spaces", "Автоматично переставляти робочі столи (Spaces)"),
                        value: diag.rearrangeSpaces ? tr("on", "увімкнено") : tr("off", "вимкнено"),
                        advice: tr("macOS reorders Spaces by recent use, which makes windows seem to wander. Better off.", "macOS сам міняє порядок Spaces за останнім використанням — через це вікна «губляться». Краще вимкнути."),
                        fixTitle: diag.rearrangeSpaces ? tr("Turn off", "Вимкнути") : nil) {
                    MacSettings.disableSpaceRearranging { diag = MacSettings.read() }
                }
                DiagRow(ok: true,
                        title: tr("When switching to an app, switch to a Space with its windows", "При перемиканні на застосунок переходити на Space з його вікнами"),
                        value: diag.switchToSpaceWithWindows ? tr("on", "увімкнено") : tr("off", "вимкнено"),
                        advice: diag.switchToSpaceWithWindows
                            ? tr("macOS will jump you to another desktop. If you want windows to always come to you, turn this off and Focal brings the window over.", "macOS перекине тебе на інший робочий стіл. Якщо хочеш, щоб вікна завжди приходили до тебе, вимкни це — Focal сам притягне вікно.")
                            : tr("You stay where you are and Focal brings the window here.", "Ти лишаєшся на місці, а Focal притягує вікно сюди."),
                        fixTitle: nil) {}
                DiagRow(ok: !diag.stageManager,
                        title: "Stage Manager",
                        value: diag.stageManager ? tr("on", "увімкнено") : tr("off", "вимкнено"),
                        advice: tr("Stage Manager groups and hides windows on its own, which clashes with Focal's sets.", "Stage Manager сам групує і ховає вікна, що конфліктує з наборами Focal."),
                        fixTitle: nil) {}
                DiagRow(ok: true,
                        title: tr("Displays have separate Spaces", "Окремі Spaces для кожного дисплея"),
                        value: diag.separateSpaces ? tr("yes", "так") : tr("no", "ні"),
                        advice: tr("Focal works either way; the window moves to the display under the cursor.", "Focal працює в обох режимах; вікно переїжджає на дисплей під курсором."),
                        fixTitle: nil) {}
                Button(tr("Open Desktop & Dock settings", "Відкрити «Робочий стіл і Dock»")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
                }
            } header: {
                Text(tr("macOS settings that get in the way", "Налаштування macOS, що заважають"))
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 760)
        .onReceive(tick) { _ in
            trusted = AX.isTrusted
            canRecord = Thumbnails.hasPermission
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
                TextField(tr("Name", "Назва"), text: $name).textFieldStyle(.plain)
                    .onSubmit { store.rename(layout, to: name) }
                Text(layout.windows.map(\.appName).joined(separator: " + ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Button(tr("Open", "Відкрити")) { Task { await store.restore(layout) } }
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
        alert.messageText = tr("Turn off automatic Space rearranging?", "Вимкнути автоматичне переставляння Spaces?")
        alert.informativeText = tr("It is the same switch as in System Settings → Desktop & Dock. The Dock will restart (windows stay open).", "Це той самий перемикач, що й у Системних параметрах → Робочий стіл і Dock. Dock перезапуститься (вікна не закриються).")
        alert.addButton(withTitle: tr("Turn off", "Вимкнути"))
        alert.addButton(withTitle: tr("Cancel", "Скасувати"))
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
