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
- [x] **`preview-adapter`**
  - The one isolated module that reads private `Preview` internals: display name, traits, body, `PreviewModifier` application, `arguments:`, and `PreviewProvider` variants.
  - Done, except `arguments:`, which landed with `preview-arguments`.
  - When it can't read something, it raises a hard error that names the Xcode and SDK versions and the shape it didn't expect.
  - Each `arguments:` value becomes its own story (moved to `preview-arguments`).
  - Tests cover legacy `PreviewProvider`s rendered in Debug builds, where the 26+ SDKs wrap views in `DebugReplaceableView`. Xcode's own preview agent crashed on this case ([tour](research/xcode-previews-ux.md)).
- [x] **`macos-renderer`**
  - An offscreen `NSHostingView` in a borderless window.
  - Pinned settings: appearance, scale, size from the traits, locale, time zone, and Dynamic Type.
  - Animations are off, and rendering waits until two captures in a row match.
  - Rendering-environment metadata goes into PNG text chunks.
- [x] **`diff-engine`**
  - A perceptual CIEDE2000 comparison on the CPU, with pixelmatch-style anti-aliasing tolerance and a fast path for identical images.
  - It reports the changed-pixel ratio and the maximum ΔE, and produces a diff image.
- [x] **`snapshot-storage`**
  - The `Snapshots/<Module>/<FileStem>/<Story>/<device>.<scheme>….png` layout and name sanitization.
  - Reading and writing metadata.
  - Record modes: `missing`, `changed`, `all`, `never`.
- [x] **`swift-testing-macro`**
  - `#SwiftBookTests(variants:)` expands to a parameterized Swift Testing test.
  - Each variant gets its own failure, with reference, actual and diff images attached.
  - The record mode comes from an environment variable.
- [x] **`vibrant-text`**
  - Sidebar vibrancy (text, icons, fills, selection) rendered wrong with `cacheDisplay`.
  - Fixed two ways:
    - **Window-server capture** with ScreenCaptureKit is the default when Screen Recording is granted, and is exact.
    - **Emulation** is the fallback: each vibrant layer's color matrix applied to its backdrop, measured against the window server at ≤0.7% of pixels changed in light mode. Dark glass backgrounds differ by ΔE ≈ 15.
  - Both match the window server's inactive-window style, because the test process is never the active app.
  - Cost: window-server capture waits for the window server to settle, about 0.65 s per image versus about 0.1 s emulated.
- [x] **`fulbloom-adoption`**
  - Send Fulbloom a pinned revision plus the `Package.swift` changes.
  - Fulbloom records light and dark references for all 29 previews and runs its CI.
  - Landed in Fulbloom at `3ff0ffe`, pinned to SwiftBook `41b40ec`.
  - Adoption surfaced two vibrancy bugs, both fixed: hover states from the real pointer, and stale layers composited at the origin. It also surfaced `glass-emulation`.

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

- **What worked.** The single discovery mechanism (a conformance scan plus the `Mirror`-based adapter) read every zoo form except `arguments:`, and all 49 of Fulbloom's previews. One macro line was all the configuration Fulbloom needed. The diff engine needed no changes after its golden tests.
- **What surprised us: rendering fidelity, not discovery, was the hard part.** Most of the phase went to sidebars and glass:
  - Vibrancy is applied by the window server, so `cacheDisplay` misses it.
  - The test process is never the active app, so windows draw in their inactive style.
  - The real pointer leaked hover states into offscreen windows.
  - `cacheDisplay` changes SwiftUI's layer tree while it draws.
  - Window-server capture is exact, but it needs Screen Recording permission and an unlocked screen, and it's about 6× slower.
- **What surprised us: emulated output drifted between days.** The same commit on the same OS stopped reproducing references (`glass-emulation`).
- **Debugging lesson.** Bisect the capture pipeline before theorizing about the environment. Compare the raw capture, the composite, and each layer's contribution. Preference and lock-state hypotheses cost hours; a per-layer bisect found the bug in minutes.
- **Adoption friction.** Reviewing Fulbloom's 92 new references one at a time was slow, and no summary showed what a `changed` run had re-recorded. The validation packet's generated HTML page proved the review-page idea.
- **Replan.**
  - Phase 2 starts with `glass-emulation`, since it's a CI determinism risk, then the cheap adoption fixes: `record-summary`, `readme` and `review-page`.
  - `vibrant-text` moved into Phase 1's record, where the work happened.

## Phase 2: CLI, git, iOS and tvOS

- [x] **`glass-emulation`**
  - Emulated captures drew Liquid Glass controls as a flat fallback. `cacheDisplay` calls `_setDoingCacheDisplayInRect:`, which SwiftUI observes: it re-renders, swapping a control's glass layers (`CABackdropLayer`, SDF layers) for a translucent white fill with a 1-point border, until the window next displays.
  - Fixed by drawing with `displayIgnoringOpacity(_:in:)`, which `cacheDisplay` wraps, so the glass stays. Against the window server, Fulbloom's sidebar search field went from mean ΔE 6.4 to 3.9 in light mode and from 10.9 to 5.6 in dark. The zoo's references were unchanged.
  - Still differs from the window server: the glass edge highlight, and the dimmed placeholder text inside glass. Window-server capture is exact.
  - The Oct 2 drift of Fulbloom's references stays unexplained. It happened inside the swap this avoids.
- [x] **`record-summary`**
  - In `changed` and `all` modes, report which references were re-recorded, even when the run passes, so a reviewer knows what to look at. From Fulbloom's adoption feedback.
  - Each re-recorded reference is a Swift Testing warning: what changed, and a diff image under `.build/swiftbook/recorded/`. The run still passes. `all` mode leaves byte-identical references alone and doesn't report them.
  - Artifacts moved under `.build/swiftbook/{failures,recorded}/`. `$SWIFTBOOK_ARTIFACTS` replaces `.build/swiftbook`.
- [x] **`readme`**
  - Usage docs. Include:
    - `swift test --filter SwiftBookSnapshots` to run only the snapshots.
    - Injecting fixed times in previews instead of reading `Date.now`.
    - What each `SWIFTBOOK_RECORD` mode does.
  - From Fulbloom's adoption feedback.
- [x] **`review-page`**
  - `swiftbook review` writes an HTML page of new and changed references: grouped by file, light and dark side by side, diffs beside failures. Reviewing Fulbloom's 92 new references one at a time was the slowest step of adoption.
  - Done for `swift test`: every recording and failure writes its images and a JSON entry under `.build/swiftbook/`, and rewrites `review/index.html` from them. Each message ends with the page's path. The page copies its images, so it stays accurate after references change and can be uploaded from CI as is.
  - `swiftbook review` itself waits for `cli-skeleton`.
- [x] **`preview-arguments`**
  - Support parameterized `#Preview(arguments:)`: one story per argument, named `<preview> / <argument>`, with the group metadata's item descriptions as labels.
  - The group closure is `makeBody(PreviewGroupIndex?) -> (Body, PreviewGroupIndex)`, and it takes its index and returns both results indirectly, because `PreviewGroupIndex` is resilient. Calling it through `Reflection.function` crashed because a closure held in a generic parameter returns a tuple as one indirect value, not two. `PreviewGroup` calls it instead through a shadow generic struct whose stored closure has the same convention.
- [ ] **`capture-speed`**
  - Bring window-server capture closer to emulated speed. Options: settle on a damage signal instead of a fixed delay, or capture several windows concurrently.

- [x] **`cli-skeleton`**
  - The `swiftbook` command with `init` (`.gitattributes` LFS rule and difftool configuration) and `doctor` (toolchain, simulators, LFS, and discovery and adapter health).
  - Exit codes separate "snapshots changed" from "something broke".
  - Done, built on swift-argument-parser, with the commands in a testable `SwiftBookCLI` library.
    - Exit statuses: 0 for success, 1 when snapshots changed, 2 when something broke, and 64 for usage errors.
    - `init` writes the LFS rule.
    - `doctor` checks macOS, Xcode, Git, Git LFS, the LFS rule, unpulled LFS pointers, Screen Recording, and simulator runtimes, with `--json` output.
    - `review` opens the page from the last test run.
  - Deferred: the difftool goes with `git-difftool`, since it needs the viewer. Discovery health goes with `renderer-protocol`, since the CLI can't load user code until then.
- [x] **`git-service`**
  - Resolve revisions and the merge-base.
  - Read files at a revision with `git cat-file --filters`, fetching LFS objects on demand.
  - List the files changed against a basis.
  - Done as `GitRepository` in SwiftBookCore (macOS), over the `git` command.
    - Bases: uncommitted changes, the last commit, the branch's merge-base with the default branch, or any revision.
    - Changes cover staged and untracked files, and show renames as a deletion and an addition.
    - An LFS pointer that can't become its image is an error naming Git LFS.
  - Tested against scratch repositories: revisions, branches across a rebase, staged and untracked changes, LFS round trips, and missing LFS objects.
- [x] **`cli-diff-prune`**
  - `diff [<basis>]` and `prune`, with human-readable, JSON and JUnit output.
  - `swiftbook diff [<revision>] [--merge-base] [--format human|json|junit] [--open]` is done.
    - It compares the working tree's references, staged and untracked included, with those at a revision: HEAD by default, or the merge base with `--merge-base`.
    - It reports each one added, deleted, or modified, with pixel stats. Modified references within tolerance are listed, but don't count as changes.
    - `--open` writes a page of before, after and diff images.
    - It exits 1 when something changed. The comparison lives in SwiftBookCore (`SnapshotStore.changes(since:in:)`) for the viewer to reuse.
  - `prune` moved to `renderer-protocol`. Deciding what's orphaned needs every current story and variant, and only a process that loads the user's code knows them. Guessing from a partial test run could delete live references.
- [x] **`renderer-protocol`**
  - A versioned IPC protocol (list, render, shutdown), shared by the CLI, the viewer and every renderer.
  - A macOS renderer process that implements it.
  - `swiftbook prune`: delete references whose story or variant no longer exists, using the renderer's list.
  - `swiftbook doctor` reports how many previews were discovered and read.
  - Done.
    - **Protocol (`RendererProtocol`, version 1):** newline-delimited JSON on the renderer's stdin and stdout, starting with a hello. `list` returns stories, and with `check` it builds each view and reports failures. `render` returns a PNG with its metadata. Then `shutdown`. The renderer moves its own stdout to stderr, so user code that prints can't corrupt the stream.
    - **Host (`RendererHost`):** a package at `.build/swiftbook/renderer`. It links every library product of the user's package plus the new `SwiftBookRenderer` library, and depends on SwiftBook the way the user's package resolved it: the same path, or the same URL and revision. It starts from the user's `Package.resolved`. No linker flags were needed: SwiftPM links package targets' object files whole, so conformance records survive. If SwiftBook is in `swift package edit` mode in the user's package, the host edits it to the same working copy (since added).
    - **Supervision (`RendererProcess`):** per-request timeouts stop a hung renderer (SIGTERM, then SIGKILL). A crash is reported with its exit status and the tail of its stderr. A renderer speaking another protocol version is refused.
    - **Commands:** `swiftbook list [--check] [--json]`. `swiftbook prune [--dry-run]` deletes story directories that match no current story, only in modules the renderer links, and keeps variants. `doctor` checks discovery unless `--quick`.
    - **Timing on the zoo:** a cold host build and list takes about 14 s; warm, about 4 s, including the no-op build. A renderer's render of the zoo's Card is byte-identical to the reference recorded by `swift test`.
    - Variant-level pruning waits until the CLI knows which variants each platform records.
- [x] **`ios-host-app`**
  - A generated hidden `.swiftpm` host with an `.iOSApplication` product, built with `xcodebuild`.
  - The fallback is `swift build` plus our own `.app` wrapper; see the [spike](spikes/ios-renderer.md).
  - SwiftBook creates and reuses its own dedicated simulator.
  - Fulbloom's iPhone app is the first real test bed. Its `PhoneBrowser` previews (iOS-only, in FBFUI) use a Liquid Glass floating tab bar and a split search tab (`Tab(role: .search)` with `.tabViewSearchActivation(.searchTabSelection)`), a good fidelity check for materials and the tab bar. When `cli-test` can run iOS, message the "iOS app parallel development" session, which will wire it into Fulbloom's CI.
  - In a host app, a SwiftPM resource directory copied as `Resources` (`.copy("Resources")`) makes codesign fail with "bundle format unrecognized", because iOS bundles are flat. The host must handle or diagnose this for user packages.
  - Done with the fallback, which proved simpler than `.iOSApplication`.
    - **Build:** the macOS renderer's host package, cross-compiled with `swift build --triple arm64-apple-ios27.0-simulator`. It's wrapped in a minimal app: the SDK stamped with `vtool`, an `Info.plist` with a scene manifest, the package's resource bundles copied in, and an ad hoc signature.
    - **Resource diagnosis:** a resource bundle with a top-level `Resources` directory gets a clear error naming the fix.
    - **Simulator:** `Simulator.dedicated(for:)` creates and reuses "SwiftBook iPhone 17 Pro (iOS 27.0)" on the newest iOS 27+ runtime.
    - **Connection:** the app connects back over TCP to a port the client listens on, since there's no stdin, and speaks the same protocol. `RendererProcess` supervises it by pid, and reads its stderr from a log file.
    - **Rendering:** `UIKitRenderer` renders each story in its own window of the app with `drawHierarchy`. The device layout fills the screen with its safe areas; fitted and fixed layouts drop the safe area. It pins the same environment as macOS, at the device's native scale.
    - **Results on the zoo:** 34 stories, all readable, including the UIKit views. Lists, text fields and materials render faithfully, and output is byte-identical across app launches. A warm list takes 6.6 s; rendering all 68 variants takes 15 s.
    - **CLI:** `swiftbook list --platform ios` and a new `swiftbook render [<story>…] [--platform] [-o dir]`.
    - **Since added:** orientation, iPad, and tvOS. The app rotates its scene to a story's orientation with `requestGeometryUpdate` before rendering. iPad and Apple TV get their own pinned simulators (11-inch iPad Pro, Apple TV 4K). tvOS needed `vtool` platform number 8 and a background without `systemBackground`.
- [x] **`cli-test`**
  - `swiftbook test [--platform] [--record]` runs macOS through `swift test` and iOS/tvOS through the renderer app.
  - With no `--platform`, it runs every platform that has references.
  - Done.
    - The Mac runs `swift test --filter SwiftBookSnapshots` with the record mode passed through. Other devices render every story, light and dark, through their renderer and verify against `<device>.<appearance>.png` references.
    - Verification messages, artifacts and the review page come from `SnapshotReport` in SwiftBookCore, now shared by `#SwiftBookTests` and the CLI, with tool-specific hints such as "swiftbook test --record changed".
    - `--device` repeats, and accepts platform names (`--platform ios`). `--record` takes a record mode. `--junit` writes one test case per snapshot. With no device, it tests every device that has references.
    - The zoo has iPhone, iPad, and Apple TV references (204), and CI verifies them with `--record never`, in about 100 s.
    - Not yet: variants other than light and dark on simulated devices, and `excluding:`. The CLI can't read `#SwiftBookTests`' arguments.
    - From Fulbloom's iPhone adoption: an indeterminate `ProgressView` spun between captures, because Core Animation runs animations outside the app. Render windows now stop their layer clock (`speed = 0`) before content arrives, so every animation stays on its first frame. The zoo's new Hazards/Progress story is the canary. Renderer build failures now lead with the compiler's errors.
    - Fulbloom's iPhone adoption, round two (152 references):
      - Hangs past the 30 s timeout used to fail every remaining story. The CLI now restarts a renderer that crashes or hangs, and retries the story once on the fresh one (`RestartingRenderer` in SwiftBookCore). The test summary counts restarts.
      - A capture that's all one color must hold for a second before it counts as settled, since a presentation such as an inspector sheet may not have drawn yet.
      - The hangs didn't reproduce in four runs on Fulbloom's branch, two of them under load.
      - One story's Liquid Glass tab bar settles one pixel in one of two states (ΔE about 2), so its reference failed every other run. The diff engine now has a noise floor: at most 10 changed pixels, none past ΔE 3, still match. `swiftbook test` takes tolerance options, since it can't read `#SwiftBookTests(tolerance:)`.
- [x] **`tvos-runtime`**
  - Install the tvOS simulator runtime (a human step) and get the zoo rendering on tvOS.
  - Done: Brandon installed tvOS 27, and the zoo renders and verifies on Apple TV 4K.

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

- [x] **`viewer-shell`**
  - `swiftbook view` builds and launches the viewer app from source.
  - The viewer shows a story tree, a canvas, and a toolbar placeholder.
  - Done.
    - **The app:** the `swiftbook-viewer` product, a SwiftUI app with a sidebar tree (module, file, story), a canvas, an appearance picker, and a disabled Compare menu as the placeholder. It drives the package's macOS renderer process from a queue of its own, so its main thread never waits.
    - **`swiftbook view`:** builds the viewer as the package resolved SwiftBook, launches it with `nohup`, and logs to `.build/swiftbook/viewer.log`.
    - **No arguments:** the viewer reads its package from `SWIFTBOOK_PACKAGE`. AppKit treats command-line arguments as files to open, and SwiftUI then opens no window.
    - **Smoke test:** with `SWIFTBOOK_VIEWER_SNAPSHOT`, it draws its window to a PNG and its model's state to JSON beside it, then quits. CI checks that it reaches "ready" with a rendered image. The drawing misses the sidebar's vibrant text, which is why the JSON exists.
    - **Tests:** `ViewerModelTests` covers the tree, start-up, one render per story and appearance, render failures, and a renderer that won't start, using a fake renderer.
    - **Quitting:** the viewer needs no shutdown step, because a renderer exits when its input closes. Deferring termination until the renderer stopped hung, because the main-actor task never ran while AppKit waited.
- [x] **`renderer-supervisor`**
  - Starts, warms up and swaps renderers for each build generation.
  - Enforces render timeouts and restarts crashed or hung renderers.
  - Never blocks the main thread.
  - Done as `RendererSupervisor` in the viewer.
    - **Rebuilds:** they run on a build queue while the current renderer keeps serving. The new renderer is warmed by listing its stories (discovery), then swapped in, and the old one shuts down. Requests run on a queue of their own.
    - **Recovery:** a render that crashes the renderer, or outlives the timeout (30 s; the viewer shows it), fails with the reason, and the renderer restarts from the same build for the next request.
    - **In the model:** renders remember their generation. After a reload, the old image stays up, with a spinner, until its replacement arrives. A failed rebuild keeps the last good renders under a banner with the diagnostics. Reload is a toolbar button (⌘R) until `build-orchestrator` watches files.
    - **Fault fixture:** `Fixtures/FaultZoo` has previews that crash, hang, and are slow. `RendererSupervisorTests` renders them through real renderers, in about 20 s.
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
