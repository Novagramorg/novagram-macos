# ShortPeerRowLab

This mini-app tests the production `ShortPeerRowItem.prepare` implementation and the `ShortPeerRowView` observer lifecycle without building Telegram or creating an account. Run `prepare.py` before building: it extracts the current production code and records hashes in `provenance.json`. The baseline preparation and observer registration blocks are preserved from `b6516131e`.

The production change retains the existing four title/status layouts until their effective widths change. The attributed strings and font are fixed for an item's lifetime. The context label's width is cached by text; changing the mutable row type still invalidates it. Both legacy and modern width formulas, including the legacy selected-status image allowance, remain unchanged. Each item keeps only its current layouts, with two small cache keys (approximately 64 bytes of bookkeeping), rather than a history of widths.

The view now tracks one weak selection interaction. Rebinding to the same interaction avoids observer-array scans; switching interaction or detaching removes the old observer. Previously, `set` removed only selectable observers, then re-added the *previous* interaction. Reused rows could receive updates for a different selection model, even after removal. The tests reproduce that behavior in the preserved baseline and verify its absence in the candidate.

## Original preparation and observer validation

- Eight regression tests pass in debug, release and Address Sanitizer configurations. Release also runs the ninth test, the opt-in benchmark.
- 1,500 combinations of legacy/modern geometry, fractional widths, insets, selection/deletion controls, badges, scam/fake/premium/verified flags, right actions, status images and context labels; each is also prepared again for selection.
- Fixed-width accessory mutations check invalidation independently of window resizing.
- 1,128 byte-for-byte bitmap comparisons using real TGUIKit `TextNode` and Core Text, covering normal/selected colors, English, Arabic, Hebrew, Chinese, combining marks, emoji, truncation, empty text and 1×/2×/3× drawing.
- 1,000 unchanged preparations retain all four layout and node identities; resizing replaces them.
- All 36 transitions between plain, selectable, interactable and deletable states, plus repeated binding, detach, reattach and release. Observer delivery uses real TGUIKit `InterfaceObserver` and actual AppKit view attachment.
- Both modified production files pass Swift frontend parsing for normal and `SHARE` configurations. The share package uses symlinks to the same files.

The harness stubs account/peer data and row accessories. It supplies numeric `textInset` values rather than creating avatars or premium controls. It compiles the exact production preparation method and observer helper/lifecycle methods, with a small NSView adapter replacing the full row's `set` method; extraction checks that production `set` invokes the helper and has no separate observer registration. It does not exercise the complete row hierarchy, accessibility, avatars or a live Telegram window. Full app compilation and end-to-end scrolling were not performed.

## Release measurements

Apple Silicon, Swift 6.3.3; median of nine alternating baseline/candidate batches, 2,000 operations per batch. Times are microseconds per operation, from `results.json`.

| Path | Before | After |
|---|---:|---:|
| Repeated preparation, unchanged width | 31.087 | 0.088 |
| Selection changes, unchanged width | 30.906 | 0.089 |
| Repeated preparation with context label | 45.061 | 0.084 |
| Actual width changes | 39.622 | 39.506 |
| New item plus first text preparation | 35.302 | 35.097 |
| Observer bookkeeping on repeated binding, 100 rows per model | 3.896 | 0.040 |

These are isolated path timings, not an app-wide speedup. The cold-item benchmark creates the harness item and its attributed strings, not the full account/avatar-backed production item. Actual resizing and first preparation still perform text shaping. The optimization chiefly helps repeated sizing and selection; new rows retain the original first-layout work. The observer benchmark uses separate baseline/candidate models with 100 attached views each and excludes all other row binding work.

## Run

From the repository root:

```sh
python3 tools/perflab/ShortPeerRowLab/prepare.py
swift test --package-path tools/perflab/ShortPeerRowLab --scratch-path /tmp/ShortPeerRowLab-debug
SHORT_PEER_BENCHMARK=1 swift test -c release --package-path tools/perflab/ShortPeerRowLab --scratch-path /tmp/ShortPeerRowLab-release
swift test --sanitize address --package-path tools/perflab/ShortPeerRowLab --scratch-path /tmp/ShortPeerRowLab-asan
```

The benchmark writes `/tmp/short-peer-row-benchmark.json`. Generated sources and build products are ignored. Theme images are placeholders required to initialize TGUIKit; they are not included in the text comparisons.

## Accessory reuse pass

The next pass removes repeated work from `ShortPeerRowView.set`. An unchanged context label reuses its existing `TextViewLayout`, checking text, font, foreground color and alignment before reuse. A checked accessory retains its `ImageView` and tinted image, invalidating on source image identity, tint or display scale changes. Removing the accessory releases the view and its cache key. There is no global cache or history of old labels; the checkmark uses one optional style key per row view.

Right action callbacks now pass the action's declared `index`, rather than its position in the array. Rebinding still installs the new item's callback and accessibility label, and callbacks retain the item weakly.

`prepare.py` extracts the current context-label helper, accessory switch and right-action binding code verbatim. It compiles them in an AppKit adapter with real TGUIKit `TextView`, `ImageView`, `ImageButton` and `SwitchView`. `ReferenceAccessories.swift.txt` preserves the same blocks from `7b573a350`; `accessory-provenance.json` records the production, reference and generated source hashes. Theme images and account/peer data are supplied by the adapter. These tests do not execute the complete row's avatar, premium badge, layout or parent-table binding.

The expanded suite has 15 regression tests and two opt-in benchmarks. Debug and Address Sanitizer run all 15 regressions; the release run also executes the accessory benchmark. The original preparation, rendering and observer tests continue to pass. The new tests include:

- 206 byte-for-byte text/checkmark rendering comparisons, including 1×/2×/3× scales, Arabic, Hebrew, Chinese, emoji, combining marks, multiline labels, tint/font/alignment changes and empty labels. Every comparison checks for nonblank output. Frame sizes, backgrounds, corner radii and interaction flags are also compared with the baseline.
- All 121 transitions among the 11 accessory states, followed by removal.
- 1,000 unchanged bindings preserve label layout, checkmark view and checkmark image identity.
- Changed callbacks, removed callbacks, nonsequential action indices, peer reuse, accessibility labels and weak item retention.
- Removed label views, layouts and checkmark views are released.
- Production source parses for both normal and `SHARE` configurations. A full Telegram build was not performed.

Release medians, microseconds per accessory binding, nine alternating batches of 2,000 iterations on Apple Silicon with Swift 6.3.3:

| Scenario | Before | After |
|---|---:|---:|
| Unchanged context label | 6.204 | 0.385 |
| Changing context label | 6.353 | 6.459 |
| New row with context label | 45.247 | 45.294 |
| Unchanged colored label | 7.298 | 0.465 |
| Unchanged checkmark | 25.059 | 0.110 |
| Checkmark toggled on/off | 12.531 | 12.649 |
| New row with checkmark | 42.464 | 42.439 |

Repeated label binding is about 16× faster and repeated checkmark binding about 228× faster in this isolated path. Changing labels and new rows still perform their original work, with roughly 0–2% timing differences in this run. These measurements exclude the rest of `ShortPeerRowView.set`, layout, drawing, avatars and scrolling; they are not app-wide speedups or a resident-memory measurement. Reuse removes temporary layouts, image rasterization and view/layer churn on unchanged bindings.

Run the new benchmark with:

```sh
python3 tools/perflab/ShortPeerRowLab/prepare.py
SHORT_PEER_ACCESSORY_BENCHMARK=1 swift test -c release --package-path tools/perflab/ShortPeerRowLab --scratch-path /tmp/ShortPeerRowLab-release
```

Raw timings and all nine trials per scenario are in `accessory-results.json`; verification summaries and hashes are in `accessory-validation.json`.

## Paid-message badge pass

`ShortPeerRowView.updatePresentation` redraws the paid-message badge on every selection notification and row binding. A one-entry cache now reuses its existing image when the formatted amount, resolved colors, font, scale and star-image identity match. The cache is created only for paid badges, retains no previous entries, and is discarded when the badge is removed or changes to the premium-required icon. Unchanged images are not assigned back to the layer. Layout and animation behavior remain in the original binding method.

`prepare.py` extracts the production cache, drawing function and presentation binding method. The reference preserves the previous binding and drawing code from `007289e39`. Tests execute real TGUIKit image views, text measurement and Core Graphics rendering, using both resolutions of the app's `star_small` asset. Peer/account data and theme values are supplied by the harness. This does not compile the entire row's avatar and account integration or the full Telegram app.

The suite now passes 23 functional tests in debug, release and Address Sanitizer, with three opt-in benchmarks skipped in normal runs. Eight new regressions cover:

- 108 pixel comparisons across twelve amounts, three color palettes and three scales.
- Identical image identity through 1,000 presentation updates; the baseline keeps generating new images.
- Every transition between absent, premium-required and two paid amounts, including peer reuse.
- Cache invalidation for text/locale formatting, each color, font, scale, icon identity and dynamic light/dark colors.
- Release of removed views/caches and replaced images; matching insertion/removal animations.

Release medians in microseconds per presentation update, nine alternating batches of 2,000 iterations:

| Scenario | Before | After |
|---|---:|---:|
| Unchanged paid badge | 41.672 | 3.944 |
| Changing amount | 40.596 | 41.570 |
| New row with paid badge | 69.912 | 71.385 |
| Premium-required icon | 0.199 | 0.203 |
| No badge | 0.0283 | 0.0286 |

Unchanged paid-badge updates are about 10.6× faster in this isolated path. Changing amounts and new rows have about 2% overhead from cache bookkeeping. There is no global image cache, and this is not an app-wide speedup or resident-memory measurement. Raw trials, source hashes and validation summaries are stored in `paid-badge-results.json`, `paid-badge-provenance.json` and `paid-badge-validation.json`.

```sh
python3 tools/perflab/ShortPeerRowLab/prepare.py
swift test --package-path tools/perflab/ShortPeerRowLab --scratch-path /tmp/ShortPeerRowLab-debug
swift test -c release --package-path tools/perflab/ShortPeerRowLab --scratch-path /tmp/ShortPeerRowLab-release
swift test --sanitize address --package-path tools/perflab/ShortPeerRowLab --scratch-path /tmp/ShortPeerRowLab-asan
SHORT_PEER_PAID_BADGE_BENCHMARK=1 swift test -c release --skip-build --package-path tools/perflab/ShortPeerRowLab --scratch-path /tmp/ShortPeerRowLab-release --filter PaidBadgeTests.testPaidBadgeBenchmark
```

Run the benchmark after other builds have finished. Its output is `/tmp/short-peer-paid-badge-benchmark.json`.

## Deferred selected-text pass

`ShortPeerRowItem` previously shaped and retained normal and selected versions of both title and status even when only normal text was ever drawn. It now creates selected text on first access and retains it for the current effective widths. `prepare(true)` eagerly prepares both variants, including when the width cache hits, so rows already selected keep their preparation behavior. Resizing invalidates and releases the selected layouts. The public getters remain available to hover drawing without requiring another preparation call.

A row with title and status that has never needed selected text retains two `TextNodeLayout`/`TextNode` pairs instead of four. This is an object-count reduction, not a measured reduction in total process memory. There is no additional global cache. Once selected text is requested, the item retains the same four pairs as before.

The harness extracts the production getters, backing fields and preparation method. `ReferenceEagerPrepare.swift.txt` preserves the immediately preceding implementation from `d0610bf3d`; extraction verifies it against Git. Existing preparation, pixel, accessory, paid-badge and observer tests remain in the suite. Thirty functional tests pass in debug, release and Address Sanitizer, with four optional benchmarks skipped in the validation runs. The new tests cover lazy allocation, eager selected preparation, independent title/status access, unchanged-width selection, resize invalidation and release, absent/empty text, 1,000 retained rows and 72 exact nonblank pixel pairs after multiple unvisited resizes across six text samples, legacy/modern geometry and 1×/2×/3× drawing. Production also parses in normal and `SHARE` configurations.

Release medians in microseconds per operation, nine alternating batches of 2,000 iterations:

| Scenario | Before | After |
|---|---:|---:|
| New unselected item and text preparation | 34.784 | 18.758 |
| New selected item and text preparation | 35.005 | 35.029 |
| New item, immediately read all text variants | 35.048 | 35.243 |
| Unselected resize | 33.525 | 16.301 |
| Selected resize | 33.702 | 33.733 |
| Unchanged preparation | 0.100 | 0.100 |
| Repeated selected preparation and reads | 0.109 | 0.124 |
| First selected-text access after unselected preparation | 1.634 | 17.015 |

Initial unselected preparation is about 46% faster and unselected resize about 51% faster in this isolated harness. The tradeoff is approximately 15 microseconds of deferred work at first selected-text access in this run; subsequent reads reuse it. Already-selected preparation and immediate access to every variant are essentially unchanged. These timings include the fixture item and real text shaping, not the entire production initializer, avatar setup, row view or app scrolling. No full Telegram build or end-to-end hover test was run.

Raw trials are in `selection-results.json`; source hashes, validation details and test logs are in `selection-provenance.json`, `selection-validation.json` and `selection-logs/`.

```sh
python3 tools/perflab/ShortPeerRowLab/prepare.py
swift test --package-path tools/perflab/ShortPeerRowLab --scratch-path /tmp/ShortPeerRowLab-debug
swift test -c release --package-path tools/perflab/ShortPeerRowLab --scratch-path /tmp/ShortPeerRowLab-release
swift test --sanitize address --package-path tools/perflab/ShortPeerRowLab --scratch-path /tmp/ShortPeerRowLab-asan
SHORT_PEER_SELECTION_BENCHMARK=1 swift test -c release --skip-build --package-path tools/perflab/ShortPeerRowLab --scratch-path /tmp/ShortPeerRowLab-release --filter SelectionLayoutTests.testSelectionBenchmark
```

Run the benchmark after builds finish. Its output is `/tmp/short-peer-selection-benchmark.json`.
