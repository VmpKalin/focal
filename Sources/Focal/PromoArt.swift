import SwiftUI

// Illustrations for the promo images (`focal://render-docs`). English, because they are
// marketing art rather than app UI. Each is drawn as a dark rounded card like Focal's panels.

private let cardBackground = Color(red: 0.11, green: 0.11, blue: 0.14)

private struct PromoCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(44)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(cardBackground))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12)))
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
    }
}

/// A display with an optional window drawn inside.
private struct MiniDisplay: View {
    let name: String
    let width: CGFloat
    var windows: [(rect: CGRect, tint: Color, ghost: Bool)] = []
    var cursor: CGPoint? = nil

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [Color(red: 0.2, green: 0.24, blue: 0.42), Color(red: 0.12, green: 0.32, blue: 0.45)],
                                                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                Rectangle().fill(.white.opacity(0.18)).frame(height: 10)
                GeometryReader { g in
                    ForEach(Array(windows.enumerated()), id: \.offset) { _, w in
                        MiniWindow(tint: w.tint, ghost: w.ghost)
                            .frame(width: g.size.width * w.rect.width, height: g.size.height * w.rect.height)
                            .offset(x: g.size.width * w.rect.minX, y: g.size.height * w.rect.minY)
                    }
                    if let cursor {
                        Image(systemName: "cursorarrow").font(.system(size: 30, weight: .bold))
                            .shadow(radius: 3)
                            .offset(x: g.size.width * cursor.x, y: g.size.height * cursor.y)
                    }
                }
            }
            .frame(width: width, height: width * 0.6)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.55), lineWidth: 3))
            Text(name).font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
        }
    }
}

private struct MiniWindow: View {
    let tint: Color
    var ghost = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7).fill(ghost ? .clear : Color(white: 0.96))
            if ghost {
                RoundedRectangle(cornerRadius: 7).strokeBorder(style: StrokeStyle(lineWidth: 2.5, dash: [8, 6])).foregroundStyle(.white.opacity(0.6))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 8, height: 8) }
                    }
                    RoundedRectangle(cornerRadius: 4).fill(tint.opacity(0.85))
                    RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.8)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.8)).frame(width: 60, height: 6)
                }
                .padding(9)
            }
        }
        .shadow(color: .black.opacity(ghost ? 0 : 0.35), radius: 8, y: 4)
    }
}

private struct KeyChip: View {
    let text: String
    var tint: Color = .accentColor
    var body: some View {
        Text(text).font(.system(size: 20, weight: .semibold, design: .rounded))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(tint.opacity(0.85)))
    }
}

/// "Windows come to you": ⌘Tab to Chrome pulls its window from the other display to the cursor.
struct PromoSummonArt: View {
    var body: some View {
        PromoCard {
            VStack(spacing: 30) {
                HStack(spacing: 12) {
                    KeyChip(text: "⌘Tab → Google Chrome")
                    Text("window was on the other display").font(.system(size: 19)).foregroundStyle(.secondary)
                }
                HStack(alignment: .center, spacing: 34) {
                    MiniDisplay(name: "MacBook", width: 380,
                                windows: [(CGRect(x: 0.12, y: 0.2, width: 0.62, height: 0.62), .blue, true)])
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.right").font(.system(size: 46, weight: .bold)).foregroundStyle(Color.accentColor)
                        Text("Focal").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    MiniDisplay(name: "External display — you are here", width: 480,
                                windows: [(CGRect(x: 0.18, y: 0.16, width: 0.6, height: 0.62), .blue, false)],
                                cursor: CGPoint(x: 0.7, y: 0.66))
                }
                HStack(spacing: 22) {
                    ForEach(["Minimized", "Other display", "Other Space", "Off-screen", "No window"], id: \.self) { t in
                        Label(t, systemImage: "checkmark.circle.fill").font(.system(size: 17, weight: .medium))
                            .symbolRenderingMode(.multicolor)
                    }
                }
            }
        }
    }
}

/// Back/forward through window sets.
struct PromoSetsArt: View {
    private struct SetCard: View {
        let title: String
        let windows: [(CGRect, Color)]
        let current: Bool
        var body: some View {
            VStack(spacing: 12) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.18, green: 0.22, blue: 0.36))
                    GeometryReader { g in
                        ForEach(Array(windows.enumerated()), id: \.offset) { _, w in
                            MiniWindow(tint: w.1)
                                .frame(width: g.size.width * w.0.width, height: g.size.height * w.0.height)
                                .offset(x: g.size.width * w.0.minX, y: g.size.height * w.0.minY)
                        }
                    }
                    .padding(8)
                }
                .frame(width: 290, height: 180)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(current ? Color.accentColor : .white.opacity(0.35), lineWidth: current ? 4 : 2))
                Text(title).font(.system(size: 18, weight: .semibold))
                Text(current ? "now" : " ").font(.system(size: 14, weight: .medium)).foregroundStyle(Color.accentColor)
            }
        }
    }

    var body: some View {
        PromoCard {
            VStack(spacing: 26) {
                HStack(alignment: .top, spacing: 22) {
                    SetCard(title: "Mail + Calendar", windows: [(CGRect(x: 0, y: 0, width: 0.5, height: 1), .blue), (CGRect(x: 0.5, y: 0, width: 0.5, height: 1), .red)], current: false)
                    SetCard(title: "Chrome + series", windows: [(CGRect(x: 0, y: 0, width: 0.6, height: 1), .orange), (CGRect(x: 0.55, y: 0.25, width: 0.45, height: 0.6), .black)], current: false)
                    SetCard(title: "Telegram", windows: [(CGRect(x: 0.1, y: 0.05, width: 0.8, height: 0.9), .cyan)], current: true)
                }
                HStack(spacing: 40) {
                    HStack(spacing: 10) { KeyChip(text: "⌥`"); Text("back, one set at a time").font(.system(size: 18)) }
                    HStack(spacing: 10) { KeyChip(text: "⌥⇧`", tint: .purple); Text("forward again").font(.system(size: 18)) }
                }
                Text("Every window returns to its place — even ones Focal pulled to another display.")
                    .font(.system(size: 17)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Windows-style snapping.
struct PromoSnapArt: View {
    private func region(_ label: String, _ r: CGRect, _ tint: Color) -> some View {
        GeometryReader { g in
            RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.45))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint, lineWidth: 2.5))
                .overlay(Text(label).font(.system(size: 19, weight: .semibold, design: .rounded)).multilineTextAlignment(.center))
                .frame(width: g.size.width * r.width - 10, height: g.size.height * r.height - 10)
                .offset(x: g.size.width * r.minX + 5, y: g.size.height * r.minY + 5)
        }
    }

    var body: some View {
        PromoCard {
            VStack(spacing: 24) {
                HStack(alignment: .center, spacing: 34) {
                    VStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35))
                            region("⌃⌥←\nleft half", CGRect(x: 0, y: 0, width: 0.5, height: 1), .blue)
                            region("⌃⌥↑\ntop quarter", CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5), .purple)
                            region("⌃⌥↓\nbottom quarter", CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5), .teal)
                        }
                        .frame(width: 440, height: 270)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.55), lineWidth: 3))
                        Text("MacBook").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 10) {
                        KeyChip(text: "⌃⌥⇧ ← →")
                        Image(systemName: "arrow.left.arrow.right").font(.system(size: 40, weight: .bold))
                        Text("other display,\nmaximized").font(.system(size: 16)).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35))
                            region("⌃⌥↑\nfull screen", CGRect(x: 0, y: 0, width: 1, height: 1), .green)
                        }
                        .frame(width: 440, height: 270)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.55), lineWidth: 3))
                        Text("External display").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 18) {
                    ForEach([("⌃⌥↓", "restore / minimize"), ("⌃⌥F", "native full screen"), ("⌃⌥C", "center")], id: \.0) { k, t in
                        HStack(spacing: 8) { KeyChip(text: k, tint: .gray); Text(t).font(.system(size: 17)) }
                    }
                }
            }
        }
    }
}
