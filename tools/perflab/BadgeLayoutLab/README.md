# Badge layout sharing and lazy compact badges

Chat-list items previously measured identical unread text for full and compact badges during construction, even when no compact badge was displayed. Selected badges repeated that work on first access. The view also evaluated the compact badge getter before checking whether it could display the result.

The candidate keeps the regular badge, creates the compact badge on demand, and shares its private measured text with the matching regular badge. Selected variants support either access order. Each badge retains separate size, padding, colors, view ownership and readiness state. No global cache or additional per-badge fields are introduced. ChatListController wraps entries in the current appearance and rebuilds them on appearance changes; sharing remains local to one item and one selected/unselected state. `aroundFill` also now compares against its old value so changing the outer color actually requests display.

## Reproduce

From the repository root:

```sh
python3 tools/perflab/BadgeLayoutLab/prepare.py
BADGE_BENCHMARK=1 swift test --package-path tools/perflab/BadgeLayoutLab --scratch-path /tmp/BadgeLayoutLab-release -c release
swift test --package-path tools/perflab/BadgeLayoutLab --scratch-path /tmp/BadgeLayoutLab-asan --sanitize address
swift test --package-path tools/perflab/BadgeLayoutLab --scratch-path /tmp/BadgeLayoutLab-tsan --sanitize thread
```

The generator extracts construction blocks, selected/unselected accessors and the view condition from actual ChatListUI sources. It compares them with commit `4536e7fd6`. The GRAM predicate is extracted too, adapting `Int32?` to the harness's `Int?`. The outer item, account state and theme are small adapters. BadgeNode, TextNode, View, CoreText and drawing are the actual TGUIKit implementation.

`--baseline` substitutes the original feature snippets; it does not restore the TGUIKit library. The recorded initial baseline run used the original BadgeNode and the first five regression tests, before adding the shared initializer tests. It produced 15 expected assertions in five tests. Do not describe a current `--baseline` run as a complete original-library baseline.

## Results

Final focused release: 14 tests, zero failures, including the enabled benchmark. Address and Thread Sanitizer: 13 functional tests pass; the timing test is skipped.

There are 110 exact nonblank bitmap comparisons covering ordinary/archive badges, selection, compact/full display, independent colors and padding, emoji, RTL and multiline input, and mutable source text. Raster contexts use 1x and 2x scales; detached views use the harness's 2x system backing scale for text drawing. These are badge drawings, not full-row screenshots or a full Telegram UI test.

Additional checks cover unused getter avoidance, unread/mention/GRAM states, selection round trips, independent display delegates/readiness, release after the last shared owner, and 64 concurrent copies of an already measured layout.

Nine paired release batches alternate baseline/candidate order, with 1,000 setups per batch. Counts cycle from 1 through 200. Medians, in microseconds per setup (numerically equivalent to milliseconds per 1,000 setups):

| State | Original | Candidate |
| --- | ---: | ---: |
| Normal, full badge only | 5.560 | 2.741 |
| Normal, both badges | 5.485 | 3.030 |
| Selected, full badge only | 8.634 | 5.789 |
| Selected, both badges | 10.951 | 5.787 |

Direct retained-object measurements for a representative item:

| State | Badges before/after | Text layouts before/after | Direct bytes before/after |
| --- | --- | --- | --- |
| Normal, full only | 2 / 1 | 2 / 1 | 672 / 336 |
| Normal, both | 2 / 2 | 2 / 1 | 672 / 512 |
| Selected, full only | 3 / 2 | 3 / 2 | 1,008 / 672 |
| Selected, both | 4 / 3 | 4 / 2 | 1,344 / 848 |

Selected cases include ordinary caches created during item setup; they do not first access the ordinary compact badge. Bytes sum unique allocations for BadgeNode, TextNodeLayout, TextNode and the readiness Promise only. They exclude attributed strings, CoreText runs/lines, array storage, items, views, layers and process memory. These are partial direct-object measurements, not whole-app memory savings. Timings measure extracted badge setup, not total row construction, chat-opening latency or FPS.

Archived logs, raw timings and source hashes accompany this report. Broad regression results are recorded in `provenance.json`. No full Telegram build was performed.
