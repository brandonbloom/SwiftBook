# ``SwiftBookTesting``

@Metadata {
    @DisplayName("SwiftBook")
}

Snapshot tests and a story viewer for SwiftUI, made from the previews you already have.

## Overview

Every `#Preview` in your code is a *story*. SwiftBook renders each story in light and dark mode,
on the Mac, iPhone, iPad, and Apple TV, and compares the result with a reference image committed
to your repository. There's nothing to register and no story format to learn.

```swift
#Preview("Card") {
    Card(title: "Hello", subtitle: "A named preview")
}
```

@Image(source: card, alt: "The Card preview, rendered by SwiftBook on the Mac.")

One line in a test target turns every preview into a test:

```swift
import SwiftBookTesting
import Testing

#SwiftBookTests
```

The `swiftbook` command tests the other devices, compares references against any revision in
git, and opens the viewer: a Mac app you leave open, which shows every story and redraws as your
code compiles.

> Important: SwiftBook is early and private. Interfaces may change, and there are no tagged
> releases yet.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Stories>

### Snapshot testing

- <doc:RecordingAndReviewing>
- <doc:UnderstandingFailures>
- <doc:Devices>
- <doc:PreviewsThatSnapshotWell>
- <doc:Capture>

### References in git

- <doc:StoringReferences>
- <doc:ComparingHistory>

### The viewer

- <doc:Viewer>

### Automation

- <doc:ContinuousIntegration>
- <doc:CommandLine>
- <doc:Troubleshooting>

### Test macro

- ``SwiftBookTests(variants:tolerance:excluding:)``
- ``Variants``
