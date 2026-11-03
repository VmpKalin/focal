import AppKit

/// Windows-style window management for the focused window (Win+arrows → ⌃⌥+arrows).
///
///   ⌃⌥←/→    left/right half; again → continues onto the next display (like Windows)
///   ⌃⌥↑      maximize; from a half → top quarter
///   ⌃⌥↓      restore from maximized; from a half → bottom quarter; free window → minimize
///   ⌃⌥⇧←/→   move to the display on the left/right (maximized there by default)
///   ⌃⌥F      native full screen, ⌃⌥C center
enum SnapAction: String, CaseIterable {
    case left, right, up, down, maximize, center, restore, fullscreen, displayLeft, displayRight
}

@MainActor
enum Snap {
    enum Region: CaseIterable { case leftHalf, rightHalf, topLeft, topRight, bottomLeft, bottomRight, full }

    /// Frame a window had before Focal snapped it, for ⌃⌥↓ "restore".
    private static var savedFrames: [CGWindowID: CGRect] = [:]

    private static func sleep(_ ms: UInt64) async { try? await Task.sleep(nanoseconds: ms * 1_000_000) }

    static func focusedWindow() -> (AXUIElement, pid_t)? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != Windows.ownPID else { return nil }
        let pid = app.processIdentifier
        let axApp = AX.app(pid)
        // A minimized window is neither focused nor main; fall back to the app's first window.
        guard let el = AX.element(axApp, kAXFocusedWindowAttribute) ?? AX.element(axApp, kAXMainWindowAttribute)
                ?? AX.windows(pid).first else { return nil }
        return (el, pid)
    }

    static func rect(_ r: Region, in v: CGRect) -> CGRect {
        let hw = (v.width / 2).rounded(), hh = (v.height / 2).rounded()
        switch r {
        case .leftHalf: return CGRect(x: v.minX, y: v.minY, width: hw, height: v.height)
        case .rightHalf: return CGRect(x: v.minX + hw, y: v.minY, width: v.width - hw, height: v.height)
        case .topLeft: return CGRect(x: v.minX, y: v.minY, width: hw, height: hh)
        case .topRight: return CGRect(x: v.minX + hw, y: v.minY, width: v.width - hw, height: hh)
        case .bottomLeft: return CGRect(x: v.minX, y: v.minY + hh, width: hw, height: v.height - hh)
        case .bottomRight: return CGRect(x: v.minX + hw, y: v.minY + hh, width: v.width - hw, height: v.height - hh)
        case .full: return v
        }
    }

    /// Which snap region a frame is in. Tolerant, because apps like Terminal resize in character steps.
    static func region(of f: CGRect, in v: CGRect) -> Region? {
        Region.allCases.first { r in
            let t = rect(r, in: v)
            return abs(f.minX - t.minX) <= 20 && abs(f.minY - t.minY) <= 20 && abs(f.maxX - t.maxX) <= 20 && abs(f.maxY - t.maxY) <= 20
        }
    }

    /// The display to the left (-1) or right (+1). `wrap` cycles around the ends.
    static func neighbor(of screen: NSScreen, _ dir: Int, wrap: Bool) -> NSScreen? {
        let sorted = NSScreen.screens.sorted { $0.frame.midX < $1.frame.midX }
        guard sorted.count > 1, let i = sorted.firstIndex(of: screen) else { return nil }
        let j = i + dir
        if sorted.indices.contains(j) { return sorted[j] }
        return wrap ? sorted[(j + sorted.count) % sorted.count] : nil
    }

    /// Sets a frame and re-applies it if the app adjusted it afterwards. Apps moving to a display
    /// with a different size or scale often clamp the size to the old display a moment later.
    static func setFrame(_ el: AXUIElement, _ r: CGRect) async {
        AX.setFrame(el, r)
        for _ in 0..<4 {
            await sleep(90)
            guard let f = AX.frame(el) else { return }
            if abs(f.minX - r.minX) + abs(f.minY - r.minY) + abs(f.width - r.width) + abs(f.height - r.height) <= 4 { return }
            AX.setFrame(el, r)
        }
    }

    static func perform(_ action: SnapAction) async {
        guard AX.isTrusted, let (el, _) = focusedWindow() else { NSSound.beep(); return }
        Actions.beginBusy(); defer { Actions.endBusy() }

        let isFullScreen = AX.bool(el, "AXFullScreen") == true
        if action == .fullscreen {
            AX.set(el, "AXFullScreen", (!isFullScreen) as CFBoolean)
            return
        }
        if isFullScreen {
            // A native full-screen window lives on its own Space; leave it first.
            AX.set(el, "AXFullScreen", kCFBooleanFalse)
            await sleep(900)
            if action == .down { return }
        }
        if AX.bool(el, kAXMinimizedAttribute) == true {
            AX.set(el, kAXMinimizedAttribute, kCFBooleanFalse)
            await sleep(300)
        }

        guard let f = AX.frame(el) else { NSSound.beep(); return }
        let id = AX.windowID(el)
        let screen = Screens.screen(for: f) ?? Screens.current
        let v = Screens.visibleFrame(screen)
        let current = region(of: f, in: v)

        func place(_ r: Region, on s: NSScreen? = nil) async {
            if current == nil, let id { savedFrames[id] = f }
            await setFrame(el, rect(r, in: s.map(Screens.visibleFrame) ?? v))
        }

        func restore() async {
            var target = id.flatMap { savedFrames.removeValue(forKey: $0) }
                ?? CGRect(x: 0, y: 0, width: v.width * 0.6, height: v.height * 0.75)
            if Screens.screen(for: target) !== screen {
                target = CGRect(x: v.midX - target.width / 2, y: v.midY - target.height / 2,
                                width: min(target.width, v.width), height: min(target.height, v.height))
            }
            await setFrame(el, target)
        }

        switch action {
        case .left, .right:
            let dir = action == .left ? -1 : 1
            let (half, other) = dir < 0 ? (Region.leftHalf, Region.rightHalf) : (.rightHalf, .leftHalf)
            switch current {
            case half:
                // Already on this side: continue onto the next display, like Windows.
                if let next = neighbor(of: screen, dir, wrap: false) { await place(other, on: next) }
            case other:
                await restore()
            case .topLeft where dir > 0: await place(.topRight)
            case .bottomLeft where dir > 0: await place(.bottomRight)
            case .topRight where dir < 0: await place(.topLeft)
            case .bottomRight where dir < 0: await place(.bottomLeft)
            default:
                await place(half)
            }
        case .up:
            switch current {
            case .leftHalf: await place(.topLeft)
            case .rightHalf: await place(.topRight)
            case .bottomLeft: await place(.leftHalf)
            case .bottomRight: await place(.rightHalf)
            case .full: break
            default: await place(.full)
            }
        case .down:
            switch current {
            case .full: await restore()
            case .leftHalf: await place(.bottomLeft)
            case .rightHalf: await place(.bottomRight)
            case .topLeft: await place(.leftHalf)
            case .topRight: await place(.rightHalf)
            default:
                AX.set(el, kAXMinimizedAttribute, kCFBooleanTrue)
                return // raising a minimized window would bring it straight back
            }
        case .maximize:
            await place(.full)
        case .restore:
            await restore()
        case .center:
            let size = CGSize(width: min(f.width, v.width), height: min(f.height, v.height))
            await setFrame(el, CGRect(x: (v.midX - size.width / 2).rounded(), y: (v.midY - size.height / 2).rounded(),
                                   width: size.width, height: size.height))
        case .displayLeft, .displayRight:
            guard let next = neighbor(of: screen, action == .displayLeft ? -1 : 1, wrap: true) else { NSSound.beep(); return }
            if let id {
                // Keep a sensible "restore" size on the new display.
                savedFrames[id] = Screens.translate(current == nil ? f : (savedFrames[id] ?? f), to: next)
            }
            if Prefs.bool(Prefs.Key.maximizeOnDisplayMove) {
                await setFrame(el, Screens.visibleFrame(next))
            } else if let current {
                await setFrame(el, rect(current, in: Screens.visibleFrame(next)))
            } else {
                await setFrame(el, Screens.translate(f, to: next))
            }
        case .fullscreen:
            break
        }
        AX.perform(el, kAXRaiseAction)
    }
}
