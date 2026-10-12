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

### Running several at once

A simulator shows one app at a time and suspends the rest, so two runs can't share one. Each run
leases a simulator of its own from a pool, such as `SwiftBook iPhone 17 Pro #2` beside the first.
Runs beyond the pool's size wait their turn, and say so; waiting never counts as a timeout.

- **Size.** As many simulators per device as fit in half the Mac's memory, at 4 GB each, but at
  most one per two performance cores. Set `SWIFTBOOK_SIMULATORS` to choose. Each run reads it
  for itself, so give every run on the Mac the same value: a run with a larger one can use
  simulators beyond the others' pool.
- **Memory.** The first simulator stays booted. An extra one shuts down once it has been idle for
  5 minutes, so overlapping runs reuse it while it's warm.
- **Leases end with their run**, even one that crashes.

One run also spreads its snapshots across several simulators when they're free. It starts on
one, then takes more without waiting for them, while enough snapshots remain to repay starting
another: a few seconds for a booted simulator, about 15 more for a cold one. All of them work
through one queue of snapshots, and the results come together in one report. `--jobs` caps how
many simulators a run uses per device, within the pool, so a value above the pool's size has no
effect; `--jobs 1` keeps it to one.

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
<!-- checked: c60ae75 -->
