import Carbon.HIToolbox

/// Global hotkeys via Carbon's RegisterEventHotKey (needs no extra permissions).
final class HotKeys {
    static let shared = HotKeys()

    struct Combo {
        let keyCode: Int
        let modifiers: Int
        let display: String
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            DispatchQueue.main.async { HotKeys.shared.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// Returns false if another app already owns the combination.
    @discardableResult
    func register(_ combo: Combo, _ handler: @escaping () -> Void) -> Bool {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(combo.keyCode), UInt32(combo.modifiers),
                                         EventHotKeyID(signature: OSType(0x46_4F_43_4C), id: id), // 'FOCL'
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs.append(ref)
        handlers[id] = handler
        return true
    }
}

extension HotKeys.Combo {
    static let switcher = Self(keyCode: kVK_Space, modifiers: optionKey, display: "⌥Space")
    static let back = Self(keyCode: kVK_ANSI_Grave, modifiers: optionKey, display: "⌥`")
    static let summon = Self(keyCode: kVK_Space, modifiers: optionKey | shiftKey, display: "⌥⇧Space")
    static let saveLayout = Self(keyCode: kVK_ANSI_S, modifiers: controlKey | optionKey, display: "⌃⌥S")

    static func snap(_ a: SnapAction) -> Self {
        let co = controlKey | optionKey
        switch a {
        case .left: return Self(keyCode: kVK_LeftArrow, modifiers: co, display: "⌃⌥←")
        case .right: return Self(keyCode: kVK_RightArrow, modifiers: co, display: "⌃⌥→")
        case .up: return Self(keyCode: kVK_UpArrow, modifiers: co, display: "⌃⌥↑")
        case .down: return Self(keyCode: kVK_DownArrow, modifiers: co, display: "⌃⌥↓")
        case .displayLeft: return Self(keyCode: kVK_LeftArrow, modifiers: co | shiftKey, display: "⌃⌥⇧←")
        case .displayRight: return Self(keyCode: kVK_RightArrow, modifiers: co | shiftKey, display: "⌃⌥⇧→")
        case .fullscreen: return Self(keyCode: kVK_ANSI_F, modifiers: co, display: "⌃⌥F")
        case .center: return Self(keyCode: kVK_ANSI_C, modifiers: co, display: "⌃⌥C")
        case .maximize: return Self(keyCode: kVK_Return, modifiers: co, display: "⌃⌥↩")
        case .restore: return Self(keyCode: kVK_Delete, modifiers: co, display: "⌃⌥⌫")
        }
    }

    static let digitKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                            kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
    static func layout(_ n: Int) -> Self {
        Self(keyCode: digitKeys[n], modifiers: controlKey | optionKey, display: "⌃⌥\(n + 1)")
    }
}
