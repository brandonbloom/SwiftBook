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
- **Group** is the name of its source file, without the extension.
- **Name** is the preview's name. Unnamed previews take the group's name, and repeated names get
  " 2", " 3", and so on.

So in `MyUI/Card.swift`:

```swift
#Preview { Card(title: "Unnamed") }           // MyUI/Card/Card
#Preview { Card(title: "Also unnamed") }      // MyUI/Card/Card 2
#Preview("Card") { Card(title: "Hello") }     // MyUI/Card/Card 3
```

List them with:

```sh
swift run swiftbook list
```

`--check` also builds each story and reports any SwiftBook can't read.

### Parameterized previews

Each argument of a `#Preview(arguments:)` is its own story, named `<preview> / <argument>`
after the argument's description:

```swift
#Preview("Badge arguments", traits: .sizeThatFitsLayout, arguments: ["NEW", "SALE", "SOLD OUT"]) {
    text in
    Badge(text)
}
```

@Row {
    @Column {
        @Image(source: arguments-new, alt: "The NEW badge.")

        `Badge arguments / NEW`
    }
    @Column {
        @Image(source: arguments-sale, alt: "The SALE badge.")

        `Badge arguments / SALE`
    }
}

### Traits and modifiers

Layout traits work as in Xcode: `.sizeThatFitsLayout` measures the view, `.fixedLayout` sets the
canvas, and `PreviewModifier`s are applied, including shared context. `@Previewable` state works
too.

### When a preview can't be read

SwiftBook reads each preview's name, traits, and body through Xcode's preview types. If a future
Xcode changes their shape, SwiftBook fails loudly and names your Xcode version, rather than
rendering something wrong.

## See Also

- <doc:PreviewsThatSnapshotWell>
