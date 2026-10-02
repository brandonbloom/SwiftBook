# Story metadata: ideas

> **Status: undecided.** These are brainstormed options to revisit once the basics work. Nothing here is committed. The mechanism (SwiftUI preferences, ignored by Xcode's canvas) is decided in [vision.md](../vision.md#opting-in-and-configuring).

## Candidate options

Priority is a first guess: P0 for the first version, P1 soon after, P2 later.

| Priority | Option | Level | Use case |
|---|---|---|---|
| P0 | `.variants(.adding(.rightToLeft))` / `.removing(.dark)` / `.only(...)` | story | A text-heavy form adds RTL. A video player that is always dark drops light. |
| P0 | `.tolerance(deltaE: 3, pixels: 0.001)` | story | Gradients, shadows, blur and materials that render noisily. Prevents loosening the global tolerance. |
| P0 | `.snapshot(.skip("reason"))` | story | Useful in the viewer but non-deterministic: live clocks, random data, animation demos. The reason appears in the viewer and in test output. |
| P1 | `.masked()` | subview | Relative timestamps, caret blink, version strings. Its frame is reported via anchor preferences and excluded from diffs. |
| P1 | `.swiftBookReady(isLoaded)` | subview | Views that load in `.task`, `AsyncImage`, or other async state. The renderer waits until every ready flag is true, with a timeout. |
| P1 | `.platforms(.macOS, .iOS)` | story | A shared view that makes no sense on tvOS. Avoids unwanted references. |
| P1 | `.expandScrollViews()` | story | Long lists and settings pages, captured in full. |
| P1 | `.group("Onboarding")`, `.tags(.wip, .designReview)` | story | Sidebar organization across files (for example, user flows). Filters, and CLI selection (`--tag`). |
| P2 | `.notes("…markdown…")` | story | Design intent and links shown in the viewer. |
| P2 | `.states(.focused, .pressed, .hovered)` | story | Interaction states. Critical on tvOS, where focus appearance is the design. Hard: needs a way to set focus or press programmatically on each platform. |
| P2 | `.accessibilityAudit(.skip / .only([...]))` | story | Only if accessibility audits are added. |

## Composition sketch

There are two levels: package (the opt-in declaration), then story. Nothing at file level, because Swift has no clean place to attach it.

| Kind of option | Rule |
|---|---|
| Variants | Operations (add, remove, only) applied to the package default set. |
| Scalars (tolerance, skip) | The story value overrides the package value. |
| Lists (tags, masks) | Values accumulate. |
| Conflicts | One story setting the same scalar twice is a hard error, not last-wins. |

## Observations

- **Device** (iPhone SE vs. Pro Max vs. iPad, i.e. size classes) is probably as important as dynamic type for iOS. It belongs alongside platform as a dimension.
- Metadata exists at two levels: story-wide, and attached to a specific subview (masks, readiness). Both travel through SwiftUI preferences.
