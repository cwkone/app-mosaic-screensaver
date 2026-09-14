# Dense-grid performance changes

Measured on 2026-09-12 against release `da62bb6` (1.0), using the Intel MacBook Pro with Intel UHD 630 and Radeon Pro 5600M. The installed screensaver and published release were not replaced. This branch is a candidate for awake-display testing.

## What changed

- Idle icons use one image layer. A second layer exists only during that icon's fade, then the outgoing layer is removed. Scrolling moves columns or rows with the same phase, period, direction and offscreen wrap as the original per-icon animation.
- Identical renderer configurations and repeated resume calls do no work. The view coalesces resize, backing, attachment and discovery callbacks within a main-queue turn. Initial repeated icons share an artwork request, and texture assignments commit in batches.
- Size-specific uncolored pixels are reused across palettes. Original-color textures share that storage rather than duplicating it. Final textures have a 48 MiB NSCache cost budget and uncolored pixels have 16 MiB; this is not a process-memory ceiling. App bundle modification timestamps invalidate artwork identities after catalog refresh. Cancelled jobs cannot remove newer replacements for the same key.
- Shuffle removal avoids shifting arrays; fallback selection avoids allocating filtered pools. Chooser search results and selection summaries are reused until their inputs change. Catalog refresh runs at utility priority and persists the app list only when it changes.

No preferences, options, artwork normalization rules, image-size limits, fade timing, scroll speeds, margins, edge treatments, or selection rules were removed. Settings or actual geometry changes can still rebuild the renderer; redundant callbacks do not.

## Measurements

The table below is generated from the final benchmark logs. Each mode runs in a new process, discovers 865 apps, configures one to three offscreen renderer trees, waits for artwork, repeats the same configuration five times per view, waits for recovery, and samples three warm seconds. Most modes use three 1920×1080-point views at backing scales 1, 2, 1. `single` and `double` use one and two views; `tiny` selects two apps. Dense icons are 64 points with 8% spacing. `default` uses 104 points, `large` 256, `zero` removes spacing, `vertical` scrolls up, and `still` is stationary.

| Mode | Layers, release → candidate | Drift animations | Peak RSS (MiB) | Startup CPU (s) |
| --- | ---: | ---: | ---: | ---: |
| dense | 4,329 → 1,539 | 1,440 → 90 | 191.0 → 168.8 | 4.433 → 4.181 |
| still | 4,041 → 1,353 | 0 → 0 | 181.8 → 164.9 | 4.100 → 3.732 |
| tiny | 4,329 → 1,539 | 1,440 → 90 | 112.0 → 98.0 | 0.091 → 0.040 |
| large | 333 → 144 | 108 → 27 | 260.1 → 212.9 | 1.861 → 1.748 |
| default | 1,809 → 670 | 600 → 60 | 221.9 → 178.8 | 3.334 → 3.136 |
| vertical | 4,545 → 1,575 | 1,512 → 54 | 195.0 → 170.9 | 4.397 → 4.292 |
| zero | 4,905 → 1,737 | 1,632 → 96 | 194.7 → 174.7 | 4.356 → 4.570 |
| tint | 4,329 → 1,540 | 1,440 → 90 | 192.0 → 191.8 | 5.120 → 4.995 |
| mono | 4,329 → 1,539 | 1,440 → 90 | 192.0 → 194.4 | 4.972 → 4.760 |
| single | 1,443 → 513 | 480 → 30 | 134.9 → 128.5 | 1.404 → 1.378 |
| double | 2,886 → 1,026 | 960 → 60 | 177.9 → 163.9 | 3.320 → 3.177 |

In the dense three-view run, five unchanged callbacks per view caused **15 → 0 rebuilds** and **7,200 → 0 artwork requests**. The callback burst consumed **0.728 → 0.000047 CPU seconds**, plus **0.590 → 0.000003 CPU seconds** of artwork recovery. Peak RSS decreased by **11.6%**. The cache budget refinement keeps tinted/monochrome peak memory near the baseline; timing improvements are not uniform across modes.

Full captured measurements: [performance-measurements.json](performance-measurements.json).

Layer counts are sampled after initial artwork; active fades can temporarily add layers. Animation counts describe installed drift animations at configuration time. These offscreen trees do not establish compositor cost. Peak RSS includes startup and the repeated-configuration exercise, not just steady state. Startup CPU excludes catalog discovery. Random app selection and other activity affect timing and memory; single-run differences should not be interpreted as precise population estimates.

Warm process CPU was already small in the baseline. The change should not be described as a large measured steady-state CPU or GPU reduction. The reproducible structural improvement is the lower layer/animation count and zero rebuilds or artwork requests for identical callbacks. New icon swaps can legitimately decode during warm sampling.

## Validation and limits

- `./Scripts/build.sh`: universal arm64/x86_64 saver and preview bundles, property lists, signatures, Finder-icon metadata and ZIP packaging.
- `./Scripts/test.sh`: settings/migrations, layout and wrapping, shuffle coverage and duplicate avoidance, artwork processing and palette cache reuse, update invalidation, catalog traversal, actual saver-bundle loading, renderer cancellation/restart/fade cleanup, preview/options/chooser interactions and stop cleanup.
- `./Scripts/compare-renderer.sh`: 35 pixel-identical model-layer snapshots against the release renderer, covering all directions, small/large icons, original/tinted/monochrome palettes, zero spacing, whole-icon margins and edge fades with 2× artwork. Deterministic comparisons use Finder in every cell to avoid random-selection differences. New tests independently check every cell's grouped motion phase at wrap boundaries and long elapsed times. These are not screenshots of live presentation-layer animation.
- Preview grid and deterministic grid snapshots were visually inspected. Native options snapshots were incomplete while displays were asleep (control labels/backgrounds did not capture reliably), so their visual appearance still needs an awake check; the automated options/chooser interaction assertions passed. Local execution is Intel only; the Apple Silicon binaries were built but not run on an Apple Silicon device.

Both connected displays (built-in Retina and external 1920×1080) were asleep during the environment check. One legacyScreenSaver host process was observed. GPU/WindowServer load, frame pacing, thermal/fan behavior, actual awake multi-display hosting, and separate-host-process scaling remain unverified. Do not promote this candidate based on offscreen numbers alone.

Grouped layers were selected over raster tiles: they already remove roughly two thirds of the dense layer graph and most drift animations while preserving shared per-icon texture storage and avoiding tile redraws during fades. No tiled renderer or persistent cross-process artwork service ships in this change. Those remain possible follow-ups if awake profiling shows a remaining bottleneck; no helper daemon or display configuration change was introduced.

## Reproduce

```sh
./Scripts/build.sh
./Scripts/test.sh
./Scripts/compare-renderer.sh
./Scripts/benchmark.sh da62bb6 > QA/performance/baseline.jsonl
./Scripts/benchmark.sh working > QA/performance/candidate.jsonl
```

Run the two benchmarks sequentially. Optional mode arguments restrict the workload, for example `./Scripts/benchmark.sh working dense tiny`. Generated `build/`, `dist/`, and `QA/` files stay untracked. For the release decision, compare the installed release and this candidate with the same selected apps and settings on awake displays, including fast/slow motion in all directions and overlapping fades, and measure WindowServer/GPU/energy alongside process CPU and memory.
