# Rendering Only What Changed

Skip the snapshots a change can't affect. Experimental.

## Overview

`swiftbook test --changed` renders only the snapshots that something since the last run may have
affected, and skips the rest, which passed last time. In a package with hundreds of
stories, an edit to one view usually renders a handful, and a change that touches no code your
stories run renders none.

```
$ swiftbook test --device mac --changed
mac: rendering 16 of 514 snapshots; the other 498 passed last time, and nothing they depend on changed. (--changed is experimental.)
  16 because MyAppUI/AccountList.swift changed
mac: 16 snapshots on 6 renderer processes: 16 matched, 0 new, 0 re-recorded, 0 failed.
```

> Important: `--changed` is experimental, and some kinds of change are invisible to it. Use it
> while you work, and keep running every snapshot somewhere, such as in CI.

### How it decides

With `--changed`, SwiftBook builds a second renderer, in `.build/swiftbook/changed`, with counters
the compiler adds to every function. Each render records which of your code it ran, by source
file, using [SwiftImpact](https://github.com/brandonbloom/SwiftImpact). On the next run, a
snapshot renders again if:
- **code it ran compiles differently.** That includes files you didn't edit, when the compiler
  rebuilt them differently because of a change elsewhere, and the file declaring its `#Preview`.
- **a shared context it uses changed.** See `PreviewModifier.makeSharedContext()`.
- **it failed last time.**
- **its reference changed,** such as after `git pull`.
- **it has no past result,** because it's new or it's the first run.
- **the run's settings changed:** a rebuilt `swiftbook`, another OS version, another capture method,
  or other tolerances.

Each run says how many snapshots it renders, and the commonest reasons.

### What it can't see

Selection compares the code a snapshot runs. A snapshot can change for reasons it doesn't see:
- **Resources:** asset catalogs, bundled files, fonts, and localizations.
- **Code without counters:** C and Objective-C, prebuilt binaries, and code that macros generate
  in files other than the story's, such as `@Observable` accessors.
- **What the runtime finds by name:** Objective-C selectors, `NSClassFromString`, and reflection.
- **A protocol witness added in another file,** when the snapshot runs none of the conforming
  type's own code.

SwiftImpact's documentation lists these in full.

### What it costs

The first run with `--changed` builds the second renderer, which takes about as long as building
your package, and renders every snapshot. After that, its builds are incremental. Its past results
live with the build, so clearing `.build` clears them, and the next run renders everything.

`--changed` applies to `swiftbook test` only, not to `#SwiftBookTests` under `swift test`.

## See Also

- <doc:ContinuousIntegration>
- <doc:CommandLine>

<!-- sources: Sources/SwiftBookCLI/ChangedSnapshots.swift Sources/SwiftBookCLI/DeviceRun.swift Sources/SwiftBookCore/Renderer/RenderRecording+Probe.swift Sources/SwiftBookCore/Adapter/PreviewModifiers.swift -->
<!-- checked: edb15f9 -->
