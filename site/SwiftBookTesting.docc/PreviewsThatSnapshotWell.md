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

The rest is up to your previews.

### Fix the data

Pass fixed dates, such as `Date(timeIntervalSince1970: 1_790_000_000)`, instead of reading
`Date.now`. Avoid random values and anything that loads from the network or disk.

### Wait for nothing

A render must settle within 2 seconds, and two captures in a row must match. Previews that
animate forever, poll, or load asynchronously fail as "still changing".

### Size deliberately

Use `.sizeThatFitsLayout` for components and `.fixedLayout(width:height:)` for windows and
screens. Views that fill the space they're given, such as a `List`, get the device canvas under
`.sizeThatFitsLayout`.

### Leave a preview out

```swift
#SwiftBookTests(excluding: ["MyUI/Group/Name"])
```

## See Also

- <doc:Stories>
- <doc:Capture>
