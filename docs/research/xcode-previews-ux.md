# Xcode's preview canvas: a tour of the zoo

**Date:** 2026-10-02. Xcode 27.0, iOS 27 simulator runtime, macOS 27. No tvOS runtime was installed.

**Method:** I used computer use to drive Xcode's preview canvas over every file in [the zoo](../../Fixtures/PreviewZoo/Sources/PreviewZoo). To see how live edits and build failures look, I made one temporary text edit and one temporary compile error on disk, then reverted both.

Screenshots are in [xcode-previews-ux/](xcode-previews-ux/).

## The canvas, control by control

- **Preview tabs.** A strip across the top shows one tab per preview in the current file, and only that file. Each file remembers which tab was last selected.
  - Tabs are labeled with the display name.
  - Unnamed previews take the **file name**, and Xcode adds **"Line N"** to tell apart names that collide. In `Card.swift`, the two unnamed previews and the one named "Card" all collide: "Card Line 30", "Card Line 34", "Card Line 38". Duplicate names in `EdgeCases.swift` became "Duplicate Line 16" and "Duplicate Line 20". See [unnamed-tab-names.jpg](xcode-previews-ux/unnamed-tab-names.jpg).
  - A `PreviewProvider` contributes one tab per child view. A child without `.previewDisplayName` is labeled with the file name plus a line number ("Legacy Line 15").
  - A failed preview's tab turns red. See [build-failure.jpg](xcode-previews-ux/build-failure.jpg).
- **Bottom bar, left side:**
  - **Live** (play button): an interactive, running preview.
  - **Selectable** (crosshair): click an element in the preview to select its source; see [selectable-mode.jpg](xcode-previews-ux/selectable-mode.jpg).
  - **Variants** (grid button): a single-choice menu.
  - Live and selectable modes show one preview with a zoom percentage. Variants mode shows a grid.
- **Variants menu.** Exactly one dimension at a time is spread into a labeled grid.
  - **iPhone:** Color Scheme, Contrast, Control Borders, Orientation, Dynamic Type. Dynamic Type gives 12 cells, X Small through accessibility sizes. See [variants-dynamic-type.jpg](xcode-previews-ux/variants-dynamic-type.jpg).
  - **Mac:** Color Scheme, Contrast, Control Borders only. The menu depends on the platform.
- **Device Settings** (toggle button, bottom right): one switch per dimension (Color Scheme, Contrast, Control Borders, Orientation, …). Turning one on reveals a value picker that applies to **every cell**.
  - For example, Color Scheme set to Dark *together with* Dynamic Type variants gives a Dynamic Type grid that is entirely dark. See [device-settings-dark-plus-dynamic-type.jpg](xcode-previews-ux/device-settings-dark-plus-dynamic-type.jpg).
- **Device picker** (bottom right):
  - The menu lists Automatic, Recent, iPhone, iPad 11-inch and 13-inch, My Mac, My Mac (Mac Catalyst), and More… (specific iPhone, iPad and Mac models). See [device-picker.jpg](xcode-previews-ux/device-picker.jpg).
  - **Platform is chosen here.** Switching from iPhone to My Mac re-renders the whole canvas as macOS.
- **Export Screenshot** (camera button, bottom right).
- **`#Preview(arguments:)`** takes over the grid: one cell per argument, labeled with the argument's value. The color-scheme variants disappear. See [arguments-grid.jpg](xcode-previews-ux/arguments-grid.jpg).

## How previews render

- **iOS** previews sit in a device frame for `.defaultLayout`. `.fixedLayout` and `.sizeThatFitsLayout` show a bordered box.
- **macOS** previews render **inside window chrome**: traffic lights, with the preview's name or "Xcode Previews" as the window title. See [macos-window-chrome.jpg](xcode-previews-ux/macos-window-chrome.jpg).
  - Variant cells scale the content up to fill the cell.
  - A `.fixedLayout(width: 200, height: 80)` badge rendered in a tiny window whose traffic lights overlap the content. See [macos-fixed-layout.jpg](xcode-previews-ux/macos-fixed-layout.jpg).
  - In Selectable mode on macOS, the card's content went blank. Only the window outline remained.
- **Hazards render correctly**, `List` and materials included, because Xcode renders in a real process with real windows.
- **`PreviewModifier` shared context** worked on both previews that use it.

## Live updates and errors

- **A literal edit made on disk** (outside Xcode's editor) appeared in the live canvas within about 4 seconds.
- **A compile error** clears the entire canvas. It shows a "Failed to build Card.swift" banner with info, diagnostics and retry buttons. **No last good render is kept**, and every preview in the file is lost, not just the broken one.
- **A crash** shows a "Preview crashed: XCPreviewAgent crashed" banner, with an info button pointing to `~/Library/Logs/DiagnosticReports` and a "Show Crash Logs" button. See [crash-banner.jpg](xcode-previews-ux/crash-banner.jpg).
  - Xcode itself crashed on `Legacy.swift` (macOS, light variant) with an unconditional cast failure in `DebugReplaceableViewChild.updateValue()`. That is the 26-SDK hot-swap machinery, not zoo code.
  - The dark variant of the same preview rendered. **Even Xcode's own preview host is fragile with legacy previews.**

## What this means for SwiftBook

These are proposals; none are decided.

1. **The toolbar model checks out.** Xcode's split is our split:
   - (A)+(B): **Variants** spreads one dimension into a grid.
   - (C): **Device Settings** pins the value of each other dimension.

   Xcode lacks two of our comparison modes: 2-up comparisons beyond a grid, and revision as a dimension. Proposal: borrow Xcode's dimension vocabulary and its per-platform availability.
2. **Add Contrast (increased contrast) and Control Borders (button shapes) as dimensions.** Xcode treats them as first class, and they're cheap environment overrides.
3. **Device is the dimension, and platform is derived from it.** Xcode's picker merges iPhone, iPad, Mac and Mac Catalyst into one choice. Proposal: treat "device" (iPhone, iPad, Mac, Mac Catalyst, TV) as the dimension that determines platform, rather than two separate dimensions. Mac Catalyst then becomes a platform value we haven't planned for.
4. **`arguments:` previews.** Xcode treats the arguments as a grid. Proposal: each argument is its own story (for example, "Badge arguments / SALE") for identity and snapshots, and the viewer lays a preview's argument stories out as a group.
5. **How unnamed previews are named.** Xcode uses the file name, then "Line N" to disambiguate. That label changes whenever code moves. Proposal: keep our ordinal numbering, which survives code moves, but name unnamed previews after the file to match Xcode: `Card`, `Card 2`, `Card 3` instead of `Preview`, `Preview 2`. `StoryID.unnamed` would change.
6. **Keeping the last good render is a real differentiator.** Xcode loses every preview in a file on any build error. Our per-cell error states should borrow Xcode's crash affordances: a diagnostics summary, retry, and a link to the crash log.
7. **Window chrome on macOS.** Xcode wraps macOS previews in a window. Proposal: our references stay content-only (no chrome) so they're stable and diffable. The viewer could optionally draw a window frame around the image.
8. **Jump to source.** Selectable mode maps elements back to source using Xcode internals we don't have. At the story level, we can offer "Reveal in Xcode" at the preview's file and line. Proposal: a small, cheap viewer feature.
9. **Treat `DebugReplaceableView` as an adapter risk.** Debug builds on the 26+ SDKs erase opaque view types into `DebugReplaceableView`, and Xcode's own handling of it crashed. The adapter and renderer tests in `preview-adapter` should cover `PreviewProvider` in Debug builds specifically.
10. **Unchanged:** Xcode's canvas is scoped to one file and has no cross-file browsing, history, or diffing. These remain SwiftBook's core.
