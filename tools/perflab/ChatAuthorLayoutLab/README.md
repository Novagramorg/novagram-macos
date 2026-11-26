# Chat author and forward-name layout reuse

This native macOS lab extracts the author and forward-name sizing blocks verbatim from `ChatRowItem.makeSize`, comparing the working tree with `ba81323e5`. Both implementations use real TGUIKit TextViewLayout, Core Text, link hit testing, and TextView drawing. Small model fixtures provide row flags, badge layouts, and a reply-sizing call recorder.

```sh
python3 tools/perflab/ChatAuthorLayoutLab/prepare.py
swift test --package-path tools/perflab/ChatAuthorLayoutLab -c release
CHAT_AUTHOR_BENCHMARK=1 swift test --package-path tools/perflab/ChatAuthorLayoutLab -c release
swift test --package-path tools/perflab/ChatAuthorLayoutLab --sanitize address
swift test --package-path tools/perflab/ChatAuthorLayoutLab --sanitize thread
```

Run builds sequentially, using separate scratch paths for release and each sanitizer. Regenerate after production changes. `generation.json` records hashes of the original source, current source, and extracted code. The benchmark writes `/tmp/chat-author-benchmark.json` with nine alternating paired batches of 10,000 operations, following warmup and including autorelease-pool cleanup.

## Correctness

The initial seven tests failed nine identity assertions against the original implementation, demonstrating repeated Core Text line creation. The candidate passes nine functional tests plus the optional benchmark:

- Same-width author reuse and forwarded-name reuse when available width remains above its 250-point cap.
- One- and two-line names, long names, emoji, Arabic, Japanese, and empty names.
- Bubble/list modes, side accessories, vertical/horizontal monoforum spacing, badge widths, and date/right-side spacing.
- Narrow/wide transitions, dropped sizes, replacement layouts, and existing zero/negative-width measurement semantics.
- Link hit areas compared across a grid of points, plus an opaque peer-link fixture verifying object identity and callback delivery after reuse.
- Reply sizing calls, arguments, and top offsets remain identical. The test recorder does not implement the real reply model; its internal rendering is outside this lab's scope.
- 488 exact raster pairs at 1x and 2x drawing transforms, with size, line frame, and range comparisons. Empty strings and tiny constraints are explicitly permitted to draw no pixels; other cases require nonzero pixels.

The production call-site audit found these layouts are constructed once per row and read by TextView or chat accessory controls. Badge or effective-width changes still trigger measurement. Replaced or dropped layouts also measure. No new per-row fields, shared cache, or TGUIKit API is introduced. Reply model remeasurement remains outside the reuse guard.

These are extracted production sizing blocks, not an instantiated ChatRowItem or a live-chat benchmark. Native rendering uses the real TGUIKit implementation; application data, callback payloads, and reply-model behavior use fixtures. Whole-file parsing supplements extraction but does not establish that the full application builds.

## Performance

Release medians on the local machine, microseconds per sizing operation:

| Operation | Baseline | Candidate |
|---|---:|---:|
| Repeated author | 5.703 | 0.023 |
| Repeated forward name | 9.541 | 0.018 |
| Both, repeated width | 15.761 | 0.036 |
| Both, alternating widths | 20.260 | 20.237 |
| Both, freshly constructed layouts | 22.323 | 22.312 |

Benchmark attributes include an opaque peer-link object, exercising the conservative text preparation path used for application-specific attributes. The measured benefit concerns repeated sizing; new rows and actual width changes retain their measurement cost. Row memory size is unchanged. Avoided line allocations are supported by identity tests, while process memory and full application frame times were not measured.

Evidence is saved in `results/`: frozen extracted code, source delta, baseline failure log, benchmark samples, sanitizer/regression logs, and validation-source hashes. Previous metadata blocks are independently re-extracted from the updated ChatRowItem and confirmed byte-identical before their regression suite runs.

Validation passed: 156 functional release tests (9 author, 13 metadata, 134 chat-layer), plus the 9 author tests under each of Address Sanitizer and Thread Sanitizer. Whole-file parsing passed. TGUIKit source hashes were unchanged from the previous full 371-test functional release run; that suite was not repeated for this call-site-only change.
