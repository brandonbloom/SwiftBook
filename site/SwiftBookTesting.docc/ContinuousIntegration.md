# Running in CI

Verify references on every change, without recording new ones.

## Overview

```sh
SWIFTBOOK_RECORD=never SWIFTBOOK_CAPTURE=emulated swift test
swift run swiftbook test --device iphone --record never   # and ipad, tv, as you have references
```

- `never` turns a missing reference into a failure, instead of an unreviewed recording.
- `emulated` makes CI independent of Screen Recording permission and the screen lock. References
  must be recorded the same way; see <doc:Capture>.

### Checking out references

Check out with LFS, so references are images rather than pointers. Otherwise `swift test` and
`swiftbook test` fail once, naming the fix, rather than on every snapshot. With GitHub Actions:

```yaml
- uses: actions/checkout@v4
  with:
    lfs: true
```

### Reports

- Upload `.build/swiftbook` (or `$SWIFTBOOK_ARTIFACTS`) when a run fails. Its review page works
  as is.
- `swiftbook test --junit <file>` writes one test case per snapshot on iPhone, iPad, and Apple
  TV, and one for the Mac's whole `swift test` run.
- `swiftbook diff --format junit` reports reference changes against a revision.

### Exit status

Every `swiftbook` command exits with:

| Status | Meaning |
|---|---|
| 0 | Success |
| 1 | References or snapshots changed or failed |
| 2 | Something else went wrong |
| 64 | Usage error |

## See Also

- <doc:Capture>
- <doc:CommandLine>

<!-- sources: Sources/SwiftBookCLI Sources/SwiftBookCore/Storage Sources/SwiftBookMacros/SwiftBookTestsMacro.swift -->
<!-- checked: 901dbe2 -->
