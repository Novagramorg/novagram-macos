# Chat metadata layout reuse

This native macOS test package extracts the counter, forwarded-header, and guest-badge sizing blocks verbatim from `ChatRowItem.makeSize`. It compares the working-tree implementation with commit `84be5dd1a`, using the real TGUIKit TextViewLayout, Core Text measurement, block-image generation, and TextView drawing. The small environment fixture supplies model flags, colors, and strings without building TelegramCore or the full app.

Run from the repository root:

```sh
python3 tools/perflab/ChatMetadataLayoutLab/prepare.py
swift test --package-path tools/perflab/ChatMetadataLayoutLab -c release
CHAT_METADATA_BENCHMARK=1 swift test --package-path tools/perflab/ChatMetadataLayoutLab -c release
swift test --package-path tools/perflab/ChatMetadataLayoutLab --sanitize address
swift test --package-path tools/perflab/ChatMetadataLayoutLab --sanitize thread
```

Use separate scratch paths for sanitizers and release builds. Run them sequentially. The opt-in benchmark writes `/tmp/chat-metadata-benchmark.json` with all nine alternating paired batches, each containing 10,000 operations after warmup. Timings include autorelease-pool cleanup. Regenerate extracted code after changing production sources; `generation.json` records source and generated-code hashes.

## Behavior and evidence

The initial seven tests produced 16 expected assertion failures against the baseline: eight counter line-identity failures, five header layout-identity failures, and three badge expansion failures. The corrected implementation has 13 functional tests plus an optional benchmark. Coverage includes:

- Bubble and list widths, truncation, Arabic digits, empty strings, replacement layouts, and dropped-size recovery.
- Forwarded headers with independently varied entry/render modes, full/short/absent headers, PSA text, localization, color changes, and release of replaced or hidden layouts.
- Guest-badge shrink/expand sequences, widths at the natural-size boundary, repeated sizing, tiny widths, invalidation, and stable Core Text lines and block-image identity.
- 366 exact raster comparisons at drawing transforms of 1x and 2x, including 60 empty-layout comparisons; nonempty fixtures also require nonzero pixels. Geometry, attributed text, and embedded-item rectangles are checked separately.

The badge uses an opaque embedded-item marker with the same attribute shape as production. It exercises text preparation and reserved inline geometry, but does not fetch or draw the eye icon. Palette/model fixtures do not replace TGUIKit rendering. This package does not instantiate the complete ChatRowItem, exercise a live chat, or prove end-to-end frame-time or application-memory gains. Whole-file parsing checks syntax separately; the main application was not built.

## Measured result

Release medians on the local machine, microseconds per operation:

| Operation | Baseline | Candidate |
|---|---:|---:|
| Repeated bubble view/reply counters | 5.255 | 0.025 |
| Repeated forwarded header | 5.806 | 0.849 |
| Already-sized guest badge | 0.011 | 0.018 |
| Combined repeated metadata sizing | 12.039 | 0.900 |
| List counters with changing widths | 5.159 | 5.162 |

The combined fixture saves about 11 microseconds per repeated sizing pass. It contains all three metadata elements, which many real rows do not have. The badge fix adds a few nanoseconds to its already-fast unchanged path. Genuine width changes retain the original measurement cost. Avoided Core Text line/layout creation is verified by identity tests; process memory and full chat scrolling were not benchmarked.

Reuse is local to existing row-owned layouts, with no additional per-row fields or shared cache. Header text/style changes replace the layout. Zero-sized layouts remeasure. Truncated badges remeasure when their available width changes, allowing expansion; naturally fitting badges retain their existing layout and block image.

Validation passed: 518 functional release tests (13 metadata, 371 TGUIKit, 134 chat-layer), 13 focused tests under Address Sanitizer, and the same 13 under Thread Sanitizer. Whole-file parsing also passed. Benchmark-only tests were skipped in sanitizer and broader regression runs.

Raw logs, benchmark samples, source snapshots, and hashes are stored in `results/` as committed evidence. Generated build files remain ignored.
