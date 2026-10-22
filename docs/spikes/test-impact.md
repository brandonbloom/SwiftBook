# Spike: skipping snapshots a change can't affect

**Date:** 2026-10-21.
**Environment:** Xcode 27.0, Swift 6.4, macOS 27.2. Mac only, on the PreviewZoo (37 stories, 74 snapshots).

**Question:** can `swiftbook test` safely skip the snapshots an edit can't affect, by recording what code each render runs, and can that machinery live in a package other test tools could use?

**Answer:**
- **Yes, on the zoo.** In seven kinds of edit, every snapshot that changed was selected. That held only after three gaps found along the way were closed (see [Gaps](#gaps-found-and-closed)).
- **It costs almost nothing.** The instrumented renderer renders as fast as the plain one. Indexing the build takes 150 ms, and selecting takes 44 ms.
- **The saving is the render time of the skipped snapshots.** A run still pays its fixed cost: about 5 s on the zoo to build, start a renderer, and list the stories.
- **The machinery is generic.** The package, now [SwiftImpact](https://github.com/brandonbloom/SwiftImpact), has a probe that the process under test links, and an index and ledger that the harness uses. SwiftBook's part is about 150 lines.

## How it works

1. **Instrument the renderer.** `RendererHost` builds with `-Xswiftc -profile-generate`. That adds a counter per code region, and a 64-byte record per function holding its name hash and a pointer to its counters.
2. **Probe each render.** `ImpactProbe` finds the `__llvm_prf_data` and `__llvm_prf_cnts` sections with `getsectiondata`. It zeroes the counters before a render, and afterwards returns the name hashes of the functions whose counters moved. It checks the record layout against the counters section before trusting it. There is no LLVM runtime API and no profile file.
3. **Map functions to source files.** SwiftPM compiles each source file to its own object under `.build/out/Intermediates.noindex`, even though it links each module through one prelinked object. Each per-file object carries the `__llvm_prf_data` records of its own functions, so name hash → object needs no symbols or linker map. Every one of the renderer's 772 instrumented functions maps to exactly one object.
4. **Fingerprint objects, not sources.** An object's fingerprint hashes every section except `__DWARF`, with relocations naming their symbols rather than indexing them.
   - Recompiling an unchanged file reproduces it byte for byte.
   - When an edit changes what a call resolves to, as an overload in another file can, Swift's incremental build recompiles the caller and its object changes. Source diffs would miss that; this gets it from the compiler.
5. **Select.** After a run, each snapshot that verified is recorded in `.build/…/ledger.json`: the objects it ran and their fingerprints, the types those objects use, and the build's conformances. A snapshot that failed is dropped, so it keeps rendering until it's accepted.
   - `swiftbook test --changed` renders the snapshots the ledger lacks, and those where an object in the footprint changed or a conformance for one of its types came or went.

## Results

Each edit was applied alone to the zoo. A full run gave the truth; selection used the footprints recorded before the edit.

| Edit | Changed in a full run | Selected | Escapes |
|---|---|---|---|
| A literal in `Card.body` | 16 | 16 | 0 |
| A comment that shifts `Card.swift`'s lines | 0 | 16 | 0 |
| A more specific `Text.init(_: String)` overload in `Chrome.swift` | 36 | 70 | 0 |
| A string inside a `#Preview` body in `Hazards.swift` | 2 | 16 | 0 |
| A lazily initialized global in another file, read by `Card` | 16 | 16 | 0 |
| A `CustomStringConvertible` conformance in another file, found through `String(describing: x as Any)` | 16 | 44 | 0 |
| A new view in a new file | 0 | 0 | 0 |

The global and the conformance came from scaffolding added to the zoo for the spike: `Globals.swift`, and a use of both in `Card`. The scaffolding is not committed.

Selection over-approximates in three ways:
- **By file:** `Hazards.swift`'s eight stories go together.
- **By compiler output:** after the overload, objects the compiler rebuilt changed even where the pixels didn't.
- **Line shifts:** they change an object's code, because `#Preview`'s generated type names and `#line` carry the source location.

## Results on FulbloomFinance

FulbloomFinance has 504–512 Mac snapshots, nearly all in one target, FBFUI. I replayed its 16 first-parent commits from `5b70c736` to `0340169b` (2026-10-20 and 21) in a private clone, on the spike's SwiftBook.
- **References were the spike's own renders.** They were recorded in full at the base and accepted after each step, so no step compared renders across SwiftBook versions.
- **Each commit's non-snapshot files were brought in, then three runs:**
  1. `--changed`, the selection;
  2. a full run with `--record never`, the truth;
  3. `--changed --record changed`, accepting the full run's failures.
- **The machine was loaded by other sessions throughout** (load averages of 15–300), so the times are rough.

| Commit | What it changed | Selected | Changed | Escapes | `--changed`: wall (build) | Full: wall (build) |
|---|---|---|---|---|---|---|
| `5b70c736` | Document viewer; `Brand`, `Chrome`, 15 more views | 504 | 0 | 0 | 50 s (15) | 53 s (5) |
| `06acd07d` | App targets only | 0 | 0 | 0 | 11 s (5) | 104 s (7) |
| `28cd0b6e` | `testing/iphone.md` | 0 | 1* | 0 | 20 s (9) | 62 s (8) |
| `92928088` | SwiftBook 0.6.0 pin (overridden here) | 0 | 0 | 0 | 12 s (6) | 56 s (7) |
| `9eb51002` | `DocumentReader`, `DocumentViewer` | 146 | 0 | 0 | 60 s (39) | 86 s (8) |
| `8077a785` | Global search: FBFKit, `Chrome`, 6 views | 150 | 10 | 0 | 50 s (30) | 47 s (6) |
| `21c601c6`–`15541a52` (8 commits) | SwiftBook pins, scripts, docs | 0 each | 0 | 0 | 9–13 s (5–8) | 34–60 s (5–7) |
| `bce38774` | `fbf:` link scheme, 7 files | 130 | 0 | 0 | 54 s (26) | 77 s (6) |
| `0340169b` | `DeepLink`, `Handoff` | 70 | 0 | 0 | 86 s (27) | 92 s (14) |

\* A flake, not an escape. The commit changed no code; the snapshot failed under a load of about 179, then matched its old reference when re-rendered.

- **No escapes.** Everything that changed was selected: 10 snapshots (8 new) in `8077a785`.
- **Render time fell by 71%.** Over the 16 commits, `--changed` spent 224 s rendering against 778 s for full runs, not counting builds.
  - Every commit that changed no FBF code selected nothing, and its run took about 10 s against 35–100 s.
  - `--changed`'s build includes the commit's compile. The full run after it built warm, so wall times understate the saving.
- **Selection is conservative where it fans out:**
  - `Brand.o` is in all 504 footprints, and FBFKit's `Money`, `LocalDate`, and `Household` in about 490.
  - A footprint holds a median of 66 objects (20–156).
  - `bce38774`, a string rename, selected 130 and changed none.
  - `9eb51002` selected 146 snapshots for a new `DocumentReader.DownloadStatus: Equatable`, because types are matched by prefix and a nested type matches its parent's.
  - Line shifts in `Chrome.swift` rename its `#Preview` registry types, so they register as changed conformances. Each selected the 64 units of `Chrome` and `LedgerBrowser`.
- **Not measured:** iPhone, and FBF's own runs with its scripts and simulator pool.

## By file or by function

Studies of regression test selection in Java found per-class selection beat per-method selection overall: finer dependencies cost more to collect than the tests they skip save. That doesn't carry over here:
- **Collecting is free.** The counters already record each function.
- **Renders are expensive.** Each snapshot costs far more than a unit test, so every one skipped matters more.
- **The cost is elsewhere.** Fingerprinting a Swift function, not collecting its execution, is the expensive part.

So I measured. [funcfp.py](test-impact/funcfp.py) fingerprints each instrumented function in a Mach-O object:
- **Function boundaries:** the code between symbols, which is how the linker splits it under `MH_SUBSECTIONS_VIA_SYMBOLS`.
- **What a function's fingerprint covers:** its bytes and its relocations, each naming its target:
  - external symbols by name;
  - C strings by contents;
  - uninstrumented helpers (thunks, outlined code, macro-generated closures) by their own fingerprint, recursively;
  - other data by its bytes.
- **Mapping records to functions:** each profile record's counter relocation names `___profc_<PGO name>`, and the PGO name is the mangled name, prefixed by `<path>:` when the function is file-local.

[levels.py](test-impact/levels.py) replays selection over captured builds and recordings. It compares five rules:

| Rule | A story is selected when |
|---|---|
| F0, by file (the spike) | an object in its footprint changed |
| F1, by function | a function it ran changed; or its declaring file's uninstrumented code (its `#Preview` body) changed; or a global in an object it ran or read changed |
| F2 | F1, or the uninstrumented code of any object it ran changed |
| F3 | F1, with each global fingerprinted and followed through what its initializer reads |
| F4 | F3, or the witness tables (`…WP`) or class metadata (`…CMf`, which holds the vtable) of a type its objects use changed |

All five select on a conformance added or removed for a type the story uses. Here a conformance only counts when its type exists both before and after: users of a new or deleted type change anyway. They also match types exactly, so a nested type doesn't count as its parent.

**Zoo.** The seven earlier edits, plus one more: a member added in another file becomes `Tag`'s witness for a protocol requirement. A generic function in `Card` reaches it through the witness table.

| Edit | Changed | F0 | F1 | F2 | F3 | F4 |
|---|---|---|---|---|---|---|
| Literal in `Card` | 16 | 16 | 16 | 16 | 16 | 16 |
| Comment shift | 0 | 16 | 16 | 16 | 16 | 16 |
| Overload elsewhere | 36 | 70 | 70 | 70 | 70 | 70 |
| `#Preview` body | 2 | 16 | 16 | 16 | 16 | 16 |
| Lazy global | 16 | 16 | 16 | 16 | 16 | 16 |
| Runtime conformance | 16 | 44 | 24 | 44 | 24 | 24 |
| New view | 0 | 0 | 0 | 0 | 0 | 0 |
| **Witness from another file** | 16 | 44 | **10 (14 escape)** | 44 | **10 (14 escape)** | 24 |

**FulbloomFinance.** The same 16 commits as above, with 8,136 snapshot checks in all. Only the commits that touched code are listed. Every rule had the one flake in `28cd0b6e` and no other escape.

| Commit | Changed | F0 | F1 | F2 | F3 | F4 |
|---|---|---|---|---|---|---|
| `5b70c736` | 0 | 504 | 226 | 504 | 162 | 504 |
| `9eb51002` | 0 | 146 | 146 | 146 | 28 | 28 |
| `8077a785` | 10 | 150 | 112 | 128 | 82 | 112 |
| `bce38774` | 0 | 130 | 114 | 130 | 68 | 68 |
| `0340169b` | 0 | 70 | 2 | 2 | 2 | 2 |
| **All 16** | 11 | **1000** | 600 | 910 | 342 | **714** |

- **Per function, safely, selects 29% fewer than per file** (F4: 714 against 1000). That's 8.8% of all checks against 12.3%.
- **The gains are uneven:** `0340169b` drops from 70 to 2, `9eb51002` from 146 to 28, and `bce38774` from 130 to 68. `5b70c736` gains nothing: its changes to view bodies change their opaque result types, and with them the witness tables of every view that uses them.
- **Tracking by function opens holes that tracking by file mostly closes for free.** The changed witness table lives in the conformance's object, and a story that runs the type's code has that object in its footprint anyway.
  - F1 and F3 let 14 of 16 snapshots escape the witness edit; F4 needs its dispatch rule to catch them.
  - The dispatch rule took three tries before it stopped selecting more than F0. It first included the bodies behind witness thunks, then struct metadata, then tables that had disappeared.
- **Each rule rests on Swift's mangling conventions:** `vau` and `_WZ`/`vpfi` for globals, `WP` and `CMf` for dispatch, and `Mc`, `Mn`, `N`, `Ma` for types. An instance only a constructed test would expose is likely still out there.
- **Indexing costs about 5 s per build** in Python, for FBF's 520 objects.

Conclusion: ship selection by file. Selection by function is a measured 29% further cut in renders, which over these 16 commits is about a minute against roughly 13 of full runs. It costs a second, more fragile layer of rules. Revisit it once selection by file has telemetry on skips that turn out wrong, and more history than one adopter's day.

## Gaps found and closed

1. **Macro expansions aren't instrumented.** A `#Preview` body ran no instrumented code, so `Hazards/Dates` recorded none of `Hazards.swift`. The fix: the renderer adds each story's `fileID` to its footprint. Without it, edit 4 escaped. The same blindness predictably covers every macro's generated code, such as `@Observable` accessors and `@Entry`, but that is untested.
2. **A global is initialized once per process.** Only the first story each renderer drew recorded `Globals.o`; 14 of the 16 changed snapshots escaped. The fix: an object in a footprint brings in the objects defining every global addressor (`…vau`, `…vauZ`) it references, transitively. Addressors aren't instrumented, but their references are visible in the object's symbol table.
3. **Conformances are found at runtime.** Adding a conformance changes what `as? P` finds without changing any object the story ran; 14 of 16 escaped. (With a static `String(describing: Tag())`, overload resolution changed `Card.o` and nothing escaped.)
   - The fix: the ledger keeps the build's conformance descriptors (`…Mc`), and each footprint keeps the manglings of the types its objects define or refer to (`…N`, `…Ma`, `…Mn`).
   - A conformance added or removed whose mangling begins with one of a unit's types selects the unit.

## Timing

All runs used one renderer process, warm, with the debug `swiftbook`.

| Run | Time |
|---|---|
| Full run, all match | 10.1 s |
| `--changed`, nothing to render | 5.0 s |
| Full run after the `Card` edit, 16 fail | 21.9 s |
| `--changed` after the `Card` edit, 16 render and fail | 17.7 s |

- **A matching snapshot costs about 70 ms; a failing one about 0.8 s.** The zoo's snapshots are cheap, so skipping saves little here.
- **FulbloomFinance would save far more.** It reports 514 Mac snapshots taking 1–2 minutes on six renderers. Typical edits change 1–4% of them, though file granularity and shared views select more.
- **The instrumented renderer renders at the same speed:** 10–11 s against 10 s. Switching instrumentation on or off rebuilds the renderer once.

## Known gaps

- **Code that isn't instrumented:**
  - C and Objective-C targets;
  - prebuilt binaries;
  - macro-generated code in a file other than the story's (see gap 1).

  A change to such code goes unseen unless something instrumented in the same object also ran. A conservative rule: treat an object that changed but defines no instrumented functions as affecting everything. Generalizing gap 2's fix would also help: add the objects defining any uninstrumented function a footprint's objects call.
- **Resources:** asset catalogs, bundled files, and fonts aren't tracked. Either hash the resource bundles into a key every unit shares, or record bundle reads per unit.
- **The environment:**
  - Xcode, the SDK, the OS and simulator runtime, capture mode, tolerances, and `SWIFTBOOK_*` settings belong in a key the whole ledger depends on.
  - SwiftBook's own changes already reach every footprint, because its rendering code runs in every render.
- **Caches in the harness:** SwiftBook computes a `PreviewModifier`'s shared context once. Its footprint should go to every story that uses the modifier. On the zoo the context and its users share a file, so this went untested.
- **Concurrency:** counters are per process, so a process can measure one unit at a time. SwiftBook's renderers already work that way. A harness that runs tests in parallel within one process, such as Swift Testing by default, would have to serialize them.
- **Not tried here:** iOS and tvOS simulators, which should work since the probe runs in the app and the simulator shares the host's file system, and the in-process `#SwiftBookTests` path.
- **The profile record layout is LLVM's** (version 10, 64 bytes). The probe validates it and refuses to run if it doesn't fit.

## The package

The spike's package became [SwiftImpact](https://github.com/brandonbloom/SwiftImpact), separate from SwiftBook and knowing nothing about snapshots. Its API changed after the spike; see its documentation. SwiftBook supplies what only it knows:
- what a unit is: story × device × appearance;
- the file declaring each story;
- the shared contexts each may use;
- the results and references that decide whether a past result still holds.

`swiftbook test --changed` is the result; see the documentation's Rendering Only What Changed. The spike's own code is on the branch `worktree-test-impact-spike`.

Swiftpothesis could use the probe as it is, for coverage-guided generation as well as selection.
