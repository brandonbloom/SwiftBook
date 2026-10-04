# Storing References in Git

Where references live, and how to keep them in Git LFS.

## Overview

References are PNGs in your repository, one per story and variant:

```
Snapshots/<Module>/<Group>/<Story>/<device>.<appearance>.png
```

The `Snapshots` directory sits in the package or Xcode project that contains the test. Each PNG
records the rendering environment it was made in, so a failure can point out an OS or capture
change.

### Git LFS

Store references in [Git LFS](https://git-lfs.com) so they don't bloat your history:

```sh
swift run swiftbook init
```

This adds the rule to `.gitattributes`, and is safe to run again:

```
**/Snapshots/**/*.png filter=lfs diff=lfs merge=lfs -text
```

GitHub's LFS works. `swiftbook doctor` reports references that are unpulled LFS pointers.

### Pruning

When you rename or delete a preview, its references are left behind. Delete them with:

```sh
swift run swiftbook prune --dry-run   # see what would go
swift run swiftbook prune
```

Only modules the renderer links are pruned, so references for code SwiftBook can't see are kept.

## See Also

- <doc:ComparingHistory>
