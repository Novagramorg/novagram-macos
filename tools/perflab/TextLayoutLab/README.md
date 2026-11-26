# Text layout measurement lab

Standalone AppKit/Core Text executable and regression suite for `TextViewLayout.measure`. It needs no Telegram account, full app build, network dependencies, or telegram-ios build. Run on macOS with Xcode command-line tools.

## Production change

Each layout retains its prepared attributed string, Core Text typesetter, and decoration-presence flag for source strings containing 64–4096 UTF-16 units. A repeated measurement reuses this preparation only after checking immutable attribute values and attributed-string equality. `setAttributedString` invalidates it explicitly. Mutable attributed strings are supported through snapshot comparison.

Permitted attribute values are fonts, numbers, URLs, immutable strings, component-based colors, and immutable paragraph styles without mutable children. Dynamic colors, text blocks/lists, custom tab options, and unknown attribute objects take the original preparation path. The first measurement defers the eligibility scan until reuse. Short labels avoid cache allocation; long messages avoid retaining an additional large typesetter. There is one entry per layout and no global cache.

Every measurement still reconstructs lines, cutouts, alignment, geometry, decorations, and hit-testing data. Layout options and externally modified line arrays therefore remain observable. A layout remains stateful: concurrent measurement of the same instance is unsupported, just as before. Independent instances and sequential migration between queues are tested.

## Run

```sh
tools/perflab/TextLayoutLab/run.sh test
tools/perflab/TextLayoutLab/run.sh release-test
tools/perflab/TextLayoutLab/run.sh tsan
tools/perflab/TextLayoutLab/run.sh asan
tools/perflab/TextLayoutLab/run.sh bench > /tmp/text-layout-benchmark.json
tools/perflab/TextLayoutLab/run.sh bench --memory baseline
tools/perflab/TextLayoutLab/run.sh bench --memory candidate
tools/perflab/TextLayoutLab/run.sh bench --memory baseline --truncated
tools/perflab/TextLayoutLab/run.sh bench --memory candidate --truncated
```

Build products go to `${TMPDIR}/telegram-text-layout-lab`. Set `TEXT_LAYOUT_LAB_WORK` to separate directories when running configurations concurrently. Run benchmarks alone for more stable timing.

`prepare.py` extracts the current production initializer, measurement methods, setter, geometry reset, hit-test method, and supporting layout types. It compiles the production cache helper directly. The reference measurement implementation is frozen in `Fixtures/Baseline.swift.txt`; nonmeasurement scaffolding includes an identity equality operator. `Support.swift.txt` supplies minimal palette, interaction, selection, and quote-header stand-ins. The executable uses real AppKit fonts, Core Text shaping, and bitmap drawing. `provenance.json` records the exact source and fixture hashes.

## Measured result

Recorded on 2026-10-15, Apple Silicon, macOS 26.4, Swift 6.3.3. Times are medians of nine paired batches, alternating execution order after warm-up. Cold measurements create a new layout. Resize measurements reuse one layout and alternate widths 280/290. These are component measurements, not app opening times or frame-rate measurements.

| Scenario | UTF-16 units | Cold speedup | Resize µs per measurement, baseline → candidate | Resize speedup |
|---|---:|---:|---:|---:|
| short-label | 18 | 1.00× | 4.3 → 4.2 | 1.01× |
| chat-paragraph | 260 | 1.00× | 44.8 → 10.7 | 4.21× |
| unicode | 67 | 1.00× | 104.9 → 4.5 | 23.49× |
| plain-4k | 4056 | 1.00× | 1650.6 → 1157.2 | 1.43× |
| links-4k | 4056 | 1.00× | 3186.5 → 2397.3 | 1.33× |
| links-16k | 16640 | 1.00× | 25638.0 → 25618.5 | 1.00× |
| decorations | 4056 | 1.00× | 2704.8 → 2203.9 | 1.23× |
| quotes | 4056 | 1.00× | 1973.6 → 1997.9 | 0.99× |
| color-markers | 4056 | 1.00× | 3144.0 → 3245.4 | 0.97× |
| embedded | 4056 | 1.00× | 3786.8 → 2780.0 | 1.36× |
| mixed-fonts | 4056 | 1.00× | 2688.3 → 1719.7 | 1.56× |
| truncated-rich | 4056 | 1.00× | 1103.3 → 318.4 | 3.46× |

Cold performance is essentially unchanged. The largest gain is specific to the mixed-script Unicode fixture, where typesetter preparation dominates. Quotes and color markers intentionally reject reuse; in this run they were approximately 1.2% and 3.1% slower on repeated measurement. Real embedded emoji payloads may also reject reuse; the benchmark's embedded markers are integers. These results do not imply universal acceleration across all attributes or strings.

Memory probes retain 300 unique layouts, each containing 4028 UTF-16 units plus a short numeric prefix, after two width measurements. Separate processes measure resident-size growth after warm-up:

| Scenario | Baseline growth | Candidate growth | Difference across 300 layouts |
|---|---:|---:|---:|
| Full layout | 60.12 MiB | 60.47 MiB | 0.34 MiB |
| Three-line preview | 35.89 MiB | 36.16 MiB | 0.27 MiB |

Resident size is a coarse, noisy process metric, not an allocation or retained-memory guarantee. The per-instance length cap limits the tradeoff; it does not impose a global memory budget.

## Math approaches tested

- **Glyph-advance prefix sums and binary search for wrapping:** rejected. The runnable experiment gives `AVATAR To Wa` a width of 93.84375 instead of Core Text's 88.130859375. Arabic, Indic, and emoji fail simple glyph mapping; line-break mismatches also occur for Latin text. Advances alone do not preserve shaping, fallback, kerning, or word-break rules.
- **Binary interval intersection:** about 13.6× faster than a full scan on 400 ordered lines and 800 queries. The experiment validates ordered, nonoverlapping ranges and falls back for truncated or unordered ranges; 20,000 randomized queries match full intersection. A trial integrating this with consolidated attribute scans did not improve complete cold measurements consistently and regressed some small/rich cases, so those production changes were removed. The combined prototype is not part of this lab; the interval experiment remains runnable.
- **Monotonic interval sweep:** about 19.9× faster than binary intersection in the strictly ordered synthetic workload. Attribute queries and truncated line ranges do not universally satisfy its ordering assumptions. It remains an experiment.
- **Prepared typesetter reuse:** preserves Core Text's existing shaping and wrapping math while eliminating repeated setup. This is the only production optimization in this change.

## Correctness evidence

All **17 tests pass** in debug, release, Address Sanitizer, and Thread Sanitizer. The suite compares initial and repeated measurements across more than 1800 fixture layouts, including 1000 seeded randomized inputs. Coverage includes:

- RTL, Arabic, Indic, CJK, combining marks, emoji sequences, tabs, newlines, soft hyphens, and all truncation modes.
- Fonts, kerning, ligatures, paragraph indents, cutouts, spacing, alignment, quotes, links, embedded markers, underline, strike-through, and color markers.
- Line ranges and frames, every UTF-16 offset, sampled Core Text hit positions, line-index hit tests, decoration rectangles, and exact glyph bitmap bytes for selected fixtures before and after reuse.
- Mutable source edits, font/paragraph changes, setter invalidation, cache length boundaries, mutable paragraph children, dynamic colors, option changes, cleared line arrays, independent parallel layouts, and sequential queue migration.

The bitmap check draws actual `CTLine` objects. It does not render the complete production `TextView`; decoration geometry is compared separately. Some cold baseline bugs may be shared by both implementations: equivalence is evidence against regressions, not a proof that all existing behavior is correct.

The edited production files pass Swift syntax parsing. The helper also typechecks in Swift 5 mode targeting x86_64 macOS 10.13. The full TGUIKit dependency graph and main app have not been built in this lab. A main-app smoke pass should still cover chat pane resizing, message editing, theme/font changes, RTL/emoji messages, links/selection, and truncated previews.

Raw outputs, source hashes, and validation metadata are in [Evidence](Evidence/). No telegram-ios source is changed by this work.
