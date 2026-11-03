import AppKit
import ScreenCaptureKit

/// Window previews for the grid switcher. macOS only hands out window images with the
/// Screen Recording permission; without it the grid falls back to app icons.
@MainActor
final class Thumbnails: ObservableObject {
    @Published private(set) var images: [CGWindowID: NSImage] = [:]
    private var loading: Task<Void, Never>?

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func requestPermission() {
        if !CGRequestScreenCaptureAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    /// Refreshes previews for `ids`; previous images stay visible until the new ones arrive.
    func load(_ ids: [CGWindowID]) {
        guard Self.hasPermission, !ids.isEmpty else { return }
        loading?.cancel()
        loading = Task { @MainActor in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else { return }
            let byID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
            for id in ids {
                guard !Task.isCancelled else { return }
                guard let w = byID[id], w.frame.width > 1, w.frame.height > 1 else { continue }
                let cfg = SCStreamConfiguration()
                let scale = min(1, 520 / w.frame.width)
                cfg.width = Int(w.frame.width * scale)
                cfg.height = Int(w.frame.height * scale)
                cfg.showsCursor = false
                guard let cg = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: w),
                                                                          configuration: cfg) else { continue }
                images[id] = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
        }
    }

    func forget(except alive: Set<CGWindowID>) {
        images = images.filter { alive.contains($0.key) }
    }
}
