# SwiftBook vision

> **Status: draft.** Written collaboratively. Sections marked *(proposed)* are recommendations awaiting agreement; everything else reflects decisions already made. Background and prior art are in [research.md](research.md).

## Summary

SwiftBook is a story viewer and visual testing tool for SwiftUI.

- **Stories are your previews.** Every `#Preview` in your code is a story. There is nothing extra to write, register, or configure.
- **One app to leave open.** A macOS app shows every story across platforms and appearances. It shows how each story differs from any point in git history, and updates live as the code compiles.
- **The same stories are your tests.** The same stories run as snapshot tests under `swift test` and `xcodebuild`. Reference images are committed to git (LFS-friendly) and diffed locally, with no cloud service.

## Goals

1. **Convention over configuration.** Adding SwiftBook to a package needs a dependency and a few lines of test code. Defaults cover layout, storage, variants, and naming.
2. **Previews are the only story format.** Any `#Preview` that works in Xcode's canvas works in SwiftBook. The preview needs no wrappers or registries, and its name isn't repeated anywhere else.
3. **Variants are first class**, light and dark above all. Platform is a variant too, so iOS and macOS renderings of the same story can sit side by side.
4. **A live, always-open macOS viewer.** It is fast and smooth. It picks up new code as soon as it compiles, and build errors, crashes, and hangs in user code never take it down or block it.
5. **History-aware review.** Every story can be compared against uncommitted changes, the last commit, the branch's merge-base, or any revision.
6. **Built-in visual diffing.** Perceptual diffs, a full set of comparison modes, and readable test failures.
7. **Git-native storage.** Reference images live in the repo and work with Git LFS (including GitHub's LFS). Git is the integration point; GitHub-specific features aren't a priority.
8. **A CI-friendly CLI and build integration.** Deterministic rendering, clear exit codes, and output that machines can read.
9. **Buildable from source.** No prebuilt binaries anywhere in the dependency graph, and only a few pinnable dependencies.

## Non-goals for the first version

- A richer story layer: args, controls, decorators, or a `*.stories.swift` format. It may come later.
- GitHub-specific integration beyond LFS: PR comments, check runs, hosted reports.
- Cloud or hosted baseline storage.
- More than one discovery mechanism.
- Live-updating viewers on iOS or tvOS. Those builds are static (see [Viewer](#viewer)).
- watchOS and visionOS.

## Concepts

| Term | Meaning |
|---|---|
| **Story** | One `#Preview` (or `PreviewProvider` variant), identified by module, source file, and display name. |
| **Dimension** | An axis along which a story can be rendered differently: platform, device (size class), color scheme, dynamic type size, layout direction / locale, and revision. |
| **Variant** | One choice of value for every dimension, for example `ios · dark · large · ltr`. |
| **Snapshot** | One story rendered as one variant, as a PNG. |
| **Reference** | A snapshot committed to the repo, holding the expected appearance. |
| **Basis** | The git revision (or the working tree) that references are compared against. |

Revision is a dimension like any other. "Compare this story to `main`" works the same way as "compare light to dark".

## User experience

### macOS viewer

The primary interface is a macOS app that you leave open while you work.

**Sidebar**
- Lists every story, grouped by module, then file, then story.
- Searchable.
- Filters by *change status* against the chosen basis:
  - Uncommitted changes (working tree vs `HEAD`).
  - The most recent commit (`HEAD` vs `HEAD~`).
  - This branch (working tree vs merge-base with the default branch).
  - Any revision or range.
- The default filter is uncommitted changes when the working tree is dirty, and the most recent commit when it's clean.
- Each story has a status badge: unchanged, changed, new, removed, failed to render, or build error.

**Toolbar.** Three independent controls:

- **(A) Comparison mode:**
  - single
  - 2-up
  - grid (N-up)
  - later: swipe, onion skin, blink, and diff highlight
- **(B) Comparison dimension.** Which dimension the comparison spreads across: platform, color scheme, dynamic type, locale/direction, or revision.
- **(C) Dimension values.** One picker per dimension, always available. With comparison off, the color scheme picker toggles light and dark. With comparison on and the dimension set to color scheme, you see light and dark 2-up. The other pickers still apply to every cell.

**Canvas**
- Shows one story or several selected stories, each laid out per the toolbar.
- Zoom and pan are synchronized across all cells, because small diffs are invisible otherwise.
- Diff cells report the changed-pixel ratio and the maximum perceptual difference.

**Live update**
- The viewer watches the source tree.
- When a build succeeds, new renders replace old ones without a flash and without losing your scroll, zoom, or selection.
- When a build fails, the last good renders stay on screen under a build-error banner with the diagnostics.
- When a single story crashes or hangs, only that cell shows the error.

### iOS and tvOS viewer

A static, in-process build of the same viewer UI for running on a device or simulator, to play with stories interactively in their real environment.

- It has none of live reload, out-of-process isolation, or history.
- It shows the stories compiled into it, with the dimension pickers (C) and live comparison across dimensions the device can render (A, B).

### Opting in and configuring

Swift has no way to enable this with zero code, so a test target opts in with **a single declaration**. It is the only project-level configuration point:

```swift
import SwiftBookTesting

#SwiftBookTests                                       // defaults: light + dark
#SwiftBookTests(variants: .colorScheme × .dynamicType(.large, .accessibility3))
```

- The macro expands to an ordinary Swift Testing parameterized test over every discovered story. It runs the **macOS** snapshots under `swift test` or `xcodebuild`.
- **iOS and tvOS snapshots run through `swiftbook test`**, using the same generated renderer app as the viewer. Package test targets on those platforms have no host app, and without one, test rendering loses fidelity ([spike](spikes/ios-renderer.md)). As a result, CI references always match what the viewer shows. Those snapshots don't appear in Xcode's test navigator.
- Its arguments set the package-wide defaults: which variants are **recorded** and the diff thresholds.
- Nothing else is read: no config files and no environment-specific setup. The CLI and viewer find settings by looking for this declaration.
- The viewer can render any variant on demand, whatever is recorded.

**Story metadata** goes on the preview itself through SwiftBook modifiers. Xcode's canvas ignores them, and SwiftBook reads them through SwiftUI preferences during rendering:

```swift
#Preview("AccountList (empty)", traits: .fixedLayout(width: 420, height: 640)) {
  AccountList(…)
    .swiftBook(.variants(.adding(.rightToLeft)), .diffTolerance(0.02))
}
```

Decided about metadata:

- The vocabulary is general, not limited to variants. It will grow to cover diffing, rendering, inclusion, and organization.
- Metadata can apply to the whole story or to one subview. For example, a masked region or a readiness signal attaches to the view it describes.
- Metadata must not change how the preview looks in Xcode.

The specific options and how they combine are undecided until the basics work. Ideas are in [ideas/story-metadata.md](ideas/story-metadata.md).

### Tests

- Each story appears as its own test in Xcode and in `swift test` output.
- Each variant the platform renders is compared on its own. A failure attaches the reference, the actual image, and the diff, and its message names the file to look at.
- Recording is controlled by an environment variable or a CLI flag (`missing`, `changed`, `all`, `none`). It never needs a source edit.
- **Each platform owns its references.** Verifying on macOS checks only `macos.*` references. A missing reference for a platform that wasn't run is not a failure.

### CLI

`swiftbook` is a single command-line tool, built from source.

| Command | Purpose |
|---|---|
| `swiftbook view` | Build and launch the macOS viewer for the current package. |
| `swiftbook test [--platform …] [--record …]` | Run snapshot tests on each platform: `swift test` for macOS, and the generated renderer app in a pinned simulator for iOS/tvOS. With no `--platform`, it runs every platform that already has references, so CI coverage follows what's committed. |
| `swiftbook diff [<basis>]` | Summarize changed snapshots against a basis. Can also open the viewer on them. |
| `swiftbook prune` | Delete references whose story or variant no longer exists. |
| `swiftbook init` | Write `.gitattributes` LFS rules and the git difftool configuration. |
| `swiftbook doctor` | Check the toolchain, simulators, LFS, and how well discovery and its adapter are working. |

Exit codes tell "snapshots changed" apart from "something broke". Machine-readable output (JSON, JUnit) sits alongside the human-readable output.

## Architecture

### Process model

The macOS viewer never links user code. All user code runs in separate **renderer** processes that the viewer manages.

```
┌──────────────────────────── macOS ────────────────────────────┐
│                                                               │
│  SwiftBook.app (viewer)                                       │
│   ├─ file watcher ──▶ build orchestrator (swift build /       │
│   │                     xcodebuild, incremental)              │
│   ├─ git service (history, LFS-aware blob reads)              │
│   ├─ diff engine (Core Image)                                 │
│   └─ renderer supervisor ──IPC──┬─▶ macOS renderer (gen N)    │
│                                 │                             │
│                                 └─▶ iOS Simulator             │
│                                      └─ iOS renderer (gen N)  │
└───────────────────────────────────────────────────────────────┘
```

**Renderers**
- Each renderer is built from a hidden host package under `.build/swiftbook/` that depends on the user's package and links its library products. No source is generated, because discovery happens at runtime.
- Renderers are **per platform and per build generation**. A successful build starts a new renderer and warms it up. Once it is ready, the viewer swaps over to it and shuts the old one down. The viewer never tries to unload code from a running process.
- The protocol has three requests: list stories, render (story, variant) → PNG plus metadata, and shutdown.

**Isolation**
- Every render has a timeout. A hung or crashed renderer is killed and restarted, and the failing story is marked.
- A build error stops at the orchestrator and is shown in the UI.
- The viewer's main thread never waits on a renderer or on a build.

**Speed**
- Incremental builds, a warm renderer, and rendering what's visible first.
- Renders are cached by (build generation, story, variant).

macOS cells are images. An "open interactively" action asks the renderer to show the story in a window of its own. Embedding interactive stories in the viewer through remote layer hosting (private API, as Xcode's canvas does) is deferred.

### Discovery

There is one mechanism: **scan the binary at runtime** for `PreviewRegistry` conformances (from `#Preview`) and `PreviewProvider` conformances (from the legacy format) in the loaded images, and build each preview through Apple's public `makePreview()`.

- Reading display name, traits, and body from Apple's `Preview` value needs private internals. All of that lives in a single **preview adapter** module.
- **Breakage guards:**
  - **Hard error, never a skip.** If the adapter finds a preview it can't read, it fails loudly. The message names the Xcode and SDK version and the shape it didn't expect.
  - **`swiftbook doctor`** reports how many previews were discovered and how many parsed.
  - **SwiftBook's own CI** renders a fixture covering every `#Preview` form (named, traits, `@Previewable`, `PreviewModifier`, `arguments:`, UIKit/AppKit, `PreviewProvider` groups) on every supported platform. It also runs on Xcode betas, so breakage is caught before users hit it.
- Story identity is module + source file + display name. Unnamed previews are numbered by their order within the file, so moving code doesn't rename them. SwiftBook encourages naming previews.
- **`PreviewModifier` traits are supported in v1.** The adapter runs the shared-context setup and applies the body. If an Xcode release breaks this, the result is the same hard error as any other unreadable preview.
- **`#if DEBUG` is optional.** SwiftBook builds in Debug by default, where guarded previews are present. A consumer that builds in optimized configurations can use its own compilation condition.

### Rendering

- **Pinned for determinism:** appearance, scale, size (from the layout trait), locale, time zone, and dynamic type size.
- **macOS** renders an `NSHostingView` in an offscreen borderless window with an explicit `NSAppearance`. Fulbloom has proven this setup.
- **iOS and tvOS** render a `UIHostingController` in a `UIWindow` using `drawHierarchy`. This runs inside a **real app process** in a pinned simulator, because without a host app `drawHierarchy` returns blank images ([spike](spikes/ios-renderer.md)).
  - SwiftBook generates and builds that renderer app itself. The user doesn't need an app target.
  - First choice: a hidden `.swiftpm` package with an `.iOSApplication` product. Fallback: `swift build` plus our own `.app` wrapper.
  - The cycle from an edit to a new render took about 3 s in the spike.
- Animations are disabled. Rendering waits until two consecutive captures match, instead of using fixed delays.
- Rendering-environment metadata goes in PNG text chunks: OS build, device, scale, SwiftBook version, and adapter version. A mismatch on verify produces a readable explanation, not just a pixel diff.

**Variants**
- The default set is **light and dark on every platform the tests run on**.
- Other dimensions are opt-in, through the opt-in declaration or per-story metadata (see [Opting in and configuring](#opting-in-and-configuring)).

### Diff engine

Ours, written on Core Image with no dependencies:

- **Pass/fail:** a per-pixel perceptual difference (CIE Lab ΔE), which also feeds the highlight overlays.
- **Anti-aliasing tolerance:** ported from pixelmatch (ISC license).
- **Fast path:** a quick exit for identical images.
- **Thresholds:** a changed-pixel ratio and a ΔE tolerance, with defaults set by the opt-in declaration and per-story overrides through story metadata.

The same engine runs in tests, the CLI, and the viewer.

### Storage

References live in a top-level `Snapshots/` directory next to `Package.swift` or the `.xcodeproj`:

```
Snapshots/
  <Module>/<FileStem>/<Story Name>/<platform>.<colorScheme>[.<other dims>].png
```

- They sit outside every target directory. SwiftPM doesn't warn about unhandled files, and Xcode's synchronized folders don't pull them in.
- One LFS rule, which `swiftbook init` writes: `Snapshots/**/*.png filter=lfs diff=lfs merge=lfs -text`.
- File names carry only the dimensions. The rendering environment goes in the PNG metadata, so an Xcode upgrade re-renders images instead of renaming them.
- `prune` deletes orphaned references.

### Git integration

- **Expected images** are the references in the working tree. Any other basis reads blobs with `git cat-file --filters <rev>:<path>`, which resolves LFS pointers. Missing LFS objects are fetched on demand.
- **Change status** for the sidebar filters is computed in two steps:
  1. *Source-changed*: stories in files touched by the basis diff. Cheap, and shown immediately.
  2. *Image-changed*: the current render differs from the basis reference. The definitive result, filled in as renders complete.
- **History views** compare committed references across revisions. Old revisions aren't rebuilt.
- **Difftool:** `swiftbook init` can register a `git difftool` that opens the viewer's comparison mode for PNGs.
- **Hosting:** any Git LFS server works, including GitHub's. There are no other hosting-specific features.

## Platform support

| | Rendering (tests and Mac viewer) | Viewer app |
|---|---|---|
| macOS | v1 | v1, live |
| iOS | v1 (simulator) | v2, static |
| tvOS | v1 (simulator) | v2, static |
| watchOS, visionOS | later | later |

## Phasing

1. **Core:** discovery and the adapter guard, macOS rendering, the diff engine, storage, and `SwiftBookTesting` under `swift test`. Fulbloom adopts at this point.
2. **CLI:** `test`, `diff`, `prune`, `init`, and `doctor`, plus iOS and tvOS rendering in the simulator.
3. **macOS viewer:** renderers out of process, live rebuild, the sidebar with history filters, and toolbar A, B and C.
4. **Viewer depth:** swipe, onion skin, blink, and diff overlays, iOS renderer streaming into the Mac viewer, and the difftool.
5. **Static iOS and tvOS viewer apps.**

## First consumer

Fulbloom Finance is a macOS SwiftUI app built as a SwiftPM package. It has 29 `#Preview`s using `.fixedLayout`, fixtures, and `#if DEBUG`. Its constraints are:

- Plain `swift test`.
- No prebuilt binaries.
- Minimal pinned dependencies, with swift-syntax acceptable.
- References in LFS.
- Deterministic macOS rendering.
- A macOS story browser.

Details are in [research.md](research.md#first-consumer-fulbloom-finance).

## Open questions

1. **The story metadata vocabulary.** Deferred until the basics work. See [ideas/story-metadata.md](ideas/story-metadata.md).
2. **Projects without a package (deferred).** v1 assumes stories live in SwiftPM library products. The core runtime and tests work in any test target; only `swiftbook view` and the CLI assume a package.
3. **The name.** "SwiftBook" is a placeholder. [hpennington/SwiftBook](https://github.com/hpennington/SwiftBook) already exists in this exact space ("documenting, isolating, and testing SwiftUI, UIKit & AppKit components"), so a public release needs a different name.
