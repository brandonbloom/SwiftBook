# The swiftbook Command

Every command, and the environment variables SwiftBook reads.

## Overview

In a package that depends on SwiftBook, run it with `swift run swiftbook <command>`.
`swiftbook help <command>` shows every option.

| Command | What it does |
|---|---|
| `swiftbook view` | Opens the viewer. See <doc:Viewer>. |
| `swiftbook test [--device <device>] [--record <mode>] [--junit <file>]` | Snapshot-tests stories on each device: the Mac through `swift test`, and iPhone, iPad, and Apple TV in SwiftBook's simulators. See <doc:Devices>. |
| `swiftbook diff [<revision>] [--merge-base] [--format human\|json\|junit] [--open]` | Lists references added, deleted, or changed against a revision. See <doc:ComparingHistory>. |
| `swiftbook list [--check] [--device <device>]` | Lists the package's stories. `--check` also builds each one. |
| `swiftbook render [<story>…] [--device <device>] [-o <dir>]` | Renders stories, light and dark, to PNGs laid out like references. |
| `swiftbook prune [--dry-run]` | Deletes references to stories that no longer exist. |
| `swiftbook init` | Adds the Git LFS rule for references to `.gitattributes`. |
| `swiftbook doctor [--json] [--quick]` | Checks your setup. See <doc:Troubleshooting>. |
| `swiftbook review [--print]` | Opens the review page from the last test run. |

### The renderer

`list`, `render`, `prune`, `doctor`, `test`, and the viewer build a *renderer*: a hidden package
under `.build/swiftbook/renderer` that links your package's library products, so SwiftBook can
load your previews in a process of their own. The first build takes as long as building your
package; later ones are incremental.

### Environment variables

| Variable | Effect |
|---|---|
| `SWIFTBOOK_RECORD` | When `swift test` writes references: `missing`, `changed`, `all`, or `never`. See <doc:RecordingAndReviewing>. |
| `SWIFTBOOK_CAPTURE` | How Mac renders are captured: `windowServer` or `emulated`. See <doc:Capture>. |
| `SWIFTBOOK_ARTIFACTS` | Where actual images, diffs, and the review page go, instead of `.build/swiftbook`. |

## See Also

- <doc:ContinuousIntegration>

<!-- sources: Sources/SwiftBookCLI -->
<!-- checked: 0b491d7 -->
