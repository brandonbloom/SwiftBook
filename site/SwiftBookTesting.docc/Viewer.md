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

The sidebar lists stories by module, file, and story. The canvas shows the selected story, and
the toolbar switches between light and dark.

- **Search** filters stories by ID.
- **Click** a module or file row to expand or collapse it.
- **Arrow keys** move through the outline as in Finder: up and down move the selection, left
  collapses a row or moves to its parent, and right expands a row or moves to its first child.

After rendering the selected story, the viewer renders the rest in sidebar order, so switching
stories is instant.

### Seeing what changed

The bar above the stories compares every story against a *basis*:

- **Uncommitted changes**: the working tree against the last commit. This is the default when
  you have uncommitted changes.
- **Last commit**: the last commit against the one before it. This is the default otherwise.
- **This branch**: everything since the branch left the default branch.
- **Revision…**: any branch, tag, or commit.

Each story gets a badge. A story whose source changed is marked at once; when its render
arrives, the badge says whether its image did: **changed**, **new** (no reference at the basis),
or **failed** to render. Stories that render as their references did lose the badge. The filter
button shows only the stories that changed.

Badges compare Mac renders with Mac references.

### Live reload

The viewer watches your package's files. When edits pause, it rebuilds incrementally and redraws
the canvas, in a few seconds. While it rebuilds, the last render stays up with a spinner.
**Reload** (⌘R) rebuilds on demand.

### When something goes wrong

Your previews run in a separate renderer process, so nothing they do can take the viewer down:

- **Build errors** appear in a banner over the last good renders.
- **A preview that crashes** fails with the reason, and the renderer restarts for the next
  story.
- **A preview that hangs** fails after 30 seconds, and the renderer restarts. Stories rendered
  ahead of the selection give up after 5 seconds, and render again when you select them.

## See Also

- <doc:CommandLine>

<!-- sources: Sources/SwiftBookViewer Sources/SwiftBookCLI/ViewCommand.swift -->
<!-- checked: 5656084 -->
