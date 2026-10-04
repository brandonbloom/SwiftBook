# Understanding Failures

Read a mismatch, and tune what counts as one.

## Overview

When a render doesn't match its reference, the failure says how much changed and where, and
notes any change in the rendering environment, such as an OS update. Here, the weather changed:

<!-- transcript: failure -->
```
Wander/WeatherCard/Weather card (mac.light) doesn't match Snapshots/Wander/WeatherCard/Weather card/mac.light.png.
5281 pixels changed (2.11%), max ΔE 44, within 159×144 at (76, 149).
Actual and diff images: .build/swiftbook/failures/Wander/WeatherCard/Weather card
To accept the change: SWIFTBOOK_RECORD=changed swift test
```
<!-- /transcript -->

The reference, actual, and diff images are attached to the test result, and appear on the
review page. In diff images, changed pixels are red and anti-aliasing differences are yellow.

@Row {
    @Column {
        @Image(source: failure-reference, alt: "The reference: 72° and Mostly Sunny.")

        Reference
    }
    @Column {
        @Image(source: failure-actual, alt: "The actual render: 68° and Partly Cloudy.")

        Actual
    }
    @Column {
        @Image(source: failure-diff, alt: "The diff: the changed temperature and condition in red.")

        Diff
    }
}

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

<!-- sources: Sources/SwiftBookCore/Diff Sources/SwiftBookCore/Storage/SnapshotReport.swift Sources/SwiftBookCLI/TestCommand.swift -->
<!-- checked: 5656084 -->
