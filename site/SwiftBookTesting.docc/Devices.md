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
        @Image(source: welcome-iphone, alt: "Wander's welcome screen on iPhone.")
    }
    @Tab("iPad") {
        @Image(source: welcome-ipad, alt: "Wander's welcome screen on iPad.")
    }
    @Tab("Mac") {
        @Image(source: welcome-mac, alt: "Wander's welcome screen on the Mac.")
    }
    @Tab("Apple TV") {
        @Image(source: welcome-tv, alt: "Wander's welcome screen on Apple TV.")
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
swift run swiftbook render Wander/Welcome/Welcome --device iphone -o /tmp/renders
```

### Limitations

- On iPhone, iPad, and Apple TV, `swiftbook test` checks light and dark only, and doesn't apply
  `#SwiftBookTests`' `excluding:`.

## See Also

- <doc:CommandLine>
- <doc:ContinuousIntegration>

<!-- sources: Sources/SwiftBookCLI/TestCommand.swift Sources/SwiftBookCLI/RenderCommand.swift Sources/SwiftBookCore/Renderer Sources/SwiftBookCore/Rendering/Device.swift Sources/SwiftBookCore/Rendering/UIKitRenderer.swift -->
<!-- checked: 5656084 -->
