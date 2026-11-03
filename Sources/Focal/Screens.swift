import AppKit

/// Converts between AppKit screen coordinates (bottom-left origin) and the global
/// top-left coordinates used by CGWindowList and the Accessibility API.
enum Screens {
    private static var primaryHeight: CGFloat {
        NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.screens.first?.frame.height ?? 0
    }

    static func topLeft(_ r: NSRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// Usable area (without menu bar and Dock) in top-left coordinates.
    static func visibleFrame(_ s: NSScreen) -> CGRect { topLeft(s.visibleFrame) }
    static func fullFrame(_ s: NSScreen) -> CGRect { topLeft(s.frame) }

    /// The display the user is working on: the one under the mouse pointer.
    static var current: NSScreen {
        // Test hook: `defaults write dev.focal.app debugScreen -int N` pins "where I am" to screen N.
        if let i = UserDefaults.standard.object(forKey: "debugScreen") as? Int, NSScreen.screens.indices.contains(i) {
            return NSScreen.screens[i]
        }
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// True when the display is showing a full-screen app (its own Space). Ordinary windows cannot
    /// be placed over it: moving one "there" puts it on that display's hidden desktop instead.
    static func isShowingFullScreen(_ s: NSScreen) -> Bool {
        let full = fullFrame(s)
        return Windows.cgWindows(onScreenOnly: true).contains { w in
            abs(w.frame.minX - full.minX) <= 1 && abs(w.frame.minY - full.minY) <= 1
                && abs(w.frame.width - full.width) <= 1 && abs(w.frame.height - full.height) <= 1
        }
    }

    /// Where pulled windows should go: the display I am on, unless it shows a full-screen app;
    /// then another display that does not; nil if every display is in full screen.
    static var pullTarget: NSScreen? {
        let here = current
        if !isShowingFullScreen(here) { return here }
        return NSScreen.screens.first { $0 !== here && !isShowingFullScreen($0) }
    }

    /// The display that holds most of `rect`, or nil if the rect is off every display.
    static func screen(for rect: CGRect) -> NSScreen? {
        var best: (NSScreen, CGFloat)?
        for s in NSScreen.screens {
            let i = fullFrame(s).intersection(rect)
            guard !i.isNull else { continue }
            let area = i.width * i.height
            if area > (best?.1 ?? 0) { best = (s, area) }
        }
        return best?.0
    }

    /// Moves `rect` from its display onto `target`, keeping its relative position and fitting it inside.
    static func translate(_ rect: CGRect, to target: NSScreen) -> CGRect {
        let dst = visibleFrame(target)
        var size = CGSize(width: min(rect.width, dst.width), height: min(rect.height, dst.height))
        if size.width < 200 || size.height < 150 { size = CGSize(width: dst.width * 0.7, height: dst.height * 0.8) }
        var origin: CGPoint
        if let src = screen(for: rect).map(visibleFrame), src.width > size.width, src.height > size.height {
            let rx = (rect.minX - src.minX) / (src.width - rect.width)
            let ry = (rect.minY - src.minY) / (src.height - rect.height)
            origin = CGPoint(x: dst.minX + clamp(rx) * (dst.width - size.width),
                             y: dst.minY + clamp(ry) * (dst.height - size.height))
        } else {
            origin = CGPoint(x: dst.midX - size.width / 2, y: dst.midY - size.height / 2)
        }
        origin.x = origin.x.rounded(); origin.y = origin.y.rounded()
        return CGRect(origin: origin, size: size)
    }

    private static func clamp(_ v: CGFloat) -> CGFloat { v.isFinite ? min(max(v, 0), 1) : 0.5 }
}
