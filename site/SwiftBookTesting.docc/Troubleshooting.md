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

<!-- TODO(site): sample `swiftbook doctor` output. -->

### Mac renders differ from what I see on screen

Without Screen Recording permission, or with the screen locked, SwiftBook falls back to emulated
capture, which differs slightly around vibrancy and Liquid Glass. Grant permission to the app
running the tests, or record and verify with `SWIFTBOOK_CAPTURE=emulated` everywhere. See
<doc:Capture>.

### A story fails as "still changing"

Something in the preview animates, polls, or loads asynchronously. See
<doc:PreviewsThatSnapshotWell>.

### A reference fails with a few faint pixels

Materials such as Liquid Glass can settle slightly differently from run to run. Small amounts of
such noise already match; for more, adjust tolerance. See <doc:UnderstandingFailures>.

### A bundle "has a top-level Resources directory"

iOS and tvOS bundles are flat, so a resource bundle with a top-level `Resources` directory, as
from `.copy("Resources")`, can't go in the renderer app; codesign would reject it as "bundle
format unrecognized". Rename the directory your package copies as a resource to something else.

## See Also

- <doc:CommandLine>
