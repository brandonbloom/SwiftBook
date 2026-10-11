# Backlog

Feedback and findings not yet planned. Remove an item when it lands or is declined; move it into [plan.md](plan.md) when it's scheduled.

## From Fulbloom's adoption

Fulbloom has 632 references (about 300 on iPhone), checked by many agents running CI in parallel on one Mac.

- **Liquid Glass noise above the noise floor.** Glass tab bars, search fields, and toolbars differ slightly between runs. One tab bar's glass differed by 17 pixels. One search field differed by 5,725 pixels (0.18%) at a largest ΔE of 3. Both exceed the 10-pixel, ΔE 3 noise floor. Ideas:
  - A looser tolerance inside known glass materials, masked by region.
  - Glass rendered as a deterministic material in snapshots.
  - The story-level `.tolerance` and subview `.masked()` options in [ideas/story-metadata.md](ideas/story-metadata.md).
- **Retry failures.** A failure in a preview the change didn't touch still blocks landing. `--retry-failed N` would re-render only the failures and pass if a retry matches. Report retried-then-matched separately, so flakes stay visible.
- **Throughput as suites grow.** Full Mac and iPhone runs take minutes and grow linearly. Ideas:
  - Render only previews whose source files (or their dependencies) changed since their references were recorded, with a full run nightly. The viewer's source-changed pass is a start.
  - Shard across the simulator pool.
- **Date-dependent previews.** A compact `DatePicker`'s width changed at midnight. Ideas: a fixed clock in snapshot mode, or a lint for `Date.now` in previews.
- **Read the accent color from the app target.** `SwiftBookConfiguration.tint` (`project-tint`) sets it by hand. SwiftBook could instead find the app target that uses the package and read its `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` color.
