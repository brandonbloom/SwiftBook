# Previews Are Stories

How SwiftBook finds your previews and names them.

## Overview

A *story* is one preview: one `#Preview`, one child of a `PreviewProvider`, or one argument of a
`#Preview(arguments:)`. SwiftBook finds them at runtime, from the conformance records that
`#Preview` and `PreviewProvider` compile into your binary, so there's nothing to register. Any
preview that works in Xcode's canvas works in SwiftBook.

### Story IDs

A story's ID is `Module/Group/Name`:

- **Module** is the Swift module the preview is in.
- **Group** is the name of its source file, without the extension, or of its `PreviewProvider`
  type.
- **Name** is the preview's name. Unnamed previews take the group's name, and repeated names get
  " 2", " 3", and so on. Names count as repeated when their references would share a file:
  `Dark` and `dark`, or `Row:` and `Row?`, since `:` and `?` both become `_` in file names.

So in `MyUI/Card.swift`:

```swift
#Preview { Card(title: "Unnamed") }           // MyUI/Card/Card
#Preview { Card(title: "Also unnamed") }      // MyUI/Card/Card 2
#Preview("Card") { Card(title: "Hello") }     // MyUI/Card/Card 3
```

List them with `swiftbook list`. Here it is on Wander, the sample app these docs use:

<!-- transcript: list -->
```
$ swift run swiftbook list
Wander/Status/Status / Confirmed
Wander/Status/Status / Waitlisted
Wander/Status/Status / Cancelled
Wander/Trips/Upcoming trips
Wander/WeatherCard/Weather card
Wander/Welcome/Welcome
```
<!-- /transcript -->

`--check` also builds each story and reports any SwiftBook can't read.

### Parameterized previews

Each argument of a `#Preview(arguments:)` is its own story, named `<preview> / <argument>`
after the argument's description:

```swift
#Preview("Status", traits: .sizeThatFitsLayout, arguments: StatusBadge.Status.allCases) { status in
    StatusBadge(status).padding()
}
```

@Row {
    @Column {
        @Image(source: status-confirmed, alt: "The Confirmed badge.")

        `Status / Confirmed`
    }
    @Column {
        @Image(source: status-waitlisted, alt: "The Waitlisted badge.")

        `Status / Waitlisted`
    }
    @Column {
        @Image(source: status-cancelled, alt: "The Cancelled badge.")

        `Status / Cancelled`
    }
}

### Traits and modifiers

Layout traits work as in Xcode: `.sizeThatFitsLayout` measures the view, `.fixedLayout` sets the
canvas, and `PreviewModifier`s are applied, including shared context. `@Previewable` state works
too.

### When a preview can't be read

SwiftBook reads each preview's name, traits, and body through Xcode's preview types. If a future
Xcode changes their shape, SwiftBook fails loudly and names your macOS, SwiftUI, and
DeveloperToolsSupport versions, rather than rendering something wrong.

## See Also

- <doc:PreviewsThatSnapshotWell>

<!-- sources: Sources/SwiftBookCore/Discovery Sources/SwiftBookCore/Adapter Sources/SwiftBookCLI/ListCommand.swift -->
<!-- checked: 9aa59e3 -->
