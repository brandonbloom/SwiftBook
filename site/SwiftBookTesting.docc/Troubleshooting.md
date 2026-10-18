# Troubleshooting

Find out what's wrong with `swiftbook doctor`.

## Overview

```sh
swift run swiftbook doctor
```

It checks:

- macOS, Xcode, Git, and Git LFS.
- The LFS rule for references, and references that are unpulled LFS pointers.
- Screen Recording permission, for window-server capture.
- Simulator runtimes for iPhone, iPad, and Apple TV.
- That every story can be read. This builds the renderer; `--quick` skips it.

It exits with status 2 if any check fails. `--json` writes the results for scripts.

<!-- transcript: doctor -->
```
$ swift run swiftbook doctor
✓ macOS: 27.2
✓ Xcode: Xcode 27.0, Build version 27A266a
✓ Git: git version 2.51.2
✓ Git LFS: git-lfs/3.8.0 (GitHub; darwin arm64; go 1.27.1)
✓ LFS rule: References in Snapshots go to Git LFS.
✓ References: 48 in Snapshots.
✓ Capture: Screen Recording is allowed here, so macOS snapshots capture through the window server.
✓ Simulators: iOS and tvOS runtimes installed.
✓ Discovery: 6 stories discovered, and every one can be read.
```
<!-- /transcript -->

### Mac renders differ from what I see on screen

Without Screen Recording permission, or with the screen locked, SwiftBook falls back to emulated
capture, which differs slightly around vibrancy and Liquid Glass. Grant permission to the app
running the tests, or record and verify with `SWIFTBOOK_CAPTURE=emulated` everywhere. See
<doc:Capture>.

### A story fails as "still changing"

Something in the preview animates, polls, or loads asynchronously. See
<doc:PreviewsThatSnapshotWell>.

### A story hangs or crashes the renderer

In the viewer and on iPhone, iPad, and Apple TV, stories render in a separate renderer process;
under `swift test`, they render in the test process. A renderer that takes longer than 30 seconds
is stopped, and SwiftBook samples its threads first: the error names the sample file, which shows
where the renderer was stuck. `swiftbook test` restarts the renderer and retries the story once,
and its summary lists the stories that caused restarts.

### A reference fails with a few faint pixels

Materials such as Liquid Glass can settle slightly differently from run to run. Small amounts of
such noise already match; for more, adjust tolerance. See <doc:UnderstandingFailures>.
`swiftbook flakes` renders each story several times to show which ones vary; see
<doc:PreviewsThatSnapshotWell>.

### A bundle "has a top-level Resources directory"

iOS and tvOS bundles are flat, so a resource bundle with a top-level `Resources` directory, as
from `.copy("Resources")`, can't go in the renderer app; codesign would reject it as "bundle
format unrecognized". Rename the directory your package copies as a resource to something else.

## See Also

- <doc:CommandLine>

<!-- sources: Sources/SwiftBookCLI/DoctorCommand.swift Sources/SwiftBookCore/Renderer/RendererHost.swift Sources/SwiftBookCore/Renderer/RendererProcess.swift Sources/SwiftBookCore/Renderer/RestartingRenderer.swift Sources/SwiftBookCLI/DeviceRun.swift Sources/SwiftBookCLI/FlakesCommand.swift -->
<!-- checked: 2bc9529 -->
