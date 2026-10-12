# Backlog

Feedback and findings not yet planned. Remove an item when it lands or is declined; move it into [plan.md](plan.md) when it's scheduled.

## From Fulbloom's adoption

Fulbloom has 632 references (about 300 on iPhone), checked by many agents running CI in parallel on one Mac.

- **Retry failures.** A failure in a preview the change didn't touch still blocks landing. `--retry-failed N` would re-render only the failures and pass if a retry matches. Report retried-then-matched separately, so flakes stay visible.
- **Throughput as suites grow.** Full Mac and iPhone runs take minutes and grow linearly. Simulated devices now spread across the pool (`parallel-devices`). Ideas:
  - Render only previews whose source files (or their dependencies) changed since their references were recorded, with a full run nightly. The viewer's source-changed pass is a start.
  - Parallel Mac rendering under `swift test` (84 s for Fulbloom). Renders are serialized because they set process-wide state, such as the time zone.
  - `--shard i/n` to split a run across CI machines.
  - Give extra simulators back when another run is waiting, if one run starves the others.
- **A machine-wide pool size.** Each run reads `SWIFTBOOK_SIMULATORS` for itself, so runs with different values disagree on the pool's size, and the larger one can use simulators beyond the others' pool. Documented for now; recording the size in the shared cache directory would enforce one.
- **Date-dependent previews.** A compact `DatePicker`'s width changed at midnight. Ideas: a fixed clock in snapshot mode, or a lint for `Date.now` in previews.
- **Read the accent color from the app target.** `SwiftBookConfiguration.tint` (`project-tint`) sets it by hand. SwiftBook could instead find the app target that uses the package and read its `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` color.
