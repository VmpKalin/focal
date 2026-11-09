# Focal launch kit

Positioning, copy for each channel, the image set, and what must happen before a public release.

## Positioning

**One-liner:** Windows that come to you. A Mac window switcher that puts every window on the screen you are looking at.

**Short (140 chars):** Focal fixes ⌘Tab on Mac: windows in the order you used them, pulled to your screen, plus back/forward for whole sets of windows.

**Who it's for**
- Anyone with two displays who has pressed ⌘Tab and seen nothing happen.
- People who live in full screen and several desktops, and lose windows there.
- Switchers from Windows who miss Alt+Tab per window and Win+arrow snapping.

**Why not AltTab / Rectangle / Witch?**

| | Focal | AltTab | Rectangle | Witch |
| --- | --- | --- | --- | --- |
| Per-window ⌘Tab with previews | ✅ | ✅ | ❌ | ✅ |
| Pulls the window to the display you are on | ✅ | ❌ | ❌ | ❌ |
| Fixes ⌘Tab to minimized / windowless apps automatically | ✅ | ❌ | ❌ | ❌ |
| Back / forward through sets of windows | ✅ | ❌ | ❌ | ❌ |
| Saved layouts that relaunch apps | ✅ | ❌ | ❌ | ❌ |
| Windows-style snapping and display throw | ✅ | ❌ | ✅ | ❌ |
| Checks the macOS settings that lose windows | ✅ | ❌ | ❌ | ❌ |
| Free, local, no account | ✅ | ✅ | ✅ | ❌ (paid) |

Check the competitor columns before publishing. They change often.

## Image set

All images are in `docs/promo` (2880×1800, 16:10, fits Product Hunt, X and the Mac App Store):

1. `01-hero.jpg`: Windows that come to you.
2. `02-command-tab.jpg`: The window you just left is next.
3. `03-every-window.jpg`: Full screen, other desktops, all in one list.
4. `04-come-to-you.jpg`: Right screen, every time.
5. `05-back-forward.jpg`: ⌘Tab for whole sets of windows.
6. `06-snap.jpg`: Win + arrows, on a Mac.
7. `07-fixes-macos.jpg`: Finds the settings that lose windows.

Regenerate them with `focal://render-docs` and `scripts/make-promo.swift` (see README).

**Still missing (record by hand):** a 20 to 30 second screen recording with two displays. ⌘Tab to an app whose window is on the other screen and watch it arrive, then ⌥\` back to the previous pair of windows. That moment sells Focal better than any still.

## Copy per channel

### Product Hunt

**Name:** Focal
**Tagline (60):** Windows that come to you — a smarter ⌘Tab for Mac
**Topics:** Mac, Productivity, Developer Tools

**Description:**
> Focal is a menu bar window manager that fixes the Mac's app switching. ⌘Tab lists windows, not apps, in the order you used them, with live previews and search. When you switch to an app, its window lands on the screen you are looking at, even if it was minimized, on the other display, on another desktop or closed. ⌥` brings back the whole set of windows you were just using, and ⌃⌥ arrows snap windows like on Windows. Everything stays on your Mac.

**First comment (maker):**
> Hi PH 👋 I built Focal after one too many ⌘Tabs to Chrome that did nothing, because its window was on my other monitor or in full screen on another desktop. Focal makes every switch land where I am, lists every window (even the ones App Exposé says don't exist), and lets me jump back to "Chrome + the series I was watching" in one keystroke. I'd love to hear what macOS window habit annoys you most. That's what goes into the next version.

### X / Threads

> ⌘Tab to Chrome. Nothing happens. The window is on your other monitor. Or minimized. Or in full screen on another desktop.
>
> I built Focal so the window always comes to you. Plus a per-window ⌘Tab, back/forward for window sets and Win+arrow snapping. 🧵

### Reddit (r/macapps)

**Title:** I made Focal: ⌘Tab that brings the window to the screen you are on, and back/forward for sets of windows

## Before a public release

- [ ] English (and other) localization: the UI is Ukrainian only today.
- [ ] Developer ID signing and notarization, DMG.
- [ ] Decide on the ⌘Tab takeover default: it uses a private API, so it may not be allowed in the Mac App Store; distribute directly.
- [ ] A short screen recording (see above).
- [ ] Make the repository public, or publish a landing page.
