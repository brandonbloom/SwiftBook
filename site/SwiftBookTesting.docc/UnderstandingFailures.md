# Understanding Failures

Read a mismatch, and tune what counts as one.

## Overview

When a render doesn't match its reference, the failure says how much changed and where, and
notes any change in the rendering environment, such as an OS update:

```
MyUI/Card/Card (mac.light) doesn't match Snapshots/MyUI/Card/Card/mac.light.png.
2407 pixels changed (0.12%), max ΔE 31, within 404×60 at (18, 16).
Actual and diff images: .build/swiftbook/failures/MyUI/Card/Card
To accept the change: SWIFTBOOK_RECORD=changed swift test
```

The reference, actual, and diff images are attached to the test result, and appear on the
review page. In diff images, changed pixels are red and anti-aliasing differences are yellow.

<!-- TODO(site): reference, actual, and diff images of a real failure. -->

### How images are compared

Comparison is perceptual. A pixel counts as changed if its color differs by more than ΔE 1
(CIEDE2000, about the smallest difference people notice). Anti-aliasing shifts along edges are
ignored.

By default, any changed pixel fails, except for noise: at most 10 changed pixels, none differing
by more than ΔE 3, still match, because GPU-rendered materials such as Liquid Glass can settle a
pixel differently from run to run.

### Adjusting tolerance

`#SwiftBookTests(tolerance:)` adjusts comparisons under `swift test`. `swiftbook test` takes
`--delta-e`, `--changed-ratio`, `--noise-pixels`, and `--noise-delta-e`. After loosening or
tightening tolerance, re-record with `SWIFTBOOK_RECORD=all`.

## See Also

- <doc:RecordingAndReviewing>
- <doc:Capture>
