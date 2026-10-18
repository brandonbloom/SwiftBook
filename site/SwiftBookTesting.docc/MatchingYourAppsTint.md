# Matching Your App's Tint

Give every story your app's accent color, so controls look in snapshots as they do in the app.

## Overview

An app usually sets its accent color in its asset catalog: an `AccentColor` color set, named by
the app target's **Global Accent Color Name** build setting
(`ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`). That setting belongs to the app. Previews
render outside it, in Xcode's canvas and in SwiftBook alike, so they get the system's blue: a
prominent button, a toggle, or a link that's green in your app is blue in every snapshot.

Tell SwiftBook the color once, in a library, and it tints every story.

### Declare the tint

Add the `SwiftBook` library to a target whose previews SwiftBook renders, usually the one with
your design system. It contains only declarations and depends only on SwiftUI, so it's safe to
ship in your app:

```swift
.target(
    name: "MyUI",
    dependencies: [.product(name: "SwiftBook", package: "SwiftBook")],
    resources: [.process("Resources")])
```

Then declare one type that conforms to `SwiftBookConfiguration`:

```swift
import SwiftBook
import SwiftUI

struct Snapshots: SwiftBookConfiguration {
    static var tint: Color? { Color("AccentColor", bundle: .module) }
}
```

SwiftBook finds the type the way it finds previews, so there's nothing to register. It applies
`.tint(_:)` around every story in `swift test`, in `swiftbook test` on every device, in the
viewer, and in interactive windows. A color from an asset catalog keeps its light and dark
values.

### Keep one source of truth

The library can't read the app's asset catalog, and the app's build setting can't read the
library's. To keep the two from drifting:

- Put the color in the library's asset catalog, as the configuration above does, and tint the
  app with it in code: `WindowGroup { ContentView().tint(Color("AccentColor", bundle: .module)) }`,
  or through a `Color` extension the library exports.
- Keep the app's own `AccentColor` with the same values too, if you need it. The build setting
  also colors things SwiftUI's `.tint` doesn't reach, such as UIKit and AppKit controls and some
  system UI.

### What changes in your references

Each snapshot records the tint it rendered with, as `#RRGGBB` for its appearance, or
`#RRGGBBAA` if it's translucent. Setting or
changing the tint changes the rendered controls, so re-record:

```
SWIFTBOOK_RECORD=changed swift test --filter SwiftBookSnapshots
swiftbook test --device iphone --record changed
```

A reference recorded with another tint says so when it fails, for example
`tint none → #0D8D6D`.

On the Mac, snapshots render in an inactive window, where macOS draws some controls, such as
prominent buttons and sidebar selections, without the accent. The tint still applies to
everything that uses it in an inactive window, such as `.foregroundStyle(.tint)`.

Declare one configuration per package. If there are several, SwiftBook uses the first by
module-qualified type name and prints a warning.

## See Also

- <doc:PreviewsThatSnapshotWell>
- <doc:RecordingAndReviewing>

<!-- sources: Sources/SwiftBook Sources/SwiftBookCore/Discovery/ProjectConfiguration.swift Sources/SwiftBookCore/Rendering/RenderEnvironment.swift Sources/SwiftBookCore/Storage/SnapshotReport.swift -->
<!-- checked: 2bc9529 -->
