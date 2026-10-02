# SwiftBook implementation plan

This plan implements [vision.md](vision.md). It is a living document: it gets replanned at the end of every phase.

## How to work this plan

- **Steps are named with slugs.** Use the slug in branch names, commits and conversation (for example `discovery-scan`). Do the steps in order unless a step says otherwise.
- **A step is done** when its automated checks pass in CI. Tick its box.
- **A phase is done** after three gates, in this order:
  1. **Automated verification.** The phase's checks run under `mise run ci` and pass.
  2. **Agent-assisted human validation.** The agent prepares a *validation packet*: rendered contact sheets, sample failure output, timings, and a short checklist of what to look at. Brandon works through the checklist and approves, or files issues.
  3. **Mini retro and replan.** Answer in the phase's retro section: what worked, what surprised us, and what changes. Then edit the remaining phases (and the vision doc if needed) before starting the next phase.

## Phase 0: Foundation

- [x] **`repo-skeleton`**
  - **Package and modules.** Create `Package.swift` with the empty modules (`SwiftBookCore`, `SwiftBookTesting`, `SwiftBookMacros`, and the `swiftbook` executable).
  - **Platforms.** macOS, iOS and tvOS, all with a minimum of 27.
  - **Tooling.** `mise.toml` sets `SWIFTBOOK_HOME` and the `deps`, `build`, `test` and `ci` tasks. `scripts/ci` builds and tests with warnings treated as errors, plus `swift format lint --strict`. A minimal GitHub Actions workflow calls `scripts/ci`.
  - **Dependencies.** Only swift-syntax, which the macro needs.
- [x] **`preview-zoo`**
  - A fixture package, `Fixtures/PreviewZoo`, with one example of every preview form:
    - named and unnamed `#Preview`
    - each layout trait
    - `@Previewable`
    - `PreviewModifier` with shared context
    - `arguments:`
    - AppKit and UIKit views and view controllers
    - `PreviewProvider` with one preview and with several
    - previews inside `#if DEBUG`
  - It also includes the content that tends to render wrong: List, TextField, materials, blur, scroll views, and dates.
  - Every later phase tests against it, and it is the canary for Xcode changes.

**Automated verification:** `mise run ci` passes on a clean checkout. The zoo builds on macOS, iOS and tvOS.
**Human validation:** read the zoo to confirm it covers the preview forms used in real code.

### Phase 0 retro

- **CI exit status.** Piping CI output through `tail` hid a failing run and let the commit through. Always check CI's real exit status.
- **Linting gap.** `swift format lint` only sees files git tracks, so new files go unlinted until they're staged.
- **Global gitignore.** Brandon's global `~/.gitignore` ignores any path named `notes`, so `docs/notes` became `docs/ideas`.
- **Prebuilt binaries.** Apple's prebuilt binaries are acceptable, including SwiftPM's swift-syntax prebuilts, which saves about 45 s per clean build. Only third-party binaries are ruled out.
- **Silencing warnings.** It's allowed when a comment justifies it. The legacy `PreviewProvider` fixtures are marked deprecated to silence the 27 SDKs' deprecation warnings.
- **Platform floor.** Raised to 27 on every platform, for SwiftBook and the zoo alike. It removes availability guards for `PreviewModifier` and `arguments:` previews.
- **Replan.** Added `zoo-more-forms` to Phase 4.

## Phase 1: Core, macOS, `swift test`

Fulbloom adopts SwiftBook at the end of this phase.

- [x] **`discovery-scan`**
  - Scan `__swift5_proto` for `PreviewRegistry` and `PreviewProvider` conformances.
  - Story identity is module, file, and display name. Unnamed previews get an ordinal.
- [x] **`xcode-previews-tour`**
  - Use computer use to explore the zoo in Xcode's preview canvas. Record what it looks like and every affordance of the preview system: variants, device and appearance settings, live and selectable modes, pinning, and how errors are presented.
  - Write findings to `docs/research/xcode-previews-ux.md` and propose any vision changes.
- [ ] **`preview-adapter`**
  - The one isolated module that reads private `Preview` internals: display name, traits, body, `PreviewModifier` application, `arguments:`, and `PreviewProvider` variants.
  - When it can't read something, it raises a hard error that names the Xcode and SDK versions and the shape it didn't expect.
  - Each `arguments:` value becomes its own story.
  - Tests cover legacy `PreviewProvider`s rendered in Debug builds, where the 26+ SDKs wrap views in `DebugReplaceableView`. Xcode's own preview agent crashed on this case ([tour](research/xcode-previews-ux.md)).
- [ ] **`macos-renderer`**
  - An offscreen `NSHostingView` in a borderless window.
  - Pinned settings: appearance, scale, size from the traits, locale, time zone, and Dynamic Type.
  - Animations are off, and rendering waits until two captures in a row match.
  - Rendering-environment metadata goes into PNG text chunks.
- [ ] **`diff-engine`**
  - A perceptual ΔE comparison in Core Image, with pixelmatch-style anti-aliasing tolerance and a fast path for identical images.
  - It reports the changed-pixel ratio and the maximum ΔE, and produces a diff image.
- [ ] **`snapshot-storage`**
  - The `Snapshots/<Module>/<FileStem>/<Story>/<device>.<scheme>….png` layout and name sanitization.
  - Reading and writing metadata.
  - Record modes: `missing`, `changed`, `all`, `none`.
- [ ] **`swift-testing-macro`**
  - `#SwiftBookTests(variants:)` expands to a parameterized Swift Testing test.
  - Each variant gets its own failure, with reference, actual and diff images attached.
  - The record mode comes from an environment variable.
- [ ] **`fulbloom-adoption`**
  - Send Fulbloom a pinned revision plus the `Package.swift` changes.
  - Fulbloom records light and dark references for all 29 previews and runs its CI.

**Automated verification:**
- Every zoo form is discovered and parsed on macOS, and a deliberately unreadable shape produces the expected error message.
- Rendering the same story ten times produces byte-identical PNGs.
- Light and dark renders differ, and sizes match their traits.
- Diff-engine golden tests on synthetic image pairs: identical, anti-aliasing shift, one-pixel change, color shift, and size change. The engine meets a performance budget.
- Macro expansion tests.
- End to end on the zoo: record, verify (passes), change a view, verify (fails with a readable message).

**Human validation packet:**
- A contact sheet of every zoo story in light and dark, next to screenshots of Xcode's canvas.
- Three sample failure messages.
- The diff images for the golden cases.
- Fulbloom's recorded references.

### Phase 1 retro

_(fill in on completion)_

## Phase 2: CLI, git, iOS and tvOS

- [ ] **`cli-skeleton`**
  - The `swiftbook` command with `init` (`.gitattributes` LFS rule and difftool configuration) and `doctor` (toolchain, simulators, LFS, and discovery and adapter health).
  - Exit codes separate "snapshots changed" from "something broke".
- [ ] **`git-service`**
  - Resolve revisions and the merge-base.
  - Read files at a revision with `git cat-file --filters`, fetching LFS objects on demand.
  - List the files changed against a basis.
- [ ] **`cli-diff-prune`**
  - `diff [<basis>]` and `prune`, with human-readable, JSON and JUnit output.
- [ ] **`renderer-protocol`**
  - A versioned IPC protocol (list, render, shutdown), shared by the CLI, the viewer and every renderer.
  - A macOS renderer process that implements it.
- [ ] **`ios-host-app`**
  - A generated hidden `.swiftpm` host with an `.iOSApplication` product, built with `xcodebuild`.
  - The fallback is `swift build` plus our own `.app` wrapper; see the [spike](spikes/ios-renderer.md).
  - SwiftBook creates and reuses its own dedicated simulator.
- [ ] **`cli-test`**
  - `swiftbook test [--platform] [--record]` runs macOS through `swift test` and iOS/tvOS through the renderer app.
  - With no `--platform`, it runs every platform that has references.
- [ ] **`tvos-runtime`**
  - Install the tvOS simulator runtime (a human step) and get the zoo rendering on tvOS.

**Automated verification:**
- Git service tests against temporary repos, including LFS-tracked PNGs, rebases, and missing LFS objects.
- CLI exit-code and output tests.
- iOS and tvOS zoo renders pass the same determinism and fidelity checks as macOS. Materials and blur must be visible.
- The edit-to-render latency script reports its numbers in CI.

**Human validation packet:**
- iOS and tvOS contact sheets next to Xcode's canvas.
- `swiftbook diff` output for a staged change.
- A walkthrough of `init` and `doctor` on a fresh clone of Fulbloom.

### Phase 2 retro

_(fill in on completion)_

## Phase 3: macOS viewer

- [ ] **`viewer-shell`**
  - `swiftbook view` builds and launches the viewer app from source.
  - The viewer shows a story tree, a canvas, and a toolbar placeholder.
- [ ] **`renderer-supervisor`**
  - Starts, warms up and swaps renderers for each build generation.
  - Enforces render timeouts and restarts crashed or hung renderers.
  - Never blocks the main thread.
- [ ] **`build-orchestrator`**
  - Watches files, runs incremental `swift build` and `xcodebuild`, and shows diagnostics in a banner.
  - When a build fails, the viewer keeps showing the last good renders.
- [ ] **`render-cache`**
  - Caches renders by (generation, story, variant) and renders what's visible first.
- [ ] **`sidebar-history`**
  - Search and grouping.
  - Basis filters: uncommitted changes, last commit, branch, any revision.
  - Change status in two passes: source changed first, then image changed.
  - Status badges.
- [ ] **`toolbar-compare`**
  - Comparison mode (A), comparison dimension (B) and dimension values (C), including the revision dimension.
  - 2-up and grid layouts, with zoom and pan synchronized across cells.
  - Diff metrics on each cell.
- [ ] **`interactive-window`**
  - "Open interactively" asks the renderer to show the story in its own window.

**Automated verification:**
- Fault-injection fixtures: a compile error, a preview that crashes, a preview that hangs, and a preview that renders slowly. The viewer process survives each one and shows the right status.
- The edit-to-updated-cell latency stays within budget.
- Main-thread hang detection during scripted sessions.
- View-model tests for the A, B and C toolbar state.

**Human validation packet:**
- The agent drives the viewer through a scripted session (computer use), records screenshots and a short screen recording, and reports timings.
- Brandon then keeps the viewer open while working on Fulbloom for a day and logs any friction.

### Phase 3 retro

_(fill in on completion)_

## Phase 4: Viewer depth

- [ ] **`diff-modes`**
  - Swipe, onion skin, blink, and a diff highlight with an adjustable ΔE threshold.
- [ ] **`ios-in-viewer`**
  - The iOS and tvOS renderers stream into the macOS viewer with live rebuilds.
- [ ] **`zoo-more-forms`**
  - Extend the zoo to the preview forms it leaves out: widgets, Live Activities, and visionOS and watchOS previews if those platforms come into scope.
- [ ] **`git-difftool`**
  - `git difftool` opens the viewer's comparison mode for PNGs.

**Automated verification:** diff-mode rendering tests against the golden pairs. A live iOS rebuild updates the viewer within budget. The difftool is invoked correctly from a temporary repo.
**Human validation packet:** a guided tour of each diff mode on real Fulbloom and zoo changes.

### Phase 4 retro

_(fill in on completion)_

## Phase 5: Static iOS and tvOS viewer

- [ ] **`static-viewer`**
  - A static, in-process build of the viewer UI for iOS and tvOS.
  - It has the dimension pickers and comparison across dimensions the device can render.

**Automated verification:** the viewer builds and launches on iOS and tvOS simulators, and smoke tests navigate the zoo.
**Human validation packet:** a test build on a real device.

### Phase 5 retro

_(fill in on completion)_
