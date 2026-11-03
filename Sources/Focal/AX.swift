import AppKit
import ApplicationServices

// Private but long-stable HIServices symbols (used by alt-tab-macos, yabai, AeroSpace, ...).
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

@_silgen_name("_AXUIElementCreateWithRemoteToken")
private func _AXUIElementCreateWithRemoteToken(_ data: CFData) -> Unmanaged<AXUIElement>?

/// Thin wrapper over the Accessibility API.
enum AX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func app(_ pid: pid_t) -> AXUIElement { AXUIElementCreateApplication(pid) }

    static func value(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
        return v
    }

    static func string(_ el: AXUIElement, _ name: String) -> String? { value(el, name) as? String }
    static func bool(_ el: AXUIElement, _ name: String) -> Bool? { value(el, name) as? Bool }

    static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = value(el, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    @discardableResult
    static func set(_ el: AXUIElement, _ name: String, _ v: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(el, name as CFString, v) == .success
    }

    @discardableResult
    static func perform(_ el: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(el, action as CFString) == .success
    }

    static func windowID(_ el: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(el, &id) == .success && id != 0 ? id : nil
    }

    // MARK: Geometry (AX uses global top-left coordinates, same as CGWindowList)

    static func frame(_ el: AXUIElement) -> CGRect? {
        guard let p = value(el, kAXPositionAttribute), let s = value(el, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &point)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    static func setFrame(_ el: AXUIElement, _ rect: CGRect) {
        var size = rect.size, point = rect.origin
        let sv = AXValueCreate(.cgSize, &size)!, pv = AXValueCreate(.cgPoint, &point)!
        // size → position → size: apps clamp size to the screen they are currently on.
        set(el, kAXSizeAttribute, sv)
        set(el, kAXPositionAttribute, pv)
        set(el, kAXSizeAttribute, sv)
    }

    // MARK: Windows

    static func isRealWindow(_ el: AXUIElement) -> Bool {
        let subrole = string(el, kAXSubroleAttribute)
        return subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole
    }

    /// Windows on the current Space(s), including minimized ones.
    static func windows(_ pid: pid_t) -> [AXUIElement] {
        (value(app(pid), kAXWindowsAttribute) as? [AXUIElement] ?? []).filter(isRealWindow)
    }

    /// Finds a window by id, including windows on other Spaces that kAXWindows does not report.
    static func window(pid: pid_t, id: CGWindowID) -> AXUIElement? {
        if let w = windows(pid).first(where: { windowID($0) == id }) { return w }
        return bruteForceWindows(pid, stopAt: id).first(where: { windowID($0) == id })
    }

    /// Windows of `pid` on every Space. Enumerates remote AX element tokens, the same trick alt-tab-macos uses.
    static func bruteForceWindows(_ pid: pid_t, stopAt target: CGWindowID? = nil) -> [AXUIElement] {
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: Int32(pid)) { Data($0) })
        token.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })
        var found: [AXUIElement] = []
        for elementID: UInt64 in 0..<1000 {
            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementID) { Data($0) })
            guard let el = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue(),
                  isRealWindow(el) else { continue }
            found.append(el)
            if let target, windowID(el) == target { break }
        }
        return found
    }
}
