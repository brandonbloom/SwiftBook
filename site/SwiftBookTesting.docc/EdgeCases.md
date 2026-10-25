# The Edge Cases SwiftBook Handles

What it takes to render the same pixels every time, and what SwiftBook does about each problem.

## Overview

A snapshot test is only worth having if it fails when your view changes, and only then. Apple's
frameworks weren't built for that. What a view looks like depends on which process draws it,
what the window server composites, whether a mouse is plugged in, the time zone, the machine's
load, and the state of a simulator. Each item below made renders wrong, flaky, slow, or stuck
until SwiftBook handled it. Most were found on real projects, and the hardest have fixture
stories that fail if they come back.

You don't need any of this to use SwiftBook. It's here so you know what's covered.

### What the window server draws

- **Vibrancy and Liquid Glass aren't drawn by your app.** The window server composites sidebar
  vibrancy, materials, and glass. Drawn into an image, a selected sidebar row came out as a black
  rectangle, and vibrant text came out black. SwiftBook captures through the window server with
  ScreenCaptureKit when it's allowed. Otherwise it emulates vibrancy: it reads each vibrant
  layer's color matrix and applies it to the captured backdrop. Emulation differs from the
  window server in under 1% of pixels in light mode. See <doc:Capture>.
- **Drawing a view into an image changes it.** AppKit's `cacheDisplay` tells SwiftUI it's
  caching, and SwiftUI swaps Liquid Glass controls for a flat white fallback until the window
  next displays. SwiftBook draws with the method `cacheDisplay` wraps, which leaves the glass
  alone. That cut one adopter's search-field difference from the window server roughly in half.
- **Layers move mid-capture.** Drawing into a bitmap can replace a view's layers, and a detached
  layer drawn alone lands at the origin: a search field's fill appeared as a stray capsule.
  SwiftBook renders vibrant layers before capturing their backdrop.
- **The window server shows content late.** It lists a new window, and draws its latest content,
  a few frames after the app does. Window-server captures wait for the window to be listed and
  settle on three identical captures, not two.
- **ScreenCaptureKit can wait forever,** apparently while macOS asks whether to allow screen
  recording. Each call gets 10 seconds, then fails with a message that names the prompt.
- **A locked screen captures nothing,** and captures need Screen Recording permission. SwiftBook
  checks both and falls back to emulated capture, and each reference records how it was
  captured, so a mismatch between methods is reported as such rather than as a change.

### Your Mac leaking into renders

- **The pointer.** AppKit checks the real pointer against a window's frame even when the window
  isn't on screen, and draws hover states. An adopter's snapshots flaked with hover highlights
  whenever the pointer was near the Dock. Render windows sit 100,000 points off every screen,
  ignore the mouse, and capture without the cursor.
- **Scroll bars.** With "Show scroll bars: Automatically", macOS switches to legacy scrollers
  whenever it sees a mouse, including a keyboard that reports itself as one, as on a docked Mac.
  They take about 15 points from every list, table, and scroll view, which failed 118 of one
  adopter's 520 Mac snapshots. Every render process pins overlay scrollers before AppKit reads
  the setting.
- **The active app.** The rendering process is never the frontmost app, so windows always draw
  in their inactive style, and every Mac that records or checks a reference agrees.
- **Displays.** Captures draw at the pinned scale whatever the screens' backing scale, convert to
  8-bit sRGB, and snap to whole pixels, so references don't depend on your monitors.
- **Time zones.** `Date.formatted()` reads the process's time zone, not SwiftUI's environment,
  and setting `NSTimeZone.default` isn't enough. SwiftBook sets the process's zone for each
  render and never runs two renders that need different ones at once. Locale, calendar, Dynamic
  Type, layout direction, and animations are pinned too; see <doc:PreviewsThatSnapshotWell>.
- **Animations.** Core Animation runs animations outside the app, so turning them off in UIKit
  and SwiftUI isn't enough: an indeterminate progress view kept spinning. SwiftBook stops the
  window's layer clock before your view appears.

### Staying out of your way

- **Render windows on screen.** Window-server capture needs the window on screen. SwiftBook puts
  it below the desktop, where the wallpaper hides it, and keeps it out of Mission Control and
  window cycling, so nothing flickers and focus isn't taken. Captures are identical.
- **Dock icons.** A command-line program started from an app registers with macOS as that app,
  icon and all, and the Dock can keep the tile after the program exits. SwiftBook's renderer runs
  as an app of its own that never appears in the Dock, and renders in your test process switch
  it to an accessory app first.
- **Orphans.** A renderer whose parent dies notices within a second and exits, instead of leaving
  a window or a hung capture behind.

### Knowing when a render is done

- **Views settle in stages.** A render is captured once consecutive captures match. A `PDFView`
  draws a blurry page, holds still, then draws sharp tiles, so one in five renders caught the
  blur. Stories can ask for a longer hold, and the hold stretches with the machine's load.
- **Heavy load.** On CI Macs with load averages over 100, a single capture could take the whole
  settle window. A render always gets at least five captures before it can fail.
- **Blank first frames.** A capture that's all one color must hold for a second before it
  counts, so a sheet or inspector that hasn't drawn yet isn't recorded as empty.
- **Liquid Glass flickers in the render server.** On iOS, glass is composited outside the app in
  a few discrete states: dithered or banded, a selected tab's lens toggling between two
  rasterizations every 80–250 ms forever, a shape switching drawing paths after a moment. No
  system setting or settle time makes it deterministic; one adopter story failed 5 runs in 20.
  SwiftBook finds the glass in each render and ignores differences inside it that vanish when
  averaged, while any real change, in or behind the glass, still fails. Across about 1,000
  renders this covered all of the noise. See <doc:UnderstandingFailures>.
- **SwiftUI sometimes hangs.** Under heavy load it can spin while building a List header, about
  one run in five. Each renderer is a process of its own, so SwiftBook samples a hung one for
  the record, restarts it, and retries the story.

### Simulators

- **iOS draws only in a real app.** From a test process, `drawHierarchy` returns blank images,
  other methods miss materials or show placeholders, and starting an app from a test hangs.
  SwiftBook builds a minimal app from your package for each simulator platform.
- **The SDK version decides how UIKit draws.** SwiftPM stamps apps with the deployment target as
  their SDK version, so List headers drew in iOS 18's style. SwiftBook stamps the real SDK.
- **A simulator runs one app at a time** and suspends the rest, so parallel runs suspended each
  other's renderers until they timed out. Each run leases simulators from a pool of SwiftBook's
  own, sized to the Mac's memory and cores, and keeps extra ones warm for five minutes so a
  run doesn't pay 15 seconds for a cold boot.
- **System services crash-loop.** A simulator's PosterBoard crashed 25 times in two minutes on
  an adopter's Mac. A run erases a simulator before using it if a service crashed over and over
  in the last hour, and `swiftbook doctor` reports it.
- **Process IDs are reused.** A simulator app isn't SwiftBook's child, so its process ID can pass
  to an unrelated process once it exits. SwiftBook checks a process's start time before it
  stops one.

### Reading your previews

- **Xcode's previews have no public API** to list or read them. SwiftBook finds every `#Preview`
  and `PreviewProvider` in your code by scanning the binary, and reads each through one small,
  checked adapter that names the OS and framework versions if a layout ever changes, rather than
  rendering something different from Xcode.
- **Preview arguments, modifiers, and debug builds** each needed care: `#Preview(arguments:)`
  crashed when called the obvious way, `PreviewModifier` content can only be built by SwiftUI's
  own internal type, and debug builds wrap views in a type that crashed Xcode's own preview agent
  on legacy previews. The test fixtures cover each form.
- **Your app's accent color.** Previews render outside your app, so controls came out blue where
  the app is green. Asset-catalog colors resolve against the current appearance rather than
  SwiftUI's, so SwiftBook resolves your tint for each appearance explicitly. See
  <doc:MatchingYourAppsTint>.

### References in git

- **Case-insensitive disks.** Stories named `Dark` and `dark`, or `Card` and `Card.`, would
  overwrite each other's references on APFS. SwiftBook numbers names that collide, and keeps
  names valid on macOS, Windows, and Git.
- **Unpulled Git LFS files.** A fresh clone or worktree had 157 failures and no explanation.
  SwiftBook recognizes LFS pointers everywhere it reads a reference, never records over one,
  and stops with a count and the fix.
- **Upgrades that change nothing.** An OS or SwiftBook upgrade changed every reference's bytes
  but not its pixels: about 220 MB for one adopter. SwiftBook compares pixels, and leaves
  references whose pixels match alone.
- **Machine-dependent diffs.** The GPU can compute slightly different results on different
  Macs, so comparisons run on the CPU, in sRGB.

### CI machines and the toolchain

- **Hosted runners have three cores,** and Swift's cooperative thread pool is as wide. Code that
  blocks a thread while waiting for other async work deadlocks there, though it passes on a
  many-core Mac. SwiftBook's own CI runs on such a runner.
- **`Process.waitUntilExit` can hang** off the main thread, so live reload stopped after an edit.
  SwiftBook polls with deadlines instead.
- **Printing from your code.** Renderers talk to SwiftBook over standard output, so anything your
  code prints goes to standard error instead of corrupting the protocol, and a renderer that
  crashes mid-write can't take SwiftBook down with it.
- **Debug builds are slow over pixels.** A loop over a screen-sized image takes seconds
  unoptimized, enough to look like a hang. Pixel work uses `memcmp`, `memset`, and C.
- **SwiftPM in worktrees.** A path dependency takes its identity from its directory's name, and
  edited dependencies drop out of `Package.resolved`. SwiftBook's renderer finds your SwiftBook
  dependency either way and builds against the same versions you do.

### What isn't handled

Some things are better fixed in your previews: `Date.now` and random values change between
runs, and Mac stories render as a content view, without window chrome or toolbars. See
<doc:PreviewsThatSnapshotWell>.

## See Also

- <doc:Capture>
- <doc:PreviewsThatSnapshotWell>
- <doc:Troubleshooting>

<!-- sources: Sources/SwiftBookCore/Rendering Sources/SwiftBookCore/Renderer Sources/SwiftBookCore/Adapter Sources/SwiftBookCore/Diff Sources/SwiftBookCore/Storage Sources/SwiftBookRenderer -->
<!-- checked: HEAD -->
