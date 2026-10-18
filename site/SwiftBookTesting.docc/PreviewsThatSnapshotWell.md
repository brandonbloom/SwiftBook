# Writing Previews That Snapshot Well

Make every render identical, on every Mac, every time.

## Overview

SwiftBook pins the rendering environment, so a reference recorded on one Mac matches renders on
another:

| Setting | Value |
|---|---|
| Scale | 2× on the Mac; each device's native scale elsewhere |
| Locale | `en_US` |
| Time zone | UTC, including for `Date.formatted()` |
| Calendar | Gregorian |
| Dynamic Type | Large |
| Layout direction | Left to right |
| Animations | Off; every animation stays on its first frame |
| Canvas for the device layout | 800×600 points on the Mac |
| Tint | The system's, unless your package sets one (<doc:MatchingYourAppsTint>) |

The rest is up to your previews.

### Fix the data

Pass fixed dates, such as `Date(timeIntervalSince1970: 1_790_000_000)`, instead of reading
`Date.now`. Avoid random values and anything that loads from the network or disk.

### Wait for nothing

A render must settle within 2 seconds: two captures in a row must match, or three when
capturing through the window server. On a loaded machine, a render gets at least 5 captures,
however long they take. Previews that animate forever, poll, or load asynchronously fail as
"still changing".

### Size deliberately

Use `.sizeThatFitsLayout` for components and `.fixedLayout(width:height:)` for windows and
screens. Views that fill the space they're given, such as a `List`, get the device canvas under
`.sizeThatFitsLayout`.

### Find flaky previews

A preview that renders differently from run to run fails now and then for no reason. Find them
by rendering each story several times and comparing the renders with each other:

```sh
swift run swiftbook flakes --device iphone --runs 20
swift run swiftbook flakes MyUI/Charts/Cash\ flow --runs 50
```

Each run starts a fresh renderer, as CI would. For each snapshot that rendered more than one
way, it reports how often each way appeared, how many pixels differ and where, and whether a
snapshot comparison would fail on the difference. Images of every variant, its difference
(boxed), and an enlarged close-up go to `.build/swiftbook/flakes/<device>`. It compares renders
with each other, not with references, so it works on stories that have none yet.

It exits with status 1 only if a comparison could fail on a flaky snapshot. A snapshot that
varies too faintly to fail a comparison is listed with `≈` and summarized separately.

Common causes: random or live data, the current date or time, content that loads
asynchronously, and animations that don't start from a fixed state.

### Leave a preview out

```swift
#SwiftBookTests(excluding: ["MyUI/Group/Name"])
```

## See Also

- <doc:Stories>
- <doc:Capture>

<!-- sources: Sources/SwiftBookCore/Rendering Sources/SwiftBookTesting Sources/SwiftBookCLI/FlakesCommand.swift -->
<!-- checked: 2bc9529 -->
