# Recording and Reviewing References

Control when references are written, and review them before you commit.

## Overview

A *reference* is a PNG committed to your repository that holds a story's expected appearance,
one per variant, such as `mac.light.png` and `mac.dark.png`. Tests compare fresh renders against
references, and record new ones according to the record mode.

### Record modes

`SWIFTBOOK_RECORD` controls when `swift test` writes references. `swiftbook test` takes the same
values with `--record`.

| Mode | Missing reference | Reference that doesn't match | Use |
|---|---|---|---|
| `missing` (default) | Recorded; the test fails until you review it | Fails | Day-to-day work |
| `changed` | Recorded | Re-recorded, with a warning | Accepting intended changes |
| `all` | Recorded | Every reference that differs at all is re-recorded, with a warning | After changing tolerance or the rendering environment |
| `never` | Fails | Fails | CI |

Re-recordings pass, but each one is reported as a warning, with a diff image showing what
changed. To accept an intended change:

```sh
SWIFTBOOK_RECORD=changed swift test
```

### The review page

Every run that records or fails writes a review page to `.build/swiftbook/review/index.html`.
It shows each story's new, re-recorded, failed, and missing references, grouped by file, with
variants side by side, and reference, actual and diff images for failures. Open it with:

```sh
swift run swiftbook review
```

The page shows only the latest run, and every test message ends with its path. It copies its
images, so it stays accurate after references change, and CI can upload it as is.

@Image(source: review-page.png, alt: "The review page, showing reference, actual, and diff images for a failed weather card in light and dark.")

### Where artifacts go

Actual images, diffs, and the review page go under `.build/swiftbook`. Set
`SWIFTBOOK_ARTIFACTS` to put them somewhere else, such as a directory your CI uploads.

## See Also

- <doc:UnderstandingFailures>
- <doc:ComparingHistory>

<!-- sources: Sources/SwiftBookCore/Storage Sources/SwiftBookCore/Review Sources/SwiftBookCLI/ReviewCommand.swift -->
<!-- checked: 2bc9529 -->
