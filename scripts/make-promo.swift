#!/usr/bin/env swift
// Composes marketing images from Focal's demo snapshots.
//
//     open -g "focal://render-docs?dir=/tmp/focal-docs"
//     swift scripts/make-promo.swift /tmp/focal-docs/snapshots docs/promo
import AppKit

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: make-promo.swift <snapshots-dir> <output-dir>"); exit(1) }
let shots = URL(fileURLWithPath: args[1])
let out = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let canvas = NSSize(width: 2880, height: 1800)

struct Slide {
    let file: String
    let shot: String
    let eyebrow: String
    let title: String
    let body: String
    var hue: [NSColor]
}

let slides: [Slide] = [
    Slide(file: "01-hero", shot: "01-grid", eyebrow: "FOCAL FOR MAC",
          title: "Windows that\ncome to you.",
          body: "Every window of every app, with live previews. Pick one and it lands on the screen you are looking at. ⌥Space.",
          hue: [.systemIndigo, .systemPurple, .systemBlue]),
    Slide(file: "02-command-tab", shot: "02-list", eyebrow: "A BETTER ⌘TAB",
          title: "The window you\njust left is next.",
          body: "⌘Tab lists windows, not apps, in the order you used them. Type to search by tab or document title.",
          hue: [.systemBlue, .systemTeal, .systemIndigo]),
    Slide(file: "03-every-window", shot: "03-hidden", eyebrow: "NOTHING HIDES",
          title: "Full screen,\nother desktops —\nall in one list.",
          body: "App Exposé only shows the current Space. Focal finds every window and tells you where it is.",
          hue: [.systemOrange, .systemPink, .systemPurple]),
    Slide(file: "04-come-to-you", shot: "04-summon", eyebrow: "WINDOWS COME TO YOU",
          title: "Right screen,\nevery time.",
          body: "Minimized, on the other display, on another Space, off-screen or closed: switch to the app and its window appears under your cursor.",
          hue: [.systemTeal, .systemBlue, .systemMint]),
    Slide(file: "05-back-forward", shot: "05-sets", eyebrow: "BACK & FORWARD",
          title: "⌘Tab for whole\nsets of windows.",
          body: "Chrome and a series, then a quick look at Telegram? ⌥` puts both back where they were. ⌥⇧` goes forward.",
          hue: [.systemPurple, .systemIndigo, .systemPink]),
    Slide(file: "06-snap", shot: "06-snap", eyebrow: "SNAP LIKE WINDOWS",
          title: "Win + arrows,\non a Mac.",
          body: "⌃⌥ arrows for halves, quarters and full screen. ⌃⌥⇧ arrows throw a window to the other display, maximized.",
          hue: [.systemGreen, .systemTeal, .systemBlue]),
    Slide(file: "07-fixes-macos", shot: "07-settings", eyebrow: "FIXES WHAT MACOS GETS WRONG",
          title: "Finds the settings\nthat lose windows.",
          body: "Space rearranging, Stage Manager and friends, checked and fixed in one click. Nothing leaves your Mac.",
          hue: [.systemPink, .systemOrange, .systemPurple]),
]

func font(_ size: CGFloat, _ weight: NSFont.Weight, rounded: Bool = false) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard rounded, let d = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: d, size: size) ?? base
}

func symbol(_ name: String, _ size: CGFloat, _ color: NSColor) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        .applying(.init(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
}

func drawWallpaper(_ rect: NSRect, colors: [NSColor]) {
    NSColor(white: 0.06, alpha: 1).setFill()
    rect.fill()
    // Soft colored blobs.
    let blobs: [(CGFloat, CGFloat, CGFloat)] = [(0.78, 0.35, 0.55), (0.95, 0.85, 0.45), (0.45, 0.05, 0.5), (0.1, 0.9, 0.35)]
    for (i, b) in blobs.enumerated() {
        let c = colors[i % colors.count].withAlphaComponent(0.5)
        let r = rect.width * b.2
        let center = NSPoint(x: rect.width * b.0, y: rect.height * b.1)
        NSGradient(colors: [c, c.withAlphaComponent(0)])?
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: r, options: [])
    }
}

func drawMenuBar(_ rect: NSRect) {
    let h: CGFloat = 52
    let bar = NSRect(x: 0, y: rect.height - h, width: rect.width, height: h)
    NSColor(white: 0, alpha: 0.25).setFill()
    bar.fill()
    let fg = NSColor.white
    let attrs: [NSAttributedString.Key: Any] = [.font: font(26, .semibold), .foregroundColor: fg]
    let regular: [NSAttributedString.Key: Any] = [.font: font(26, .regular), .foregroundColor: fg]
    symbol("apple.logo", 26, fg)?.draw(in: NSRect(x: 40, y: bar.minY + 12, width: 26, height: 30))
    NSString(string: "Finder").draw(at: NSPoint(x: 100, y: bar.minY + 10), withAttributes: attrs)
    var x: CGFloat = 220
    for item in ["File", "Edit", "View", "Go", "Window"] {
        NSString(string: item).draw(at: NSPoint(x: x, y: bar.minY + 10), withAttributes: regular)
        x += NSString(string: item).size(withAttributes: regular).width + 44
    }
    // Status items, right to left.
    var right = rect.width - 40
    let time = "Mon 9 Nov  9:41"
    right -= NSString(string: time).size(withAttributes: regular).width
    NSString(string: time).draw(at: NSPoint(x: right, y: bar.minY + 10), withAttributes: regular)
    for name in ["switch.2", "magnifyingglass", "wifi", "battery.75percent"] {
        right -= 64
        symbol(name, 26, fg)?.draw(in: NSRect(x: right, y: bar.minY + 11, width: 40, height: 30))
    }
    // Focal's menu bar icon, highlighted.
    right -= 74
    let pill = NSRect(x: right - 10, y: bar.minY + 6, width: 60, height: 40)
    NSColor(white: 1, alpha: 0.22).setFill()
    NSBezierPath(roundedRect: pill, xRadius: 10, yRadius: 10).fill()
    symbol("rectangle.stack", 26, fg)?.draw(in: NSRect(x: right + 2, y: bar.minY + 10, width: 36, height: 30))
}

/// Places the snapshot centered in the right half, as large as fits.
func drawPanel(_ shot: NSImage) {
    let box = NSRect(x: 1390, y: 110, width: 1410, height: 1560)
    let scale = min(box.width / shot.size.width, box.height / shot.size.height, 1.0)
    let size = NSSize(width: shot.size.width * scale, height: shot.size.height * scale)
    let frame = NSRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
    shadow.shadowBlurRadius = 90
    shadow.shadowOffset = NSSize(width: 0, height: -30)
    shadow.set()
    shot.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
}

func drawCopy(_ slide: Slide) {
    let fg = NSColor.white
    let left: CGFloat = 170
    let maxWidth: CGFloat = 1150
    let para = NSMutableParagraphStyle()
    para.lineSpacing = 6

    let eyebrow: [NSAttributedString.Key: Any] = [
        .font: font(34, .bold), .foregroundColor: slide.hue[0].blended(withFraction: 0.35, of: fg) ?? fg, .kern: 4,
    ]
    let title: [NSAttributedString.Key: Any] = [.font: font(118, .bold, rounded: true), .foregroundColor: fg,
                                                 .paragraphStyle: para, .kern: -2]
    let body: [NSAttributedString.Key: Any] = [.font: font(46, .regular), .foregroundColor: fg.withAlphaComponent(0.72),
                                                .paragraphStyle: para]

    let t = NSAttributedString(string: slide.title, attributes: title)
    let b = NSAttributedString(string: slide.body, attributes: body)
    let tH = t.boundingRect(with: NSSize(width: maxWidth, height: 1200), options: .usesLineFragmentOrigin).height
    let bH = b.boundingRect(with: NSSize(width: maxWidth - 120, height: 1000), options: .usesLineFragmentOrigin).height
    let total = 50 + 40 + tH + 50 + bH
    var y = (canvas.height - 52) / 2 + total / 2

    y -= 50
    NSAttributedString(string: slide.eyebrow, attributes: eyebrow).draw(at: NSPoint(x: left, y: y))
    y -= 40 + tH
    t.draw(with: NSRect(x: left, y: y, width: maxWidth, height: tH), options: .usesLineFragmentOrigin)
    y -= 50 + bH
    b.draw(with: NSRect(x: left, y: y, width: maxWidth - 120, height: bH), options: .usesLineFragmentOrigin)
}

func render(_ slide: Slide) throws {
    guard let shot = NSImage(contentsOf: shots.appending(path: "\(slide.shot).png")) else {
        print("missing \(slide.shot)"); return
    }
    // Snapshots are @2x; treat their pixel size as points.
    if let rep = shot.representations.first { shot.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh) }

    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    rep.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(origin: .zero, size: canvas)
    drawWallpaper(rect, colors: slide.hue)
    drawMenuBar(rect)
    drawPanel(shot)
    drawCopy(slide)
    NSGraphicsContext.restoreGraphicsState()

    let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    try jpeg?.write(to: out.appending(path: "\(slide.file).jpg"))
    print("wrote \(slide.file).jpg")
}

for slide in slides { try render(slide) }
