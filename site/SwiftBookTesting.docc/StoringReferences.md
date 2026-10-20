# Storing References in Git

Where references live, and how to keep them in Git LFS.

## Overview

References are PNGs in your repository, one per story and variant:

```
Snapshots/<Module>/<Group>/<Story>/<device>.<appearance>.png
```

A variant that sets a dynamic type size, right-to-left layout, or a locale adds it to the name, as
in `mac.light.rtl.png`.

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

GitHub's LFS works.

In a clone or worktree where Git LFS isn't set up, or its files weren't pulled, references are
small text pointers rather than images. SwiftBook checks before comparing anything: `swift test`
fails one test, "References are images", and skips the snapshots, and `swiftbook test` stops with
the same message. Both count the pointers and give the fix, `git lfs pull` (after
`git lfs install`, if Git LFS isn't set up). No record mode overwrites a pointer.
`swiftbook doctor` reports pointers too.

### Pruning

When you rename or delete a preview, its references are left behind. Delete them with:

```sh
swift run swiftbook prune --dry-run   # see what would go
swift run swiftbook prune
```

Only modules the renderer links are pruned, so references for code SwiftBook can't see are kept.

### Size

References are compact PNGs: each row is filtered the way that compresses best, the image is
deflated at zlib's highest level, and an opaque image is stored without an alpha channel. That
keeps the Git LFS history small, because every changed reference adds a new copy of the file.

References recorded before SwiftBook 0.3 were stored less compactly. Shrink them once with:

```sh
swift run swiftbook compress --dry-run   # see how much they'd shrink
swift run swiftbook compress
```

It renders nothing. It checks that each new file decodes to the same pixels, with the same
metadata, before replacing it, so the commit needs no review. Running it again changes nothing.
Copies already in your Git LFS history stay there.

Re-recording with `all` rewrites only references whose pixels differ, so upgrading SwiftBook or
macOS doesn't rewrite every reference.

## See Also

- <doc:ComparingHistory>

<!-- sources: Sources/SwiftBookCore/Storage Sources/SwiftBookCore/Rendering/PNGCompaction.swift Sources/SwiftBookCLI/CompressCommand.swift Sources/SwiftBookCLI/InitCommand.swift Sources/SwiftBookCLI/PruneCommand.swift Sources/SwiftBookCLI/DoctorCommand.swift Sources/SwiftBookCLI/TestCommand.swift Sources/SwiftBookMacros/SwiftBookTestsMacro.swift -->
<!-- checked: 00128c9 -->
