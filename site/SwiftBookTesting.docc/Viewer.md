# Using the Viewer

A Mac app to leave open while you work.

## Overview

The viewer shows every story in your package and redraws them as your code compiles:

```sh
swift run swiftbook view
```

It builds the viewer from source, as your package resolved SwiftBook, and opens it on the
package. Its log goes to `.build/swiftbook/viewer.log`.

<!-- TODO(site): screenshot of the viewer on the zoo. -->

### Browsing stories

The sidebar lists stories by module, file, and story, and the canvas shows the selected story.

- **Search** filters stories by ID.
- **Click** a module or file row to expand or collapse it.
- **Arrow keys** move through the outline as in Finder: up and down move the selection, left
  collapses a row or moves to its parent, and right expands a row or moves to its first child.

After rendering what's on the canvas, the viewer renders the rest in sidebar order, so switching
stories is instant.

**Open Interactively** (⌘O), or double-clicking a cell, shows the selected story live in a
window of its own, in that cell's color scheme and layout direction, so you can click, type, and
scroll in it.

### Seeing what changed

The bar above the stories compares every story against a *basis*:

- **Uncommitted changes**: the working tree against the last commit. This is the default when
  you have uncommitted changes.
- **Last commit**: the last commit against the one before it. This is the default otherwise.
- **This branch**: everything since the branch left the default branch.
- **Revision…**: any branch, tag, or commit.

Each story gets a badge. A story whose source changed is marked at once; when its render
arrives, the badge says whether its image did: **changed**, **new** (no reference at the basis),
or **failed** to render. A reference at the basis that can't be read, such as a Git LFS pointer,
gets a question mark that says why. Stories that render as their references did lose the badge.
The filter button shows only the stories that changed.

Badges compare Mac renders with Mac references. The viewer captures the way those references
were recorded, from the window server or emulated, so a story doesn't look changed just because
it was captured differently; see <doc:Capture>. `SWIFTBOOK_CAPTURE` overrides this.

### Comparing

The toolbar sets three things:

- **Layout**: a single story, **2-up**, or a **grid**.
- **Compare**: what the cells differ in: **color scheme**, **layout direction**, or
  **revision**.
- **Color scheme and layout direction**: the values every cell uses, except along the compared
  dimension and the grid's rows.

The grid also has a row for each value of a second dimension: color scheme, or layout direction
when comparing color schemes.

Comparing revisions puts the reference at the sidebar's basis beside the working tree's render,
labeled with the share of pixels that changed and the largest ΔE. The grid adds a third cell
that highlights the difference. References are recorded left to right only, so right-to-left cells say
there's nothing to compare.

Zoom applies to every cell at once: use the toolbar, ⌘−, ⌘0, ⌘=, or pinch. Scrolling one cell
scrolls the others with it, so you can look at the same detail everywhere.

### Live reload

The viewer watches your package's files. When edits pause, it rebuilds incrementally and redraws
the canvas, in a few seconds. While it rebuilds, the last render stays up with a spinner.
**Reload** (⌘R) rebuilds on demand. Interactive windows reopen on the new build.

### When something goes wrong

Your previews run in a separate renderer process, so nothing they do can take the viewer down:

- **Build errors** appear in a banner over the last good renders.
- **A preview that crashes** fails with the reason, and the renderer restarts for the next
  story.
- **A preview that hangs** fails after 30 seconds, and the renderer restarts. Stories rendered
  ahead of the selection give up after 5 seconds, and render again when you select them.

## See Also

- <doc:CommandLine>

<!-- sources: Sources/SwiftBookViewer Sources/SwiftBookCLI/ViewCommand.swift Sources/SwiftBookCore/Storage/SnapshotStore.swift Sources/SwiftBookCore/Storage/GitLFS.swift -->
<!-- checked: 901dbe2 -->
