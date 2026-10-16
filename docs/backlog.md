# Backlog

Feedback and findings not yet planned. Remove an item when it lands or is declined; move it into [plan.md](plan.md) when it's scheduled.

## From the first adoption

The first adopter has 632 references (about 300 on iPhone), checked by many agents running CI in parallel on one Mac.

- **Flaky failures.** A failure in a preview the change didn't touch still blocks landing. Brandon would rather discourage flaky tests and give tools to fix them than retry them: retries also slow down runs that genuinely break many snapshots. `swiftbook flakes` (`flake-finder`) finds them. To discuss:
  - Diagnose failures without passing them: when few snapshots fail, re-render each once or twice to label it "consistent change" or "flaky", pointing to `swiftbook flakes`.
  - Guard new references: render a missing reference twice before recording it, and refuse if the renders differ.
  - Report renderer timeouts and crashes as infrastructure failures, separate from mismatches.
  - `swiftbook flakes` under load: a CI failure under several parallel CI runs didn't reproduce in 10 sequential runs. Rendering across the pool at once, or under artificial CPU load, might surface timing flakes.
  - `swiftbook flakes --from-ci <log>`, taking the failing stories from a test log.
- **Throughput as suites grow.** Full Mac and iPhone runs take minutes and grow linearly. Simulated devices now spread across the pool (`parallel-devices`). Ideas:
  - Render only previews whose source files (or their dependencies) changed since their references were recorded, with a full run nightly. The viewer's source-changed pass is a start.
  - Parallel Mac rendering under `swift test` (84 s for the first adopter). Renders are serialized because they set process-wide state, such as the time zone.
  - `--shard i/n` to split a run across CI machines.
  - Give extra simulators back when another run is waiting, if one run starves the others.
  - Recruit fewer simulators when the machine is already loaded. The first adopter's CI ran a Mac `swift test` next to an iPhone run that recruited 3–4 simulators, with load averages over 100; slow captures failed Mac snapshots as "still changing" after a single capture, until renders took at least 5 captures. `--jobs` caps it by hand.
- **A machine-wide pool size.** Each run reads `SWIFTBOOK_SIMULATORS` for itself, so runs with different values disagree on the pool's size, and the larger one can use simulators beyond the others' pool. Documented for now; recording the size in the shared cache directory would enforce one.
- **Date-dependent previews.** A compact `DatePicker`'s width changed at midnight. Ideas: a fixed clock in snapshot mode, or a lint for `Date.now` in previews.
- **Read the accent color from the app target.** `SwiftBookConfiguration.tint` (`project-tint`) sets it by hand. SwiftBook could instead find the app target that uses the package and read its `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` color.
