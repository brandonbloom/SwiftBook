# Testing on iPhone, iPad, and Apple TV

Render the same stories on every device.

## Overview

`swift test` renders stories on the Mac. `swiftbook test` renders them on the Mac, iPhone, iPad,
and Apple TV, light and dark, and compares each with its reference:

```sh
swift run swiftbook test --device iphone --device ipad --device tv
```

With no `--device`, it tests every device that has references. `--device` takes `mac`,
`iphone`, `ipad`, or `tv`, or a platform: `macos`, `ios`, or `tvos`.

@TabNavigator {
    @Tab("iPhone") {
        @Image(source: material-iphone, alt: "A material panel over a gradient, on iPhone.")
    }
    @Tab("iPad") {
        @Image(source: material-ipad, alt: "A material panel over a gradient, on iPad.")
    }
    @Tab("Mac") {
        @Image(source: material-mac, alt: "A material panel over a gradient, on the Mac.")
    }
    @Tab("Apple TV") {
        @Image(source: material-tv, alt: "A material panel over a gradient, on Apple TV.")
    }
}

### SwiftBook's simulators

On iPhone, iPad, and Apple TV, stories render in an app that runs in SwiftBook's own simulator
for that device, which it creates on first use and reuses after:

| Device | Simulator |
|---|---|
| iPhone | iPhone 17 Pro |
| iPad | 11-inch iPad Pro |
| Apple TV | Apple TV 4K |

Your own simulators are left alone. The app is built from your package's library products, so a
story's resources come along.

### Rendering stories to files

`swiftbook render` writes PNGs laid out like references, without comparing them:

```sh
swift run swiftbook render MyUI/Card/Card --device iphone -o /tmp/renders
```

### Limitations

- On iPhone, iPad, and Apple TV, `swiftbook test` checks light and dark only, and doesn't apply
  `#SwiftBookTests`' `excluding:`.

## See Also

- <doc:CommandLine>
- <doc:ContinuousIntegration>
