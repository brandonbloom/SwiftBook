# Comparing Against History

See how references changed against any revision.

## Overview

`swiftbook diff` compares the references in your working tree, staged and untracked included,
with those at a revision, and lists each one added, deleted, or modified, with how many pixels
changed:

```sh
swift run swiftbook diff               # against HEAD
swift run swiftbook diff main          # against a revision
swift run swiftbook diff --merge-base  # against where this branch left the default branch
```

Modified references within tolerance are listed, but don't count as changes. The command exits
with status 1 when something changed.

<!-- TODO(site): sample `swiftbook diff` output. -->

### Seeing the images

`--open` writes and opens a page of before, after, and diff images for every changed reference.

### Output for machines

`--format json` and `--format junit` write the same comparison for scripts and CI systems.

## See Also

- <doc:StoringReferences>
- <doc:ContinuousIntegration>
