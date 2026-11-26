# Chat status width lab

`ChatRowItem.rightSize` reads `ChatRightView.Frames.width` repeatedly during chat layout. Previously each read built arrays and scanned the rectangles. The candidate computes the same width once when the frames are constructed, using a scalar scan. The rectangles have private setters and are replaced by a new frame set when the row is sized again. There is no global cache or cache invalidation policy.

Run from the repository root:

```sh
python3 tools/perflab/ChatStatusWidthLab/run.py
python3 tools/perflab/ChatStatusWidthLab/run.py --benchmark --results tools/perflab/ChatStatusWidthLab/results.json
python3 tools/perflab/ChatStatusWidthLab/run.py --sanitize
```

The harness compiles the entire actual production `Frames` struct, including its initializer and frame placement helpers. `Reference.swift` preserves the original at `2d15cc5ee`. The geometry extensions are extracted from TGUIKit. `Environment.swift` supplies message flags and already measured text/icon sizes; it does not implement width calculation. Test-only initializers allow arbitrary rectangle fixtures to exercise edge cases beyond ordinary message layouts. The runner also verifies the production `rightSize` access and frame reconstruction call site.

152,624 comparisons cover:

- Every combination of the 17 message/layout flags, including incoming, outgoing, read, sending, failed, source attribution, log interaction, overlays, message effects, paid messages, and dice stakes.
- 5,000 randomized text/icon sizes, fractional geometry, and resizing cases, plus 5,000 state/date changes followed by frame reconstruction. Previously created snapshots must retain their widths.
- Exact equality of all 18 rectangles and total width for constructed rows, repeated reads, and value copies.
- 10,000 arbitrary rectangle sets, including negative coordinates and sizes.
- Empty/zero frames, each field individually, equal right edges, identical rectangles, and nonfinite/extreme coordinates. These protect the original first-maximum behavior, full-rectangle equality when adding status padding, and the deliberate exclusion of some fields from the width scan.

The release benchmark uses 256 mixed status configurations, warms both implementations, alternates their order across nine batches, and records raw timings and medians. It separately measures reading existing frames, constructing frames plus one read, and constructing frames plus eight reads. Checksums consume the results. The optimizer may consolidate repeated reads of the stored width, as it can in the app.

`results.json` records the extracted production struct hash, checksums, frame strides, and timings. On the tested arm64 build, caching adds 8 bytes per frame set (720 to 728 bytes) while removing the temporary arrays and repeated scans. This is a component benchmark, excluding text measurement, message construction, rendering, and full chat layout. It does not establish end-to-end opening latency or FPS. The full app was not built.
