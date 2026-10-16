# SwiftBook

**Your previews are already tests.**

SwiftBook snapshot-tests every `#Preview` in light and dark, on Mac, iPhone, iPad and Apple TV, and diffs the renders against reference images in your repository. There are no stories to write and no service to sign up for.

> [!WARNING]
> **Preview release.** SwiftBook is young and unstable. Interfaces change without notice, and there are no tagged releases yet. `Package.resolved` holds you to one revision; when you update it, expect breaking changes and re-recorded references.

## What you get

- **Stories are your previews.** Every `#Preview` and `PreviewProvider` is found at runtime, with nothing to register. If it works in Xcode's canvas, it works here.
- **Snapshot tests in one line.** `#SwiftBookTests` runs every story under `swift test`, with perceptual diffs, readable failures, and a review page for each run.
- **Every device.** `swiftbook test --device iphone` renders in SwiftBook's own simulators, several at once, as do `ipad` and `tv`.
- **A viewer to leave open.** `swiftbook view` shows every story on the Mac and redraws as your code compiles. Crashes, hangs, and build errors don't take it down.

## Installation

SwiftBook needs macOS 27 and Xcode 27, and [Git LFS](https://git-lfs.com) for reference images. Add it to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/brandonbloom/SwiftBook.git", branch: "main"),
],
targets: [
    .testTarget(
        name: "MyUITests",
        dependencies: ["MyUI", .product(name: "SwiftBookTesting", package: "SwiftBook")]),
]
```

Then add one file to the test target:

```swift
import SwiftBookTesting
import Testing

#SwiftBookTests
```

Run `swift run swiftbook init` to store references in Git LFS, then `swift test`. The first run records a reference for each preview and fails, so you can review them before committing.

## Documentation

The [documentation](https://www.brandonbloom.name/SwiftBook/docs/documentation/swiftbooktesting/) covers [getting started](https://www.brandonbloom.name/SwiftBook/docs/documentation/swiftbooktesting/gettingstarted), recording and reviewing, devices, CI, the viewer, and every command.

## Contributing

The project uses [mise](https://mise.jdx.dev). `mise run ci` runs everything that must pass before a change lands. [docs/](docs/) holds the vision, plan, and research behind the design.

## License

MIT. See [LICENSE](LICENSE).
