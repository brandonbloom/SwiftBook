# Getting Started

Add SwiftBook to a package and snapshot-test its previews.

## Overview

SwiftBook needs macOS 27 and Xcode 27, with Swift 6.2 tools or later. Every platform's
deployment target must be 27 or later. Reference images live in [Git LFS](https://git-lfs.com).

### Add the dependency

Pin an exact version. Until 1.0, every release may change alpha features:

```swift
dependencies: [
    .package(url: "https://github.com/brandonbloom/SwiftBook.git", exact: "0.7.3"),
],
```

Depend on `SwiftBookTesting` from a test target that also depends on the module whose previews
you want tested:

```swift
.testTarget(
    name: "MyUITests",
    dependencies: ["MyUI", .product(name: "SwiftBookTesting", package: "SwiftBook")]),
```

### Add the tests

Add one file to that test target:

```swift
import SwiftBookTesting
import Testing  // Required: the macro expands to Swift Testing's @Test.

#SwiftBookTests
```

### Store references in Git LFS

```sh
swift run swiftbook init
```

This adds the rule for reference images to `.gitattributes`. See <doc:StoringReferences>.

### Record and review

Run the tests:

```sh
swift test
```

The first run records a reference for each preview and fails, so you review the new images
before committing them. Open the review page to see them all at once:

```sh
swift run swiftbook review
```

Commit the references. From now on, `swift test` compares every preview against them. See
<doc:RecordingAndReviewing>.

### Check your setup

`swiftbook doctor` checks the toolchain, Git LFS and your references, Screen Recording
permission, simulators, and that SwiftBook can read every preview. See <doc:Troubleshooting>.

## See Also

- <doc:Stories>
- <doc:Devices>

<!-- sources: README.md Sources/SwiftBookTesting Sources/SwiftBookCLI/InitCommand.swift Sources/SwiftBookCLI/ReviewCommand.swift Sources/SwiftBookCLI/DoctorCommand.swift -->
<!-- checked: d2f96ed -->
