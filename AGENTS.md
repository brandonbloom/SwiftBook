# Working on SwiftBook

## Checks

SwiftBook's checks come in two tiers, because most of what it tests needs a real Mac: a window server, Screen Recording, simulators, and the GPU its references were recorded on.

| Task | Runs | Where |
|---|---|---|
| `mise run ci` | Style, a warning-free build, the tests that need no window server, renderer, or simulator, and iOS and tvOS builds | GitHub Actions on every pull request; anywhere |
| `mise run ci-local` | `ci`, then the suites in `scripts/ui-suites`, the zoo's snapshots on every device, the viewer, and edit-to-render latency | A Mac with a logged-in, unlocked display |

`scripts/ui-suites` lists, as one `swift test --filter` pattern, the suites that `ci` skips. Add a suite to it when it renders, captures, opens windows, builds a renderer, or depends on timing that a slow, shared runner can't keep. Hosted macOS runners have three cores and no logged-in display, and there those suites render differently from the committed references.

Three cores also means three cooperative threads, and global dispatch queues share that width. Code that blocks a thread waiting for work it handed to a Swift task or `DispatchQueue.global()` deadlocks there once every thread is waiting, though it passes on a many-core Mac. Give such work a `Thread` of its own, as `Shell.run` does.

## Before landing

- Run `mise run ci`. It must pass.
- Run `mise run ci-local` when a change touches rendering, capture, simulators, the renderer protocol, or the viewer. Skip it for changes that can't affect them, such as docs or pure logic covered by `ci`.
- Say which you did in the pull request or the commit message: `ci-local: passed at <commit>`, or `ci-local: skipped (<reason>)`. That's an attestation, not a gate.

## Before tagging a release

1. Start from a clean checkout of the commit to tag, with Git LFS objects pulled.
2. Run `mise run ci-local` and confirm it ends with `ci-local: ok`.
3. Run `mise run site-build` and look over the site with `mise run site-preview`.
4. Run `mise run site-stale`, and recheck any article it lists.
5. Tag, and note the `ci-local` run in the release notes.
