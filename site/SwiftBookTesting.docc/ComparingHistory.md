# Comparing Against History

See how references changed against any revision.

## Overview

`swiftbook diff` compares the references in your working tree, staged and untracked included,
with those at a revision, and lists each one added, deleted, or modified, with how many pixels
changed:

```sh
swift run swiftbook diff                    # against HEAD
swift run swiftbook diff main               # against a revision
swift run swiftbook diff --merge-base main  # against where this branch left main
```

Modified references within tolerance are listed, but don't count as changes. The command exits
with status 1 when something changed. References that were only re-encoded, with the same pixels
and metadata, as by `swiftbook compress`, are counted in one line instead of listed; JSON output
lists them as `reencoded`.

After accepting a change to Wander's weather card:

<!-- transcript: diff -->
```
$ swift run swiftbook diff
2 references changed against HEAD (cbd04c0c7):
  modified  Wander/WeatherCard/Weather card  mac.dark  5281 pixels (2.11%), max ΔE 44
  modified  Wander/WeatherCard/Weather card  mac.light  5281 pixels (2.11%), max ΔE 44
```
<!-- /transcript -->

### Seeing the images

`--open` writes and opens a page of before, after, and diff images for every changed reference.
Like the review page, it groups a change that covers the same region in three or more stories.
`--export <file>` writes the page as one file with its images inside it, to send to someone or
open on a phone:

```sh
swift run swiftbook diff main --merge-base --export changes.html
```

To keep the file small, it stores before and after images 700 pixels wide, as JPEG, and diff
images full-size. About 20 to 40 KB per changed reference is typical. `--device` and
`--appearance` narrow what's listed, exported, and counted, such as to `--device iphone
--appearance dark`.

### Output for machines

`--format json` and `--format junit` write the same comparison for scripts and CI systems.

## See Also

- <doc:StoringReferences>
- <doc:ContinuousIntegration>

<!-- sources: Sources/SwiftBookCLI/DiffCommand.swift Sources/SwiftBookCore/Git Sources/SwiftBookCore/Storage/ReferenceChanges.swift -->
<!-- checked: d835c68 -->
