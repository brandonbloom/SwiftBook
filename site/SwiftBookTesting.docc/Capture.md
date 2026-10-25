# Capturing Mac Renders

Choose between exact window-server capture and portable emulated capture.

## Overview

Some of what you see on a Mac, such as sidebar vibrancy and Liquid Glass, is drawn by the window
server rather than by your app. SwiftBook captures Mac renders one of two ways, and each
reference records which.

### Window server

The default when allowed. The window is captured with ScreenCaptureKit, exactly as it appears on
screen. It sits below the desktop, out of sight and out of Mission Control, so nothing flashes
while you work. This needs:

- Screen Recording permission for the app running the tests: Terminal, Xcode, or your agent's
  host app.
- An unlocked screen.
- A canvas that fits on the main screen.

Otherwise SwiftBook falls back to emulated capture. It takes about 0.65 s per image. If
ScreenCaptureKit doesn't answer within 10 s, as while macOS asks whether to allow screen
recording, the render fails rather than waiting.

### Emulated

The fallback, and what CI uses. The view draws itself offscreen, and SwiftBook composites the
vibrancy that only the window server would apply. It's close to the window server but not exact:
Liquid Glass edges, text inside glass, and some sidebar materials differ slightly. It takes
about 0.1 s per image.

### Choosing

Set `SWIFTBOOK_CAPTURE` to `windowServer` or `emulated`. References must be recorded with the
same capture method that verifies them, so a team whose CI runs emulated should record emulated
too.

### Rendering several at once

Most of a render is drawing on the main thread, so one process gains little from rendering
several stories at once. `swiftbook test --device mac` instead renders in several renderer
processes, each with a main thread of its own: by default half the Mac's performance cores'
worth, starting more while enough stories remain to repay it. `--jobs` sets the most. Their
images are the same as `swift test`'s.

Under `swift test`, emulated captures still render up to four stories at a time, each in a
window of its own, which helps a little; `SWIFTBOOK_MAC_RENDERS` sets how many. A story whose
environment sets another time zone renders while no other does, because `Date.formatted()` reads
the process's time zone.

Window-server captures render one at a time, in one process, unless `--jobs` or
`SWIFTBOOK_MAC_RENDERS` says otherwise: captures of several windows on screen at once haven't
been checked against captures made alone.

### Inactive windows

Windows render in their inactive style, as when another app is in front. For example, sidebar
selections are gray rather than the accent color, because the test process is never the active
app.

### Overlay scrollers

Lists, tables, and scroll views render with overlay scrollers, whatever System Settings says.
With "Show scroll bars: Automatically", macOS switches to legacy scrollers whenever it thinks a
mouse is attached, as when a Mac is docked, and they take about 15 points from every scroll view.
SwiftBook pins overlay scrollers in each process that renders, before the first render. In
`swift test`, code that reads the scroller style before SwiftBook renders, such as a test that
makes a scroll view first, fixes the style for that process.

## See Also

- <doc:ContinuousIntegration>
- <doc:Troubleshooting>

<!-- sources: Sources/SwiftBookCore/Rendering/MacRenderer.swift Sources/SwiftBookCore/Rendering/RenderGate.swift Sources/SwiftBookCore/Rendering/ScrollerStyle.swift Sources/SwiftBookCore/Rendering/Vibrancy.swift Sources/SwiftBookCore/Rendering/WindowServerCapture.swift -->
<!-- checked: 7f8c5da -->
