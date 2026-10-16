# SwiftBook research: prior art for SwiftUI visual testing and story viewing

Prior art and technical constraints for a SwiftUI story viewer and visual testing tool. This document records facts and trade-offs; design decisions belong in the vision doc.

Date: 2026-10-01. Local toolchain at time of research: Xcode 27.0 (27A266a), Swift 6.4.

Confidence markers:

- **[verified]** — read from SDK interfaces or run locally.
- **[private]** — depends on undocumented Apple internals and may break in any Xcode release.
- **[unverified]** — from secondary sources or memory; check before relying on it.

## Requirements under consideration

1. Convention over configuration.
2. Cross-platform story viewer: macOS and iOS first, tvOS required, others optional.
3. Automatic preview discovery, so stories are ordinary Xcode previews.
4. Built-in visual diffing.
5. Git / GitHub / LFS-aware local diffing.
6. CI-friendly build integration and CLI.

Plus the concrete requirements of the first consumer (see [First consumer](#first-consumer)).

---

## 1. Apple's preview system

Docs: <https://developer.apple.com/documentation/swiftui/previews-in-xcode> (machine-readable JSON at `https://developer.apple.com/tutorials/data/documentation/swiftui/previews-in-xcode.json`).

### Public API surface

- **`PreviewRegistry`** (DeveloperToolsSupport; iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1) **[verified]**:
  ```swift
  public protocol PreviewRegistry {
    static var fileID: String { get }
    static var line: Int { get }
    static var column: Int { get }
    @MainActor static func makePreview() throws -> Preview
  }
  ```
  Apple documents that the system "uses [it] to locate previews at runtime" and that defining one directly is undefined behavior. `PreviewUnavailable` lets `makePreview()` opt out.
- **`Preview`** is a public struct with **no public accessors**. Display name, traits and body can be constructed but not read back without reflection.
- **Traits** (`PreviewTrait<Preview.ViewTraits>`): `.defaultLayout`, `.sizeThatFitsLayout`, `.fixedLayout(width:height:)`, orientations, `.assistiveAccess`, `.modifier(_:)` (iOS 18 / macOS 15), and trait composition.
- **`PreviewModifier`** (iOS 18 / macOS 15): `static func makeSharedContext() async throws -> Context` plus `body(content:context:)`. Xcode caches the context across previews; the canonical use is a shared SwiftData container. `PreviewModifierContent` has no public initializer.
- **`@Previewable`** hoists `@State` and similar declarations into a generated wrapper view.
- **Parameterized previews**: `#Preview("x", arguments: [T]) { t in … }` (iOS 26 / macOS 27) **[verified]**.
- **Legacy `PreviewProvider`** remains public (back to iOS 13 / macOS 10.15), with `.previewLayout`, `.previewDisplayName`, `.previewDevice`, `.previewInterfaceOrientation`. Enumerating its variants needs underscored API (`_allPreviews`).
- **`DebugReplaceableView`** (26 SDKs): Debug builds erase opaque `some View` return types to this type so previews can hot-swap view bodies. It shows up in `Mirror` dumps and stack traces.

### What `#Preview` expands to [verified]

`#Preview` is an external macro (`PreviewsMacros`, a compiler plugin shipped inside Xcode). Each use becomes one uniquely mangled struct:

```swift
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, watchOS 10.0, *)
nonisolated struct $s…PreviewfMf_15PreviewRegistryfMu_: DeveloperToolsSupport.PreviewRegistry {
  static var fileID: String { "Mod/File.swift" }
  static var line: Int { 5 }
  static var column: Int { 1 }
  @MainActor static func makePreview() throws -> DeveloperToolsSupport.Preview {
    DeveloperToolsSupport.Preview("Named", traits: .sizeThatFitsLayout) {
      struct __P_Previewable_Transform_Wrapper: SwiftUI.View { @State var x = 1; var body: some SwiftUI.View { Foo() } }
      return __P_Previewable_Transform_Wrapper()
    }
  }
}
```

- The expansion has no `#if DEBUG`. Registries **survived `-O` with `-dead_strip`** in a local test **[verified]**. SnapshotPreviews nonetheless reports stripping under some whole-module-optimized release setups, so retention in Release is likely but not guaranteed. Consumers that wrap previews in `#if DEBUG` lose them in Release builds regardless.
- UIKit/AppKit `#Preview` bodies (`NSView`, `UIViewController`, …) use a local result builder. WidgetKit declares widget, timeline and Live Activity variants.

### Runtime discovery [verified, private]

There is no public API to enumerate previews. The working technique, used by SnapshotPreviews and reproduced locally in about 40 lines:

1. Iterate loaded images (`_dyld_image_count`), skipping system and shared-cache images.
2. Read `__TEXT,__swift5_proto` with `getsectiondata`.
3. Follow each relative pointer to a protocol conformance descriptor and keep those whose protocol name is `PreviewRegistry` (or `PreviewProvider`).
4. Call the type's metadata accessor, cast to `any PreviewRegistry.Type`, and call `makePreview()`.

Steps 1–4 use stable Swift ABI layouts, and the result is public-typed. **Extracting the view from `Preview` is the fragile part.** It requires walking private internals through `Mirror` **[private]**:

```
Preview
  displayName: String?
  dataSource: .preview(DefaultPreviewSource<ViewPreviewBody>)
    structure: .singlePreview(makeBody:) | .previewGroup(metadata:, makeBody:)
  traits: [PreviewLayoutTrait, PreviewModifierTrait, PreviewInterfaceOrientationTrait, …]
```

Applying a `PreviewModifier` outside Xcode means calling `makeSharedContext()` and `body(content:context:)` with a `PreviewModifierContent` that has no public initializer. That also needs private work. See Swift Forums: <https://forums.swift.org/t/how-to-get-access-to-a-view-defined-inside-a-preview-macro/68302>.

### How Xcode runs previews (Xcode 16+)

- Previews reuse ordinary Debug build products. With `ENABLE_DEBUG_DYLIB=YES` (the default for apps), the executable becomes a trampoline into `<App>.debug.dylib`.
- Xcode generates `.preview-thunk.swift` files and replaces literals with `__designTimeString(…)` and similar, so literal edits update without a rebuild. Body edits recompile only the files that changed. Previews execute on a JIT executor (`libPreviewsJITStubExecutor.a` [verified]; the "XOJIT" name is [unverified]).
- `XCODE_RUNNING_FOR_PREVIEWS=1` is widely used to detect the preview process but is undocumented **[unverified]**.
- Canvas variants (color scheme, Dynamic Type, orientation) are Xcode UI features, not source-level data. A tool must reproduce them with `.environment(…)` overrides.
- Sources: <https://onee.me/en/blog/how-new-xcode-swiftui-preview-works-under-the-hood/>, <https://developer.apple.com/forums/thread/761439>.

### Platform matrix

| | SwiftUI `#Preview` | UIKit/AppKit `#Preview` | Widget | Live Activity |
|---|---|---|---|---|
| iOS / iPadOS / Catalyst | 17+ | 17+ | 17+ | 17+ |
| macOS | 14+ | 14+ | 14+ | — |
| tvOS | 17+ | 17+ (UIKit) | — | — |
| watchOS | 10+ | — | 10+ | — |
| visionOS | 1+ | UIKit | 26+ | — |

### Headless rendering

- **`ImageRenderer`** (iOS 16 / macOS 13) renders only what SwiftUI draws itself. List, Form, ScrollView-backed content, TextField, Map and any `*ViewRepresentable` come out as placeholders. It is unsuitable as a general renderer, but it is the only option on watchOS.
- **iOS / tvOS / visionOS**: host a `UIHostingController` in a `UIWindow`, lay it out, then use one of:
  - `drawHierarchy(in:afterScreenUpdates:)` — most faithful; needs a window.
  - `layer.render(in:)` — misses blur and materials.
- **macOS**: host an `NSHostingView` in an offscreen borderless `NSWindow`, then use `bitmapImageRepForCachingDisplay` + `cacheDisplay`. Vibrancy and materials need a real window.
- Variants come from `.environment(\.colorScheme | \.dynamicTypeSize | \.layoutDirection | \.locale | \.timeZone)`, or UIKit `traitOverrides`.

### Testing developments, 2025–2026

- **Swift Testing image attachments** (ST-0014; Xcode 26.4+): `Attachment.record(image, named:, as: .png)` for `CGImage`, `CIImage`, `NSImage` and `UIImage` [verified]. There is no SwiftUI attachable type, and no snapshot or diff API in either Swift Testing or XCTest [verified].
- **Xcode MCP (`xcrun mcpbridge`)** exposes a `RenderPreview` tool that returns a PNG of a `#Preview`. It needs a running Xcode with the project open, so it does not fit CI **[unverified schema]**.
- **iOS and tvOS rendering always needs a simulator.** Plain `swift test` runs only on the macOS host, so `swift test` covers only macOS rendering. iOS and tvOS snapshots need `xcodebuild test -destination 'platform=iOS Simulator,…'`.

---

## 2. getsentry/SnapshotPreviews (formerly EmergeTools)

<https://github.com/getsentry/SnapshotPreviews> — MIT, about 630 stars. Reviewed at `93275706` (2026-09-15). Tagline: "Generate snapshot images from your Xcode previews with zero test code."

### Architecture

| Module | Role |
|---|---|
| `SnapshotPreviewsCore` | Runtime discovery (`ConformanceLookup.swift`), `Preview` model, rendering strategies |
| `PreviewsSupport` | **Prebuilt binary xcframework** exposing private DeveloperToolsSupport types. Building it requires hand-patching SDK `.swiftinterface` files. macOS has flagged it as malware (#236, open). |
| `SnapshottingTests` | XCTest base classes. Swizzles `XCTestCase.testInvocations` to add one test per preview. |
| `SnapshotPreferences` | Per-preview modifiers (PreferenceKeys), linked into the app |
| `Snapshotting` | Dylib injected via `DYLD_INSERT_LIBRARIES`. Runs a localhost HTTP server for the accessibility-audit flow. |
| `PreviewGallery` | In-app SwiftUI preview browser |

### Behavior

- **Discovery**: the `__swift5_proto` scan described in [Runtime discovery](#runtime-discovery-verified-private). It matches both `PreviewProvider` and `PreviewRegistry`. Filtering uses regexes over type name or `fileID:displayName`. There is no codegen.
- **Rendering by platform**:
  - iOS: own `UIWindow` + `UIHostingController` (an `intrinsicContentSize` wrapper).
  - macOS: borderless `NSWindow`.
  - tvOS, watchOS, visionOS: `ImageRenderer` only, so no UIKit-backed content renders there.
- **Rendering details**:
  - Scroll views are expanded to full content height.
  - Animations are disabled and `UIActivityIndicatorView` is swizzled frozen.
  - Orientation changes go through `requestGeometryUpdate` and polling.
  - `PreviewDevice` is **not emulated**; it only filters by `SIMULATOR_DEVICE_NAME`.
  - There is no built-in variant matrix for Dynamic Type, RTL or locale.
- **Tests**: users write an empty `XCTestCase` subclass and each preview appears as its own test in Xcode. Other test types:
  - `PreviewLayoutTest` checks layout without capturing images.
  - `AccessibilityPreviewTest` runs `performAccessibilityAudit`.

  Swift Testing is not supported (#272). Renders run sequentially with a 10 s per-render timeout.
- **Output**: `SNAPSHOTS_EXPORT_DIR` receives a PNG plus a JSON sidecar per preview. The sidecar holds display name, group, diff threshold, tags, color scheme and device. An all-image-names manifest supports sharded runs.
- **Diffing: none locally.** There are no references and no record or verify mode. Comparison happens only in Sentry's cloud (`sentry-cli build snapshots`).
- **Per-preview config**: `.snapshotRenderingMode`, `.snapshotExpansion`, `.snapshotDiffThreshold`, `.snapshotTags`, `.snapshotGroup`, `.snapshotAccessibility`. The test bundle finds these via `NSClassFromString` + `Mirror`, which avoids duplicate symbols between app and test bundle.
- **Gallery**: modules → files → previews, searchable. It has no environment toggles, no controls, no diff view, and no Mac-hosted viewer of iOS previews.
- **CI template** (`.github/workflows/ios_sentry_upload_snapshots.yml`):
  1. `build-for-testing` once.
  2. Shard `test-without-building -only-testing` runs.
  3. Merge the shards and upload.

  Test selection is driven by `git diff`, and the workflow is mostly bash in YAML.

### Known problems

- Breaks across Xcode releases: an iOS 26 crash (#240), link errors (#208), invalid bundles (#109).
- Filename and identity bugs (#226, #228, #246).
- Multi-preview `#Preview` groups render a placeholder.
- Orientation changes fail in some window modes (#161).
- Global mutable state lives in statics.

---

## 3. Prefire

<https://github.com/BarredEwe/Prefire>, <https://prefire.ru> — Apache-2.0, about 520 stars, v5.9.0 (2026-09-23).

### Discovery and code generation

- **`#Preview`** is parsed with SwiftSyntax (`PreviewParser`), which extracts name, traits, `arguments:`, `@Previewable` declarations, and **the closure body as raw source text**.
- **`PreviewProvider`** goes through a forked Sourcery, and types must opt in with `PrefireProvider`.
- Generated output is rendered from Stencil templates:
  - `PreviewTests.generated.swift`: XCTest, one test per preview.
  - `PreviewModels.generated.swift`: Playbook data.
- **Bodies are copy-pasted into generated tests.** This breaks on private or file-scoped symbols (hence the `testable_imports` option) and on formatting edge cases. Recent parser bugs: #139, #145, #146, #147, #149, #166.
- `.prefireIgnored()` and `.prefireEnabled()` are matched as **text**, not evaluated.
- Issue #177 proposes replacing Sourcery with SwiftSyntax because of its heavy transitive dependency graph (SwiftPM, llbuild, swift-driver, XcodeProj, swift-crypto).

### Integration

- **SwiftPM / Xcode build-tool plugins**: `PrefireTestsPlugin` on the test target, `PrefirePlaybookPlugin` on the app. Both are **prebuild commands running a committed Mach-O** (`Binaries/PrefireBinary.artifactbundle`). Issue #186 raises the supply-chain concern.
- CLI via Homebrew or Mint.
- **`.prefire.yml`** with `test_configuration` and `playbook_configuration` sections:
  - target and paths
  - `simulator_device`, `required_os`, `snapshot_devices`
  - `preview_default_enabled`, grouping and splitting options
  - imports
- **CI friction**:
  - `defaults write … IDESkipPackagePluginFingerprintValidatation`
  - `IDEPackageSupportDisablePluginExecutionSandbox`
  - `swift test --disable-sandbox` to record
  - template paths broken under SPM (#152, #183)
  - Playbook doesn't work with local packages (#138)

### Snapshots

- Built on swift-snapshot-testing, using `.wait(for:on: .image(precision:perceptualPrecision:layout:traits:))`.
- References go in `__Snapshots__/PreviewTests.generated/<name>.png` next to the test target.
- **Determinism**:
  - Hard failure if the simulator model or OS major version doesn't match the config (the error message was unreadable; #172 fixes it).
  - Animations off.
  - A forced scale of 2.0 on multi-device runs and on macOS.
  - Canvases clamped to 4096 pt.
- Record control via `SNAPSHOT_TESTING_RECORD`, plus `.snapshot(record: true)` per preview.
- **Open proposals that show what's missing**:
  - #171: masking
  - #173: snapshot manifest + `prune` for orphans
  - #174: global preview config
  - #175: wait-for-idle instead of fixed delays
  - #176 / #150: light/dark, Dynamic Type, RTL and locale variants

### Playbook (gallery)

**iOS only** (`#if os(iOS)`). A searchable list, grouped by component or by "user story" (`.previewUserStory(.auth)`). It shows live mini-renders and render time per preview. Excluded from release builds with `PLAYBOOK_DISABLED`.

### Platforms

iOS and tvOS for snapshots, macOS for snapshots since #168. watchOS builds but is unsupported. Requires Swift 6 / Xcode 16.

### Brandon's fork

<https://github.com/brandonbloom/Prefire>, branch `build-generator-from-source`; see its `FORK.md`.

- **Removes the binary and builds the generator from source.** SwiftPM and Xcode run only binary targets as *prebuild* commands, so a from-source generator must run as a **build command that declares its outputs up front**. The fork predicts those outputs in `BuildCommandFiles.swift`. Side effect: a file that mentions `#Preview` without defining one fails the build on a missing output.
- **Vendors the four Sourcery modules it needs.** Depending on the Sourcery package put its SwiftPM fork in every consumer's dependency graph, with stale `swift-argument-parser` and `swift-crypto` pins that broke resolution.
- **Widens swift-syntax to `600..<605`**, because the major version tracks the Swift release.
- **Build cost**: a clean build is about 40–45 s on an M4 Max, mostly swift-syntax and the parser; expect minutes on CI runners.
- **Security review**: nothing suspicious found. Caches are deserialized with `NSKeyedUnarchiver` without secure coding, and `.prefire.yml` is trusted input.

---

## 4. pointfreeco/swift-snapshot-testing

<https://github.com/pointfreeco/swift-snapshot-testing> — about 4.3k stars, v1.19.6 (2026-09-21). The de facto snapshot engine for iOS.

- **Strategies**: `Snapshotting<Value, Format>` composed from `Diffing<Format>`, transformable with `pullback` and `.wait(for:on:)`. Built-ins:
  - `.image` for UIView, NSView, SwiftUI, CALayer and more, with device presets
  - `.recursiveDescription`, `.dump`, `.json`, `.lines`
  - plugins such as AccessibilitySnapshot
- **Record modes** (1.17+): `.all`, `.missing` (the default), `.failed`, `.never`. Set them with `SNAPSHOT_TESTING_RECORD`, with `withSnapshotTesting(record:diffTool:)`, or with the Swift Testing trait `.snapshots(record:diffTool:)`. The global `isRecording` was deprecated because Swift Testing runs tests in parallel.
- **Swift Testing**: auto-detects which framework is running. Version 1.19 adds `DiffAttachment`, which attaches reference, failure and difference images.
- **Image diff**:
  - `precision` is the fraction of pixels that must match.
  - `perceptualPrecision` sets a per-pixel CIE Lab ΔE threshold, computed via Core Image / Metal. A value of 0.98 allows ΔE ≤ 2.
  - The difference image uses a difference blend.
  - Failure artifacts go to `$SNAPSHOT_ARTIFACTS`.
  - `diffTool` prints a command such as `ksdiff a b`.
- **Storage**: `__Snapshots__/<TestFile>/<testName>.<n>.png` next to the test file.
- **Known pain points**:
  - References are only valid for the same simulator model and OS.
  - Rendering drifts with every Xcode release.
  - Apple silicon and Intel anti-alias differently.
  - Screen scale must be pinned.
  - `drawHierarchy` needs a host app.
  - iOS needs a simulator.
  - Repositories fill with binary PNGs and orphans pile up.
  - There is no review UI.

---

## 5. Storybook and the web ecosystem

> The Storybook, Chromatic and web-tool details below come from a research pass that did not fetch live pages. Version-specific details are **[unverified]**.

### Storybook (<https://storybook.js.org/docs>)

- **CSF 3**: a story file's default export is metadata (`component`, `args`, `argTypes`, `decorators`, `parameters`, `tags`). Each named export is a story object. Stories are **data**, consumed by the UI, test runners, docs and Chromatic ("portable stories").
- **Args, argTypes and controls**: serializable inputs. Controls are inferred from types and can be overridden. Args are encoded in the URL so a state can be shared as a link. They merge across project → file → story.
- **Decorators** wrap a story's render (providers, themes, padding). **Parameters** are static metadata read by addons (viewport, delay, diff threshold). Both inherit across project → file → story.
- **Globals and toolbars**: theme, locale and viewport switchers that decorators read. In SwiftUI these are `EnvironmentValues`, and the same axes form the snapshot variant matrix.
- **Manager/preview split**: the UI shell talks to an isolated preview iframe over a message channel. This enables isolation and composition, where one Storybook embeds others.
- **Indexing without execution**: the `stories` glob plus a static AST indexer produce `index.json`, so the sidebar loads instantly and stories load lazily. **Autotitle** derives hierarchy from the file path; story names come from export names.
- **Testing**: every story is a smoke test for free. On top of that:
  - Play functions for interaction tests.
  - An axe-core a11y addon.
  - Vitest integration that turns stories into tests.
  - A visual-tests addon that shows Chromatic diffs inside the local UI.
- **Static build**: `storybook build` emits a hostable site plus `index.json`.
- **Why it won**:
  - The file-glob convention.
  - The story format is plain code.
  - Zero-config essentials.
  - Component isolation.
  - Shareable URLs.
  - A static index that an ecosystem grew around.

### Chromatic (<https://www.chromatic.com/docs>)

- **Baseline = most recently accepted snapshot on an ancestor commit.** A new branch uses the merge-base build, and accepted changes carry forward on the branch.
- **Squash and rebase merges break ancestry.** Chromatic uses the Git host's API to map a merged PR back to its branch builds.
- **TurboSnap** combines the bundler dependency graph with `git diff` so only affected stories are snapshotted; the rest are copied from the baseline. Changes to global files force a full run.
- **Review**: accept or deny per story, PR-style comments, and two GitHub commit statuses (UI Tests and UI Review). CLI flags include `--exit-zero-on-changes` and `--auto-accept-changes` (for main).
- **Diff UI**: side-by-side, a diff overlay (neon highlights), focus mode (dims unchanged areas), and strobe.

### Other visual regression tools

| Tool | Notable ideas |
|---|---|
| Playwright `toHaveScreenshot` | Baselines next to the test with **platform suffixes** (`name-chromium-darwin.png`). Path layout via `snapshotPathTemplate`. `--update-snapshots=all\|changed\|missing\|none`. Retries until two consecutive captures match. `maxDiffPixels` / `maxDiffPixelRatio` / `threshold`. Masks. HTML report with expected/actual/diff/side-by-side/slider. |
| reg-suit | Baselines **outside git**, in S3/GCS keyed by commit. Expected set = merge-base; actual = HEAD. PR comment links to a hosted HTML report. |
| Argos | Capture-agnostic: upload any directory of PNGs. Merge-base baselines, flaky-screenshot detection, GitHub check. |
| Lost Pixel | Baselines in the repo. A GitHub Action commits updates or opens a PR. |
| Loki | `test` / `update` / `approve` commands. Captures on iOS and Android simulators too. |
| BackstopJS | Scenario × viewport matrix in JSON. HTML report with a scrubber slider. |
| Percy, Happo | Hosted cross-browser rendering, approval-based baselines, PR status checks. |

---

## 6. Native-platform equivalents

- **Paparazzi** (Cash App): renders Android Views and Compose on the JVM through layoutlib, with **no device**, so it is fast and deterministic. `record` / `verify` Gradle tasks. Goldens in `src/test/snapshots`, and the docs recommend LFS.
- **Roborazzi**: Robolectric-based, with `record`, `verify`, `compare` and `verifyAndRecord` tasks. With **ComposablePreviewScanner** it generates tests from every `@Preview` by classpath scanning. It documents storing baselines as main-branch CI artifacts instead of in git.
- **Compose Preview Screenshot Testing** (Google): a `@PreviewTest` annotation on ordinary previews, a dedicated `screenshotTest` source set, `update` / `validate` tasks, and an HTML report. The IDE preview annotation *is* the test declaration.
- **Showkase** (Airbnb): an annotation processor discovers every `@Preview` and generates a browsable catalog grouped by preview `group`, plus screenshot tests over the same metadata. This is the closest analogue to "automatic discovery + gallery + snapshots".
- **Flutter**: `matchesGoldenFile` / `--update-goldens`. Alchemist separates platform-independent "CI goldens" (text blocked out) from platform goldens. **Widgetbook** uses annotations and codegen to discover use cases, with knobs and environment addons.
- **iOS, other**:
  - **Playbook-ios** `ScenarioProvider` + `PlaybookUI` + `PlaybookSnapshot`: a separate story DSL, not previews.
  - **iOSSnapshotTestCase**: device, OS and scale suffixes in reference file names.
  - **dafurman/AddPreviews**: a macro that registers previews into an enumerable list.
  - **[eure/swift-storybook](https://github.com/eure/swift-storybook)**: an in-app catalog that discovers `#Preview`s at runtime after a single `Storybook()` call. Not reviewed in depth.
  - **[hpennington/SwiftBook](https://github.com/hpennington/SwiftBook)**: a library for "documenting, isolating, and testing SwiftUI, UIKit & AppKit components", with snapshot testing. Not reviewed in depth. **It already uses our working name.**
  - **[aj-bartocci/Storybook-SwiftUI](https://github.com/aj-bartocci/Storybook-SwiftUI)**: a Storybook-style catalog built on the Objective-C runtime.

---

## 7. Image diffing

### Algorithms

- **pixelmatch**:
  - YIQ color distance weighted toward luminance (`threshold`, default 0.1).
  - Anti-aliasing detection: a pixel on an intensity slope between darkest and brightest neighbors is ignored.
  - Diff PNG: red for differences, yellow for anti-aliased pixels, gray for context.
  - Used by Playwright, Lost Pixel and reg-cli.
- **odiff**: a SIMD reimplementation of pixelmatch, several times faster, with ignore regions.
- **pdiff / perceptualdiff**: a human-vision model (contrast sensitivity, luminance masking).
- **SSIM / dssim**: structural similarity. Good for "how different overall", weak for "where".
- **CIEDE2000 / CIE94 ΔE**: perceptual color distance. ΔE ≤ 1 is imperceptible; about 2 is noticeable only on close inspection.
- **swift-snapshot-testing `perceptualPrecision`**: a per-pixel `CILabDeltaE` map, thresholded, then the fraction of pixels over threshold is counted. A `CIAreaMaximum` fast path short-circuits identical images. This tolerates GPU and simulator noise without hiding real changes.

### Core Image building blocks (native, GPU-accelerated, no dependencies)

| Purpose | Filters |
|---|---|
| Visual difference image | `CIDifferenceBlendMode`, `CIColorAbsoluteDifference` |
| Per-pixel perceptual ΔE map | `CILabDeltaE` |
| Turn the ΔE map into a mask | `CIColorThreshold` |
| Max delta / fraction of changed pixels | `CIAreaMaximum`, `CIAreaMinMax`, `CIAreaAverage` |
| Highlight overlays | `CIBlendWithMask`, `CIConstantColorGenerator` |

The same pipeline can drive both the pass/fail decision and the viewer's overlays.

### Diff UI modes

| Tool | Modes |
|---|---|
| GitHub | 2-up, swipe, onion skin |
| Kaleidoscope | 2-up, blink/flip, split swipe, difference highlight |
| Chromatic | side-by-side, highlight overlay, focus, strobe |
| Playwright | diff, actual, expected, side-by-side, slider |

A common superset:
- side-by-side
- swipe
- onion skin
- blink
- highlight overlay with an adjustable ΔE threshold
- difference heatmap
- **synchronized zoom and pan** — small changes are invisible otherwise
- a list of changed regions to jump between

---

## 8. Git, GitHub and LFS

### LFS

- Scope the LFS rule to snapshot directories: `**/__Snapshots__/**/*.png filter=lfs diff=lfs merge=lfs -text`.
- GitHub renders LFS images in PR rich diffs with 2-up, swipe and onion skin **[unverified for large files]**.
- `git show <rev>:path.png` returns the **LFS pointer text**, not the image. To get the image, use one of:
  - `git cat-file --filters <rev>:path`, which applies the smudge filter
  - `git show <rev>:path | git lfs smudge`
- Run `git lfs fetch origin <rev> --include=<path>` first if the object isn't local.
- Pointer files are recognizable by their first line, `version https://git-lfs.github.com/spec/v1`.

### Baseline selection

- Use the merge-base with the target branch (`git merge-base HEAD origin/main`). This is the Chromatic and reg-suit model.
- Squash merges break ancestry-based lookups when baselines are keyed by commit outside git. With references committed in-tree, the tree at merge-base *is* the baseline, so the problem disappears.

### Local tooling hooks

- **`git difftool`**: `difftool.<name>.cmd "<viewer> $LOCAL $REMOTE"`; `ksdiff` is the classic example.
- **`git diff --ext-diff`** with a `diff=<driver>` attribute.
- **`textconv`** (for example `exiftool`) for text summaries.

### GitHub Actions

- `actions/checkout` with `lfs: true`. Cache LFS objects, because bandwidth quotas bite.
- Upload expected, actual and diff PNGs plus an HTML report with `actions/upload-artifact`.
- Write a Markdown summary to `$GITHUB_STEP_SUMMARY`.
- **Check runs API**: annotations are limited to 50 per request and can point at a source line, such as a preview's `fileID:line`. `output.images[]` takes hosted URLs.
- **There is no API for uploading images into PR comments.** Images need a reachable URL, so the workarounds are:
  - a companion or orphan branch
  - object storage
  - a link to the artifact, which doesn't render inline

### In-git vs external baselines

| | In-git / LFS | External store |
|---|---|---|
| Reproducibility | Reproducible offline | Needs infrastructure |
| PR review | Reviewable in normal PR diffs | Needs a hosted viewer |
| History | Churns on every UI change; LFS quotas | Clean history |
| Baseline lookup | Squash-merge safe | Needs a commit→baseline lookup convention |

---

## 9. Cross-cutting observations

### Discovery approaches compared

| Approach | Examples | Pros | Cons |
|---|---|---|---|
| Runtime `__swift5_proto` scan | SnapshotPreviews | Zero config. Uses exactly the compiled previews, so no body copying and private symbols work. Gallery and tests share one source. | Extracting the body and traits relies on private `Mirror` paths. `PreviewModifier` needs private API. Breaks with Xcode releases. |
| Source scan + body copy-paste | Prefire | No private runtime API | Brittle: private symbols, formatting edge cases, `@Previewable`. Needs a build plugin, with all its sandbox and declared-output pain. |
| Static index (SwiftSyntax) + runtime lookup by `fileID:line` | none observed | Fast listing without execution (Storybook-style index), changed-file → affected-story selection, IDs that match the runtime registry | Still needs the private body-extraction step at render time |
| Own macro or registry alongside `#Preview` | dafurman/AddPreviews, Playbook-ios | Stable public API | Duplicates or replaces `#Preview`, which breaks "previews are the stories" |

The runtime scan itself (finding `PreviewRegistry` types and calling `makePreview()`) uses only public types and stable ABI layouts. The private dependency is concentrated in **reading the `Preview` value**. That isolates the risk to one small, version-checked adapter.

### Rendering and determinism lessons

- Use a hosting view in a window, not `ImageRenderer`, except on watchOS.
- Pin each of these explicitly:
  - appearance (`NSAppearance(named: .aqua)` on macOS, plus the `colorScheme` environment)
  - scale
  - size, from the layout trait
  - locale and time zone
  - Dynamic Type size
  - simulator model and OS
- Disable animations, freeze spinners, and wait for idle (or for two identical consecutive captures, as Playwright does) instead of fixed delays.
- Encode the rendering environment in reference paths or names (platform, OS, scale), and fail with a readable message on mismatch.
- Known macOS offscreen artifacts (from the first consumer):
  - A selected `List` row in a sidebar renders solid black.
  - A `Menu` label containing a colored `Circle` renders blank inside a sidebar `List`.

### CI and CLI lessons

- Make the CLI the primary interface, with build and test integration as a thin layer. Prefire's YAML config and Xcode `defaults` hacks, and SnapshotPreviews' bash-in-YAML, are the failure modes.
- Exit codes should distinguish "changed" from "error".
- Emit machine-readable output (JSON, JUnit) plus an HTML report.
- Keep a manifest of expected snapshots so orphans can be pruned.
- Use explicit update modes (`missing`, `changed`, `all`).
- Support building once and sharding test runs.
- Avoid sandbox-hostile writes: record into an artifacts directory, then copy references into place.

### Viewer lessons

- Every existing Swift gallery is in-app and mostly iOS-only; none has environment toggles or a diff view.
- Storybook's manager/preview split suggests a host/renderer protocol. A macOS viewer could then show renders from iOS and tvOS simulator processes as well as in-process macOS renders.
- Environment "globals" double as toolbar controls and as the snapshot variant matrix.

---

## First consumer

A private app, the first to adopt SwiftBook.

### Project shape

- A macOS SwiftUI app.
- A SwiftPM package (model, UI, and fixture modules) plus a thin Xcode project.
- Swift tools 6.4, macOS 27, Swift 6 strict concurrency.
- CI fails on any warning and runs `swift format lint --strict`.

### Story source

- Plain `#Preview` blocks inside `#if DEBUG` at the bottom of each view file. For example:
  `#Preview("ItemList (empty)", traits: .fixedLayout(width: 420, height: 640)) { let f = Fixtures.named("empty")!; ItemList(…) }`
- Bodies contain `let` statements.
- 29 previews across 7 files.
- **Nothing beyond the `#Preview` block**: no registry, no wrappers, no repeated names.

### Hard requirements

1. Runs under plain **`swift test`**. Xcode test plans are a nice-to-have.
2. Local comparison against references committed in the repo with **Git LFS**, with readable diffs. No cloud services.
3. **No prebuilt binaries** anywhere in the dependency graph.
4. Minimal, pinnable dependencies. swift-syntax is acceptable (about 45 s clean build). Sourcery and Stencil are not.
5. Deterministic macOS rendering:
   - forced light appearance
   - `.fixedLayout` size honored
   - fixed scale
   - ideally a pinned locale and time zone
6. A macOS component browser with search and grouping by view.

### Known-good macOS host

1. Create `NSWindow(styleMask: [.borderless])` with `appearance = .aqua`.
2. Set its `contentView` to an `NSHostingView` wrapping the view with `.environment(\.colorScheme, .light)`.
3. Call `layoutIfNeeded()` and `displayIfNeeded()`.
4. Run `RunLoop.main.run(until: now + 0.2)`.
5. Capture with the NSView image strategy.

Recording into `Tests/<Target>/__Snapshots__/` under `swift test` needed no sandbox flags.

### Integration

It pins packages by exact revision and resolves in CI with `--force-resolved-versions`.

---

## Open questions for the vision doc

1. **Discovery mechanism.** Use a runtime scan with an isolated private-API adapter, a SwiftSyntax static index, or both? How much private-API exposure is acceptable, and how will breakage be detected?
2. **Is `#Preview` the only story format?** Or is there an optional richer layer (args, controls, parameters) for consumers who want it?
3. **Variants.** Which environment axes (color scheme, Dynamic Type, locale/RTL, device) are a default matrix, which are opt-in, and how is that declared without configuration files?
4. **Test integration.** Swift Testing, XCTest or both? Should runtime-generated per-preview tests appear individually in Xcode's test navigator?
5. **`swift test` vs. simulators.** macOS renders under `swift test`; iOS and tvOS need `xcodebuild` with a simulator. Should the CLI own that orchestration?
6. **Viewer architecture.** One in-process app per platform, or a macOS host that drives simulator renderers over IPC?
7. **Diff engine.** Write our own Core Image pipeline, or depend on swift-snapshot-testing? Which metrics are reported (changed-pixel ratio, max ΔE)?
8. **Reference storage convention.** Path layout, environment suffixes, LFS bootstrapping, orphan pruning.
9. **Baseline semantics.** Is the baseline the working tree's committed references or the merge-base tree? How do local "compare against main" workflows resolve LFS pointers?
10. **GitHub integration depth.** Step summary only, or check runs with annotations? Where are images hosted?
11. **Release-build hygiene.** How do previews and the viewer stay out of shipping binaries?
