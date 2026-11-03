// Draws the Focal app icon. Usage: swift scripts/make-icon.swift Resources/AppIcon.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Body on Apple's icon grid: 824×824 squircle with a soft shadow.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill(); squircle.fill()
ctx.restoreGState()
squircle.addClip()
NSGradient(colors: [NSColor(red: 0.33, green: 0.20, blue: 0.85, alpha: 1), NSColor(red: 0.10, green: 0.55, blue: 0.85, alpha: 1)])!
    .draw(in: body, angle: -55)

func window(_ r: NSRect, alpha: CGFloat, front: Bool) {
    let path = NSBezierPath(roundedRect: r, xRadius: 34, yRadius: 34)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor.black.withAlphaComponent(0.30).cgColor)
    NSColor.white.withAlphaComponent(alpha).setFill(); path.fill()
    ctx.restoreGState()
    let bar = NSRect(x: r.minX, y: r.maxY - 70, width: r.width, height: 70)
    NSGraphicsContext.saveGraphicsState(); path.addClip()
    NSColor(white: front ? 0.90 : 0.80, alpha: alpha).setFill(); NSBezierPath(rect: bar).fill()
    NSGraphicsContext.restoreGraphicsState()
    for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
        c.withAlphaComponent(front ? 1 : 0.6).setFill()
        NSBezierPath(ovalIn: NSRect(x: r.minX + 32 + CGFloat(i) * 40, y: bar.midY - 13, width: 26, height: 26)).fill()
    }
    if front {
        NSColor(red: 0.33, green: 0.25, blue: 0.85, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: NSRect(x: r.minX + 40, y: r.minY + 150, width: r.width - 80, height: r.height - 260), xRadius: 16, yRadius: 16).fill()
        NSColor(white: 0.78, alpha: 1).setFill()
        for i in 0..<2 {
            NSBezierPath(roundedRect: NSRect(x: r.minX + 40, y: r.minY + 50 + CGFloat(i) * 46, width: (r.width - 80) * (i == 0 ? 0.55 : 0.8), height: 22),
                         xRadius: 11, yRadius: 11).fill()
        }
    }
}

// A stack of windows, the front one "in focus".
window(NSRect(x: 330, y: 470, width: 470, height: 330), alpha: 0.45, front: false)
window(NSRect(x: 270, y: 390, width: 470, height: 330), alpha: 0.7, front: false)
let front = NSRect(x: 200, y: 230, width: 540, height: 400)
window(front, alpha: 1, front: true)
// Focus ring around the front window.
NSColor.white.withAlphaComponent(0.95).setStroke()
let ring = NSBezierPath(roundedRect: front.insetBy(dx: -22, dy: -22), xRadius: 52, yRadius: 52)
ring.lineWidth = 14
ring.stroke()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
