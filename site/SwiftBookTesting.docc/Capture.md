# Capturing Mac Renders

Choose between exact window-server capture and portable emulated capture.

## Overview

Some of what you see on a Mac, such as sidebar vibrancy and Liquid Glass, is drawn by the window
server rather than by your app. SwiftBook captures Mac renders one of two ways, and each
reference records which.

### Window server

The default when allowed. The window is captured with ScreenCaptureKit, exactly as it appears on
screen. This needs:

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

### Inactive windows

Windows render in their inactive style, as when another app is in front. For example, sidebar
selections are gray rather than the accent color, because the test process is never the active
app.

## See Also

- <doc:ContinuousIntegration>
- <doc:Troubleshooting>

<!-- sources: Sources/SwiftBookCore/Rendering/MacRenderer.swift Sources/SwiftBookCore/Rendering/Vibrancy.swift Sources/SwiftBookCore/Rendering/WindowServerCapture.swift -->
<!-- checked: 901dbe2 -->
