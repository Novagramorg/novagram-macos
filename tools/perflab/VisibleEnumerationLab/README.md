# Safe visible-row iteration and cheaper checked lookup

`TableView.enumerateVisibleItems` read each index from the live list after obtaining a native visible range. If a callback cleared or shortened that list, the next access could trap. An isolated native-window reproduction clears four rows from the first callback and crashes the original implementation with `Array` index out of range. The sanitized stack and process output are retained in `results/baseline-crash.*`.

The final implementation keeps live-list semantics: replacements at later indexes are observed, an early false return stops iteration, and an index that no longer exists ends iteration. Empty, negative, stale and overflowing ranges are handled without an invalid subscript. Reverse traversal bounds its starting index against the current list. Nested callbacks may enumerate a replacement list independently.

The shared `optionalItem(at:)` lookup rejects negative indexes before touching the array and uses one local array value for bounds checking and retrieval, avoiding the former separate `count` and `item(at:)` accesses. Its local array lifetime ends before enumeration invokes user code. No snapshot is held across callbacks, no unsafe pointer code is shipped, and no persistent cache or state is added. Storage-identity tests prove that callback mutations do not force a whole-list copy at 100 or 10,000 rows. This is not a total-process memory measurement.

## Reproduce

```sh
python3 tools/perflab/VisibleEnumerationLab/prepare-isolated.py /tmp/VisibleEnumerationValidation
swift test --package-path /tmp/VisibleEnumerationValidation --scratch-path /tmp/VisibleEnumerationValidation-build -c release
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/VisibleEnumerationValidation --scratch-path /tmp/VisibleEnumerationValidation-asan --sanitize address
swift test --package-path /tmp/VisibleEnumerationValidation/TGUIKit --scratch-path /tmp/VisibleEnumerationValidation-kit -c release
ENUMERATION_BENCHMARK=1 ENUMERATION_FINAL=1 swift test --package-path /tmp/VisibleEnumerationValidation --scratch-path /tmp/VisibleEnumerationValidation-build -c release --skip-build --filter EnumerationBenchmarkTests
cp /tmp/visible-enumeration-benchmark.json /tmp/enumeration-forward.json
ENUMERATION_BENCHMARK=1 ENUMERATION_FINAL=1 ENUMERATION_REVERSE=1 swift test --package-path /tmp/VisibleEnumerationValidation --scratch-path /tmp/VisibleEnumerationValidation-build -c release --skip-build --filter EnumerationBenchmarkTests
cp /tmp/visible-enumeration-benchmark.json /tmp/enumeration-reverse.json
```

Use fresh output directories and run timing without competing builds. `ENUMERATION_BASELINE_CRASH=1` enables the deliberately crashing original regression test; leave it unset for ordinary validation. The generator requires the captured original or exact final TableView source and freezes two complete TGUIKit modules. Their production difference is limited to the two methods. Test-only inspection and rejected candidate extensions expose buffer identity and support comparisons; they are not included in the app. The reference preserves unrelated pending scroll-completion edits present when captured.

## Measured results and costs

The [complete median table](results/medians.md) reports microseconds per operation, with positive percentages meaning less CPU time. Each process runs nine alternating paired batches; a second process reverses initial order. Direct lookups use one million iterations per batch, iteration workloads use 200,000, and mutation workloads use 20,000. Both original and candidate iteration are invoked through stored method references. Tables are attached to hidden native windows. Transactions drain outside timed batches.

Valid checked lookup takes 14.4–14.8 ns instead of 19.3–19.6 ns, using 24–26% less time. Negative lookup uses 57–61% less time. Nonnegative out-of-range lookup is 5–6% slower, an increase of about 0.5 ns.

The iterator's additional safety has a measured cost. Unchanged-list and early-exit fixtures are 9–21% slower, adding approximately 18–279 ns per call across 1/8/24/100 visible rows. Complete 24-row iteration grows from about 0.47 µs to 0.55–0.56 µs. The fixtures that remove and re-add a row outside the viewport are 11–51% slower, adding 0.07–0.36 µs. These mutation timings vary more between processes, and are retained without claiming a gain. The final choice favors simple checked live access over snapshot semantics, unsafe buffers or an additional mutation-version mechanism.

This change is a correctness fix plus a small shared lookup optimization. It does not establish an improvement in overall chat scrolling, presented-frame rate, or application memory. No full app build or end-to-end frame pacing measurement was performed.

## Validation

Seven focused tests pass in release and Address Sanitizer, with leak detection disabled. There are 288 native viewport/inset/direction/early-exit scenarios for the production candidate against the original, and 864 additional trace comparisons for experimental snapshot alternatives. The native scenarios cover flipped and nonflipped tables, content insets, fractional scroll positions and expanded or reduced viewport ranges.

Additional focused cases cover clearing, live replacement, removal outside the viewport, tail shrink/regrow, invalid lookup indexes, and stale ranges. One focused test documents the intentionally different snapshot semantics of rejected alternatives. Six tests added to the production TGUIKit target cover real native-window clearing in both directions, later replacement visibility, stale/overflowing ranges with early exit, shrink/regrow, lookup identity after replacement/removal, and nested enumeration after clearing.

The complete frozen TGUIKit suite passes 413 functional tests with 18 optional measurements skipped. All 668 recorded compiler inputs remain unchanged after validation. The tested source, measured source and worktree implementation match; the lab appends test-only extensions. Complete logs, input hashes, final source snapshot, baseline crash evidence and raw timing batches are retained in `results`.

## Rejected experiments

Holding an ArraySlice avoids repeated lookup work but changes live replacement semantics and can copy the entire backing list when a callback mutates even an offscreen row. Copying only the visible subset or using temporary buffers avoids that whole-list copy but still changes semantics and can penalize early exits. Per-index guards, optional lookup, mutation-version tracking and a scoped unsafe-buffer lookup were compared. Scoped unsafe access showed no useful advantage over the selected normal array access. The temporary-buffer variants remain test-only.

Early exploratory timings used a direct baseline call versus a stored candidate method reference; those runs are not final performance evidence. The final harness uses symmetric method-reference calls. The `balanced-forward` and `selected-forward` exploratory runs also had a compiler present when checked after measurement and are excluded from reported results. Both final runs had no matching compiler processes in their pre/post checks. An initial test spy accidentally returned a forced stale range during AppKit's own removal callbacks; the corrected spy supplies its forced range only once, and the fixture failure is retained separately. Full machine crash reports are excluded; only sanitized relevant crash information is archived. Logs normalize trailing whitespace.
