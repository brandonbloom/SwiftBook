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

### Live reload

The viewer watches your package's files. When edits pause, it rebuilds incrementally and redraws
the canvas, in a few seconds. While it rebuilds, the last render stays up with a spinner.

### When something goes wrong

Your previews run in a separate renderer process, so nothing they do can take the viewer down:

- **Build errors** appear in a banner over the last good renders.
- **A preview that crashes** fails with the reason, and the renderer restarts for the next
  story.
- **A preview that hangs** fails after 30 seconds, and the renderer restarts.

## See Also

- <doc:CommandLine>
