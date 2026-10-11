# Liquid Glass noise in snapshots

**Date:** 2026-10-11. Xcode 27.0 (27A266a), iOS 27.0 simulator runtime (24A434), macOS 27.2, Apple M4 Max. SwiftBook at `e83d8d2` plus research instrumentation (not committed). Fulbloom at `5f9ef68`, rendered from a copy with SwiftBook in edit mode.

**Method:**

- **Renders.** About 1,000 iPhone and 560 Mac renders with `swiftbook render`:
  - 20 runs of seven glass-heavy Fulbloom stories on iPhone, and 20 more under load.
  - 20 runs of the zoo's glass stories on iPhone and Mac. The zoo story file `GlassLab.swift` was written for this research.
  - 20 runs of four Fulbloom Mac stories.
  - 30 fresh launches that each render one story first.
- **Fulbloom's failures.** Every reference/actual pair in Fulbloom's worktrees (`.build/swiftbook/failures`), all from Oct 7.
- **Instrumentation.** The iOS renderer was instrumented to:
  - dump the window's layer tree;
  - keep capturing for 3 s after a render settles (a "timeline");
  - apply accessibility overrides and private layer properties.
- **Render server experiments.** A private simulator ("GlassLab iPhone 17 Pro") ran its render server with Core Animation debug variables. The shared simulator was used only under Fulbloom's machine-wide lock, one render at a time.
- **Measurements.** CIEDE2000, as `ImageDiff` computes it, plus checks for dither periodicity and a blurred comparison.

Images are in [liquid-glass-noise/](liquid-glass-noise/). Diff maps are gray, with blue for pixels that differ by ΔE ≤ 1 and red for ΔE > 1.

## Summary

- **Glass noise is discrete, not continuous.** Every varying pixel has exactly two states. Each story shows only a handful of whole-image variants, and the same variant recurs across runs, worktrees and days.
- **The variants come from three mechanisms in the render server, not the app:**
  1. **Dither on or off.** Glass is normally dithered with a tiled 32-pixel noise texture. Rarely, a capture comes out undithered (banded). This changes thousands of pixels across every glass surface at once, by at most 2 levels per channel (ΔE up to 3.5). It is both "the whole tab bar shifted tint" and "5,725 pixels across a search field".
  2. **The selected tab's lens toggles** between two rasterizations every 80–250 ms, indefinitely, after the render has "settled". It changes 236–1,009 pixels, up to ΔE 3.4.
  3. **SDF path switch.** Core Animation switches how it draws glass shapes (inline or cached) a few hundred milliseconds after they appear. Captures near the switch land on either side, changing 69–967 pixels, up to ΔE 1.9.
- **No supported switch makes glass deterministic.** Reduce Transparency, Increase Contrast, the layer clock, and a dozen private Core Animation switches all still vary, and most also change how glass looks.
- **No settle time fixes it.** The lens never stops toggling, and the dither state lasts for the whole capture.
- **Recommendation: a glass-scoped perceptual comparison.**
  - Take the glass regions from the layer tree: visible `CABackdropLayer` frames plus 4 pt.
  - Inside them, a pixel counts as changed only if a 1-pt box blur of both images still differs by more than ΔE 3. Outside them, the comparison stays exact.
  - With these settings every observed noise variant passes, and every real change tested still fails.

## Reproduction

### iPhone: Fulbloom (20 runs, shared simulator, no extra load)

Seven stories × light and dark = 280 renders, each run a fresh renderer launch. Each run is compared with run 1, which matches Fulbloom's committed references exactly, except as noted.

| Story | Variants against run 1 | Fail the default tolerance |
|---|---|---|
| PhoneBrowser (spending), light | 15 identical. 4 "lens": 1,009 px differ, 23 > ΔE 1, max 1.97. 1 "banded": 60,888 px, 12,718 > ΔE 1, max 3.53 | 5 of 20 |
| PhoneBrowser (spending), dark | 18 identical. 2 "lens": 236 px, 19 > ΔE 1, 6 > ΔE 3, max 3.41 | 2 of 20 |
| PhoneBrowser (accounts), light | Two states of 3 px, ΔE ≤ 0.62 (run 1 is the minority one) | 0 |
| PhoneBrowser, Merchants ×2, Inventory, Investments (phone), and (accounts) dark | All identical | 0 |

- **Failures concentrate in one story.** 5 of 20 runs had at least one failure, all in PhoneBrowser (spending). It has a selected-tab lens and a glass toolbar button over content.
- **Counting.** "Fail" counts pixels above ΔE 1 against the noise floor (10 pixels, ΔE 3), before `ImageDiff`'s anti-aliasing filter, which may excuse a few.
- **The zoo's glass is calmer.** The zoo's `.glassEffect` capsules over flat and striped backgrounds flip 1–2 pixels at ΔE ≤ 1.05 in dark mode, in 12–13 of 20 runs: within the noise floor. Its tab bar, search field, glass buttons, material, blur, and a plain gradient are byte-identical every time.

### Fulbloom's Oct 7 failures

| Failure | Differing | > ΔE 1 | Max ΔE | Max channel Δ | Mechanism |
|---|---|---|---|---|---|
| Merchants (phone, tidied names), dark | 19,541 | 6,617 | 2.17 | 2 | Banded search field |
| Merchants (phone, tidied names), light | 52,903 | 7,450 | 2.67 | 2 | Banded search field |
| Merchants (phone, empty), dark | 19,541 | 6,617 | 2.17 | 2 | Banded (same signature, other worktree) |
| Inventory (phone), light | 67,203 | 3,450 | 3.39 | 13 | Glass only (see masks below) |
| PhoneBrowser (spending), dark, in three worktrees | 69 | 23 | 1.86 | 2 | SDF path |

The other PhoneBrowser failures there are real changes: a dollar amount behind the glass differs, and the glass amplifies it across the whole bar (max ΔE 40).

The reported "5,725 pixels (0.18%), largest ΔE 3, across a search field" is 0.18% of an iPhone frame (1206×2622). Its size and ΔE match the banded search fields above.

### Mac

- **Emulated capture is deterministic.**
  - Fulbloom's LedgerBrowser Window, Window (dashboard), TransactionsPage (filtered) and Inventory: 20 runs, all identical except Window, which has two states of 64 px at ΔE ≤ 0.93. Those pixels are an SF Symbol warning icon, not glass.
  - The zoo's glass stories, tab bar, search field, material and sidebar: 20 runs, all byte-identical.
  - Emulated capture draws in process, without the render server paths below.
- **Window-server capture was not tested:** the screen was locked. It composites through the real window server and may show the same mechanisms.

### Load, simulator state, and timing

- **CPU load doesn't matter.** 20 runs with 16 busy-looping processes (load average up to 130) gave the same variants at similar rates: lens 3 of 20 dark and 1 of 20 light, no banding.
- **Simulator state doesn't matter.** A freshly created simulator rendered byte-identical images to the long-running shared one.
- **Banding is rare.** It appeared once in about 1,000 iPhone renders: the first capture of a renderer launch, on the shared simulator while other sessions were active. 30 more first captures on the private simulator were all dithered. Fulbloom hit banding three times on Oct 7, each within minutes of failures in other worktrees (08:14–08:15 and 17:10–17:17). That was before its lock, when concurrent runs shared one simulator. Banding then held across consecutive renders (Merchants light and dark).
- **"Settled" doesn't mean still.** After `stableCapture` returns, a 3 s timeline of PhoneBrowser (spending) captures 10–19 distinct frames, alternating between two states at irregular 80–250 ms intervals. Merchants changes once, 258 ms (light) and 360 ms (dark) after settling, then holds.

## Where the noise comes from

### What glass is made of

The layer tree of PhoneBrowser (spending) has:

- **Glass surfaces.** The tab bar and the toolbar button are each a `CABackdropLayer` with a `glassBackground` filter, sampling at half resolution (`scale=0.5`, `marginWidth=16`), with `CASDFLayer` and `CASDFElementLayer` shapes. The shapes carry `match-position`, `match-bounds`, and similar animations, which track other layers rather than time.
- **The selected tab's lens** (`_UILiquidLensView`). A backdrop at quarter resolution with `gaussianBlur` and `colorMatrix`, a `displacementMap` (refraction), and a `_UILiquidLensView.punchout.matchPosition` animation. It sits at x = 227.5006 pt, which is 682.502 px: on a half pixel.
- **Labels and icons** inside glass use `vibrantColorMatrix` filters.
- **Every layer** has `contentsDither=1`. Every backdrop has `tracksLuma=0`, so adaptive tinting by the luminance behind the glass isn't active in these captures.

### The render server draws the capture

`drawHierarchy(afterScreenUpdates:)` is composited by the simulator's render server (backboardd), not by the app:

- Core Animation's debug variables have no effect when set in the app.
- When set on the simulator's backboardd, they do. For example, `CA_COLOR_BACKDROPS` tints every backdrop in the capture ([backdrop-mask.png](liquid-glass-noise/backdrop-mask.png)).

So the app's frozen layer clock (`speed = 0`) doesn't govern what the render server does between frames.

### 1. Dither on or off

- **Normally dithered.** QuartzCore's Metal shaders take a `noise_texture` (`noise_width`, `fc_has_noise_tex`), a tiled dither applied when glass's high-precision result is written to 8 bits. Every normal capture shows it: in flat glass, the per-pixel residual correlates 0.93–1.0 with itself shifted 32 px horizontally.
- **The noise variant is banded.** It is a gradient quantized with no dither: self-correlation is flat, and contrast-stretched crops show clean bands.
  - Search field: [dithered](liquid-glass-noise/search-field-dithered.png) and [banded](liquid-glass-noise/search-field-banded.png), with their [diff](liquid-glass-noise/search-field-diff.png) and its [32-px period](liquid-glass-noise/search-field-diff-zoom.png).
  - Tab bar: [dithered](liquid-glass-noise/tab-bar-dithered.png) and [banded](liquid-glass-noise/tab-bar-banded.png), with the [diff over the whole bar](liquid-glass-noise/tab-bar-diff.png).
  - The difference is at most 2 levels per channel with a mean ΔL of about 0, so the glass doesn't get lighter or darker. ΔE reaches 3.5 only on dark glass, where 2 levels are more visible.
- **Not reproduced by any switch tried.** The banded state didn't reproduce with `contentsDither=false` on every layer, `CA_FORCE_GENERIC_SHADERS`, `CA_DISABLE_PRECOMPILED_PIPELINES`, `CA_DISABLE_BACKDROP_COMPUTE`, `CA_BACKDROP_COMPUTE_AND_RENDER_FALLBACK`, `CA_DISABLE_LOSSY_TEXTURES` or `CA_DISABLE_TILE_SHADERS`. `reducesCaptureBitDepth` on the backdrops gives a third, differently dithered state.
- **Hypothesis, untested:** the render server occasionally composites glass with the shader variant that has no noise texture. That might happen while the texture or pipeline isn't ready, or under GPU or memory contention from several apps rendering at once.

### 2. The lens toggle

- **What changes.** The lens outline and the part of the selected label under its left edge alternate between two states ([lens-toggle.png](liquid-glass-noise/lens-toggle.png)), by up to 11 levels.
- **It doesn't depend on time or animations.** It continues with the layer clock running, with the lens's animations removed, and with the backdrop filter cache disabled on the layers. Several of those also break the lens's rendering (ΔE up to 98). `CA_DISABLE_BACKDROP_CACHE` in the render server slows the toggle (3–6 distinct frames in 3 s instead of 10–19) but doesn't stop it.
- **Likely cause:** the lens sits on a half pixel, and its edge and refraction round either way depending on per-frame state in the render server.

### 3. SDF path switch

- **Reproduced exactly.** Setting `CA_DISABLE_INLINE_SDFS` in the render server reproduces two known variants pixel for pixel:
  - Fulbloom's recurring PhoneBrowser (spending) dark failure (69 px, 23 > ΔE 1, max 1.86), as at the [toolbar button](liquid-glass-noise/toolbar-button-diff.png).
  - The change Merchants makes 258–360 ms after settling (356 and 967 px).
- **Likely cause.** Core Animation draws a glass shape inline at first, then from a cache once it has been seen for some frames (`CA_SDF_ELEMENT_MINIMUM_CACHE_COUNT`). Which side a capture lands on depends on frame timing.

### The other candidates

- **Content behind the glass.** Deterministic for identical content. But a real change behind glass spreads across the whole glass surface: a changed amount behind the tab bar changed 76,000 pixels.
- **Shimmer or specular animation over time.** Not seen. The same two states recur, the variation is the same with the clock running, and there is no drift.
- **Adaptive luminance tinting.** Inactive: `tracksLuma=0` on every backdrop.
- **GPU or shader precision.** Not seen beyond the dither: no variant has continuous, small, unstructured differences.

## Evaluating solutions

The noise cases are the seven above: banded tab bar, two lens toggles, two banded Merchants fields, the SDF switch, and Inventory.

The real changes used as controls:

- the amount behind the glass;
- Reduce Transparency;
- SwiftUI's reduce-transparency environment value, a ΔE 4 change confined to glass;
- a changed digit in caption text;
- a 0.5-pt hairline 15% darker;
- an icon moved by 1 pt.

### A tolerance scoped to glass regions

**Feasible; recommended.**

- **Masks from the layer tree.** Take visible `CABackdropLayer`s that have filters and use their window frames. That's a class-name check with public CALayer API, and no private calls.
- **Coverage.** Expanded by 4 pt, these cover 100% of the differing pixels in all seven noise cases, while covering only 5.6–10.7% of the screen. Without the margin, 97–100% are covered.

| Noise case | Mask area | Differing pixels inside the mask, 4-pt margin |
|---|---|---|
| Banded tab bar | 10.7% | 60,888 of 60,888 |
| Lens toggle, dark / light | 10.7% | 236 of 236 / 1,009 of 1,009 |
| Banded Merchants field, dark / light | 5.6% | 19,541 of 19,541 / 52,903 of 52,903 |
| SDF switch | 10.7% | 69 of 69 |
| Inventory | 6.4% | 67,203 of 67,203 |

- **Masks from anchor preferences** (a `.masked()` modifier) don't fit glass. The noisiest glass is system chrome (tab bars, toolbars, search fields) that app code doesn't wrap. And masking excludes regions entirely, so real changes in glass would vanish.
- **Effort:** small in the renderer (a tree walk after capture), medium in the diff and storage. About 1–2 days with tests.
- **Gives up:** sensitivity to changes confined to glass that are invisible after a 1-pt blur (below).

### A perceptual or statistical diff for glass

**Recommended, inside glass masks only.** A box blur of both images, then CIEDE2000 on the blurred pixels.

| Case | Raw: > ΔE 1 / max | 1-px blur (≈1 pt at 3x): > ΔE 3 / max | 2-px blur: > ΔE 3 / max |
|---|---|---|---|
| Noise: banded tab bar | 12,718 / 3.53 | 0 / 2.52 | 0 / 1.63 |
| Noise: lens toggle, dark | 19 / 3.41 | 0 / 1.26 | 0 / 1.21 |
| Noise: lens toggle, light | 23 / 1.97 | 0 / 1.25 | 0 / 1.25 |
| Noise: banded Merchants, dark | 6,617 / 2.17 | 0 / 1.21 | 0 / 1.23 |
| Noise: banded Merchants, light | 7,450 / 2.67 | 0 / 1.77 | 0 / 1.60 |
| Noise: SDF switch | 23 / 1.86 | 0 / 1.86 | 0 / 1.87 |
| Noise: Inventory | 3,450 / 3.39 | 0 / 1.84 | 0 / 1.65 |
| Real: amount behind glass | 76,493 / 40.2 | 24,912 / 35.7 | 24,604 / 34.8 |
| Real: Reduce Transparency | 185,802 / 5.28 | 95,987 / 4.41 | 94,808 / 4.39 |
| Real: SwiftUI reduce-transparency value (glass only) | 13,709 / 4.22 | 10,451 / 4.09 | 10,108 / 4.09 |
| Real: digit in caption text | 641 / 100 | 1,033 / 90.5 | 1,005 / 45.9 |
| Real: icon moved 1 pt | 558 / 100 | 828 / 97.2 | 1,122 / 61.3 |
| Real: hairline 15% darker, dark | 2,220 / 6.83 | 2,216 / 4.49 | 0 / 2.62 |
| Real: hairline 15% darker, light | 2,220 / 3.99 | 0 / 2.50 | 0 / 1.39 |

- **Separation.** A 1-pt blur with a ΔE 3 threshold separates every noise case from every glass-sized real change, with a margin of about 0.5 ΔE.
- **Not globally.** Applied everywhere, it would miss the light hairline: a real, if subtle, change outside glass. That is why it belongs inside glass masks only.
- **A 2-px blur** loses the dark hairline too.
- **Gives up:** a glass-only change that stays within ΔE 3 after a 1-pt blur, such as a slight glass tint change, which barely shows to users either.

### Deterministic glass

**Not feasible.**

| Setting | Still varies? | Look |
|---|---|---|
| Reduce Transparency, system-wide | Yes: lens in 8–9 of 10 runs | Glass nearly opaque white, separators added |
| SwiftUI `_accessibilityReduceTransparency` | Yes | Some SwiftUI glass changes (ΔE ≤ 4), backdrops remain |
| Increase Contrast (`_colorSchemeContrast`, trait) | Yes | Whole UI changes (30–73% of pixels) |
| Layer clock running (`speed = 1`) | Yes | Same |
| `contentsDither = false` on every layer | Yes | Same |
| `disableFilterCache`, `reducesCaptureBitDepth`, animations removed | Yes | Lens broken, or a different dither |
| `CA_*` variables in the render server (15 tried) | Yes: none stopped the lens toggle (8 checked with timelines) | Some break the lens; they need a render server restart |

There is no public API, environment value or trait for deterministic glass. The accessibility settings also defeat the purpose, since they change what users see.

### Better settling

**Doesn't work.**

- The lens toggles for as long as the window is up: 10–19 distinct frames in 3 s, so no hold converges on one state.
- Banding lasts for the whole capture, so waiting doesn't change it.
- Only the SDF switch is a one-time transition. Waiting about 400 ms would capture its later state consistently, but at the cost Fulbloom measured (40 s per run for a 300 ms hold).

### Per-story tolerance (`.tolerance(...)`)

**Feasible once story metadata exists; not for glass.**

- To pass the banded tab bar, PhoneBrowser (spending) would need a changed-pixel ratio of at least 0.4% and ΔE 3.6. That would hide a changed digit (0.02%) or a whole-screen color drift of ΔE 3 anywhere in the story.
- It remains useful for other noise, such as charts and blur.
- **Effort:** medium, since it depends on the unbuilt story-metadata mechanism.

### Raising the global noise floor

**Rejected.** Absorbing the banded case needs about 13,000 pixels at ΔE 3.6, everywhere, in every story.

## Recommendation

**A glass-scoped perceptual comparison, with masks from the layer tree.** Keep the noise floor (10 pixels, ΔE 3) for everything else.

1. **Collect glass regions in the renderer.**
   - In `UIKitRenderer`, after `stableCapture`, walk the window's layer tree.
   - For each visible `CABackdropLayer` with filters (not hidden, opacity above 0, non-empty), convert its bounds to window coordinates and expand by 4 pt.
   - Return the rects with the snapshot, in `SnapshotMetadata`, so they travel in the PNG's text chunks.
   - Do the same in `MacRenderer` for window-server captures. Emulated Mac captures are deterministic and can skip it.
2. **Compare inside those regions perceptually.**
   - Add the regions to `ImageDiff.Tolerance`, with a blur radius of 1 pt and a glass ΔE of 3.
   - For each pixel that differs inside a region, compare the 3×3 box means of both images (a box of `round(scale)` pixels at other scales). It counts as changed only if that ΔE exceeds the glass threshold.
   - Use the union of the reference's and the actual's regions, so moved glass can't hide anything.
   - Work only at differing pixels, so debug builds stay fast.
3. **Report it.**
   - Count ignored glass pixels separately.
   - Paint them a third color in the diff image.
   - Say "glass noise ignored" in test output, so a reviewer knows tolerance was applied.
4. **Test it.**
   - Golden tests from this research's images: the banded and dithered search fields match; the reduce-transparency and amount-behind-glass pairs don't.
   - A zoo canary like `GlassLab.swift`, with a selected-tab lens over content, to keep a noisy story under CI.
5. **Later.** Show glass regions as an overlay in the viewer's diff modes.

## Open questions

- **What triggers banding?** The best lead is several apps rendering in one simulator at once. Fulbloom's lock now prevents that, and SwiftBook's simulator pool may reintroduce it if pooled simulators share a host GPU under load.
- **Window-server capture on the Mac** wasn't measured: the screen was locked.
- **tvOS and iPad** weren't measured. They use the same render server, so the same mechanisms are likely.
