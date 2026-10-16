# SwiftBook

Snapshot tests for SwiftUI, made from the previews you already have. Every `#Preview` becomes a test that renders it in light and dark mode and compares the result with a reference image committed to your repository.

> **Status: early and private.** SwiftBook renders macOS snapshots under `swift test`. iOS and tvOS rendering, the `swiftbook` CLI, and the viewer app are planned; see [docs/plan.md](docs/plan.md). Interfaces may still change, and there are no tagged releases yet.

## Requirements

- macOS 27 and Xcode 27 (Swift 6.2 tools or later). Every platform's deployment target must be 27 or later.
- [Git LFS](https://git-lfs.com) for reference images.

## Setup

Add SwiftBook to your package, pinned by revision until there are releases:

```swift
dependencies: [
    .package(url: "https://github.com/brandonbloom/SwiftBook.git", revision: "<commit>"),
],
```

Depend on `SwiftBookTesting` from a test target that also depends on the module whose previews you want tested:

```swift
.testTarget(
    name: "MyUITests",
    dependencies: ["MyUI", .product(name: "SwiftBookTesting", package: "SwiftBook")]),
```

Add one file to that test target:

```swift
import SwiftBookTesting
import Testing  // Required: the macro expands to Swift Testing's @Test.

#SwiftBookTests
```

Store reference images in Git LFS by adding this rule to `.gitattributes`:

```
**/Snapshots/**/*.png filter=lfs diff=lfs merge=lfs -text
```

Then run `swift test`. The first run records a reference for each preview and fails, so you review the new images before committing them. Later runs compare against them.

## Running

```sh
swift test                                   # everything
swift test --filter SwiftBookSnapshots       # only the snapshots
```

Each story is one test case, named by its ID (`Module/Group/Name`), with one comparison per variant.

### Record modes

`SWIFTBOOK_RECORD` controls when references are written:

| Mode | Missing reference | Reference that doesn't match | Use |
|---|---|---|---|
| `missing` (default) | Recorded; the test fails until you review it | Fails | Day-to-day work |
| `changed` | Recorded | Re-recorded, with a warning | Accepting intended changes |
| `all` | Recorded | Every reference that differs at all is re-recorded, with a warning | After changing tolerance or the rendering environment |
| `never` | Fails | Fails | CI |

Re-recordings pass, but each one is reported as a warning, with a diff image showing what changed.

### Review page

Every run that records or fails writes `.build/swiftbook/review/index.html`: each story's new, re-recorded, failed, and missing references, grouped by file, with variants side by side, and reference, actual and diff images for failures. Open it before committing references. It shows only the latest run, and every test message ends with its path.

### Failures

A mismatch says how much changed and where, and notes any change in the rendering environment, such as an OS update:

```
MyUI/Card/Card (mac.light) doesn't match Snapshots/MyUI/Card/Card/mac.light.png.
2407 pixels changed (0.12%), max ΔE 31, within 404×60 at (18, 16).
Actual and diff images: .build/swiftbook/failures/MyUI/Card/Card
To accept the change: SWIFTBOOK_RECORD=changed swift test
```

The actual, diff and reference images are also attached to the test result. In diff images, changed pixels are red and anti-aliasing differences are yellow. Set `SWIFTBOOK_ARTIFACTS` to put artifacts and the review page somewhere other than `.build/swiftbook`, for example a directory your CI uploads.

### CI

```sh
SWIFTBOOK_RECORD=never SWIFTBOOK_CAPTURE=emulated swift test
swiftbook test --device iphone --record never   # and ipad, tv, as you have references
```

`never` turns a missing reference into a failure instead of an unreviewed recording. `emulated` makes CI independent of Screen Recording permission and the screen lock; see [Capture](#capture). References must be recorded with the same capture method that verifies them.

## Command line

In a package that depends on SwiftBook, run it with `swift run swiftbook <command>`.

| Command | What it does |
|---|---|
| `swiftbook view` | Opens the viewer on the Mac: every story in a sidebar, rendered as you edit, compared across color scheme, layout direction, or a git revision, and openable live in a window of its own. |
| `swiftbook test [--device iphone] [--record <mode>] [--junit <file>]` | Snapshot-tests stories on each device: the Mac through `swift test`, and iPhone, iPad and Apple TV in SwiftBook's own simulators, light and dark. With no `--device`, tests every device that has references. Concurrent runs each lease a simulator from a pool (`SWIFTBOOK_SIMULATORS` sets its size), and one run spreads across free ones while it pays (`--jobs` caps it). Ends with one `✗` line naming every failed snapshot, and a `swiftbook render` command for the failed stories. |
| `swiftbook diff [<revision>] [--merge-base]` | Lists references added, deleted, or changed in the working tree against a revision (`HEAD` by default), with how many pixels changed. `--format json` or `junit` for machines; `--open` shows before, after and diff images. |
| `swiftbook list [--check] [--device iphone]` | Lists the package's stories. `--check` also builds each one and reports any SwiftBook can't read. |
| `swiftbook render [<story>…] [--device iphone] [-o <dir>]` | Renders stories, light and dark, to PNG files laid out like references, without comparing or recording anything: the quick way to look at one story, or send a picture of it. Prints each file's path. |
| `swiftbook flakes [<story>…] [--device iphone] [--runs <n>]` | Finds stories that render differently from run to run: renders each one `--runs` times (10 by default), each in a fresh renderer, and reports how many ways it rendered, how often, where the renders differ, and whether a comparison would fail. Images of each variant and where it differs go to `.build/swiftbook/flakes/<device>`. Exits 1 if a comparison could fail on any of them. |
| `swiftbook prune [--dry-run]` | Deletes references to stories that no longer exist. Only modules the renderer links are pruned. |
| `swiftbook init` | Adds the Git LFS rule for references to `.gitattributes`. Safe to run again. |
| `swiftbook doctor [--json] [--quick]` | Checks macOS, Xcode, Git, Git LFS, the LFS rule, references that are unpulled LFS pointers, Screen Recording permission, simulator runtimes, and that every story can be read. |
| `swiftbook review [--print]` | Opens the review page from the last test run. |

`list`, `render`, `prune` and `doctor` build a renderer: a hidden package under `.build/swiftbook/renderer` that links your package's library products, so SwiftBook can load your previews in a process of their own. The first build takes as long as building your package; later ones are incremental. `--device` takes `mac`, `iphone`, `ipad`, or `tv` (or `macos`, `ios`, `tvos`). On iPhone, iPad, and Apple TV, the renderer is an app that runs in SwiftBook's own simulator for that device (iPhone 17 Pro, 11-inch iPad Pro, Apple TV 4K), which it creates on first use.

Exit status is 0 for success, 1 when references or snapshots changed or failed, 2 when something else went wrong, and 64 for usage errors.

## How it works

**Discovery.** SwiftBook finds previews at runtime, from the conformance records that `#Preview` and `PreviewProvider` compile into your binary. There's nothing to register. It reads each preview's name, traits, and body through Xcode's preview types, and fails loudly, naming your Xcode version, if those types change shape.

**Stories.** A story's ID is its module, its group (the source file's name), and its preview name. Unnamed previews take the group's name, and repeated names get " 2", " 3", and so on, counting names whose reference files would collide, such as `Dark` and `dark`, as repeated. Each argument of a `#Preview(arguments:)` is its own story, named `<preview> / <argument>` after the argument's description.

**References.** One PNG per variant, at `Snapshots/<Module>/<Group>/<Story>/<device>.<appearance>.png` in the package or Xcode project that contains the test. Each PNG records the rendering environment it was made in.

**Rendering.** Each preview renders in an offscreen window with a pinned environment, so a reference recorded on one Mac matches renders on another:

| Setting | Value |
|---|---|
| Scale | 2× |
| Locale | `en_US` |
| Time zone | UTC, including for `Date.formatted()` |
| Calendar | Gregorian |
| Dynamic Type | Large |
| Layout direction | Left to right |
| Animations | Off |
| Canvas for the device layout | 800×600 points |

Layout traits work as in Xcode: `.sizeThatFits` measures the view, `.fixedLayout` sets the canvas, and `PreviewModifier`s are applied.

**Comparison.** Images are compared perceptually: a pixel counts as changed if its color differs by more than ΔE 1 (CIEDE2000, about the smallest difference people notice). Anti-aliasing shifts along edges are ignored. By default, any changed pixel fails, except for noise: at most 10 changed pixels, none differing by more than ΔE 3, still match, because GPU-rendered materials can settle a pixel differently from run to run. On simulated devices, Liquid Glass gets one more allowance: the simulator draws it in a few faintly different states from run to run, so inside glass a pixel counts only if its 3×3 neighborhood, averaged, still differs by more than ΔE 3. Reference and diff images are unaffected. `#SwiftBookTests(tolerance:)` and `swiftbook test`'s `--delta-e`, `--changed-ratio`, `--noise-pixels` and `--noise-delta-e` adjust all of this.

### Capture

macOS renders are captured one of two ways, and each reference records which:

- **Window server** (the default when allowed): the window is captured with ScreenCaptureKit, exactly as it appears on screen. This needs Screen Recording permission for the app running the tests (Terminal, Xcode, or your agent's host app) and an unlocked screen, and the canvas must fit on the main screen; otherwise SwiftBook falls back to emulated capture. It takes about 0.65 s per image.
- **Emulated** (the fallback, and what CI uses): the view draws itself offscreen, and SwiftBook composites vibrancy that only the window server would apply. It's close to the window server but not exact: Liquid Glass edges, text inside glass, and some sidebar materials differ slightly. It takes about 0.1 s per image.

Set `SWIFTBOOK_CAPTURE=windowServer` or `emulated` to choose.

Windows render in their inactive style, as when another app is in front. For example, sidebar selections are gray rather than the accent color, because the test process is never the active app.

## Writing previews that snapshot well

- **Fix the data.** Pass fixed dates, such as `Date(timeIntervalSince1970: 1_790_000_000)`, instead of reading `Date.now`. Avoid random values and anything that loads from the network or disk.
- **Wait for nothing.** A render must settle within 2 seconds, and two captures in a row must match. Previews that animate forever, poll, or load asynchronously fail as "still changing".
- **Size deliberately.** Use `.sizeThatFits` for components and `.fixedLayout(width:height:)` for windows and screens. Views that fill the space they're given, such as a `List`, get the 800×600 device canvas under `.sizeThatFits`.
- **Leave a preview out** with `#SwiftBookTests(excluding: ["MyUI/Group/Name"])`.
- **Match your app's tint.** Previews render outside your app, so they don't get its accent color (the asset catalog's `AccentColor`). Add the `SwiftBook` library to your UI target and declare the color once; SwiftBook applies it as `.tint` around every story, on every device:

  ```swift
  import SwiftBook

  struct Snapshots: SwiftBookConfiguration {
      static var tint: Color? { Color("AccentColor", bundle: .module) }
  }
  ```

  The library can't see the app's asset catalog, so keep the color in the library's catalog and tint the app from it too.

The macro also takes `variants:` to change which environments each story renders in, and `tolerance:` to loosen comparisons.

## Limitations

- `swift test` renders only macOS; `swiftbook test --device iphone` (or `ipad`, `tv`) tests the others.
- On iPhone, iPad, and Apple TV, `swiftbook test` checks light and dark only, and doesn't apply `#SwiftBookTests`' `excluding:`.

## Developing SwiftBook

The project uses [mise](https://mise.jdx.dev): `mise run ci` runs everything that must pass before a change lands, including formatting, warnings as errors, the zoo's snapshot tests, and iOS and tvOS builds.

- `Fixtures/PreviewZoo` has one example of every preview form, and of the content that tends to render wrong. Its tests consume SwiftBook as a real package would.
- [docs/vision.md](docs/vision.md) is what SwiftBook is meant to become, [docs/plan.md](docs/plan.md) is how it gets there, and [docs/research.md](docs/research.md) covers prior art.
