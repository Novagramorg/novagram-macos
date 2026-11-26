# Chat text font overlap lab

The production chat renderer applied bold-italic font to every pairwise intersection of bold and italic ranges. The new helper keeps that path for small inputs (up to 16 ranges of each style, or a single range on either side). For larger inputs it sorts and merges each style's ranges, then walks both lists once. Every emitted intersection gets the same bold-italic font as before; unrelated text attributes and earlier font precedence are preserved.

Run from the repository root:

```sh
python3 tools/perflab/ChatTextFontLab/run.py
python3 tools/perflab/ChatTextFontLab/run.py --benchmark --results tools/perflab/ChatTextFontLab/results.json
python3 tools/perflab/ChatTextFontLab/run.py --sanitize
```

The runner compiles the actual production helper and verifies its call site. The reference preserves the former nested loops. Tests compare complete AppKit attributed strings, including fonts, links, colors, and underline attributes. Inputs cover empty, singleton, threshold boundaries, unsorted, nested, duplicated, adjacent, zero-length, and UTF-16 ranges within multilingual text. There are 1,700 deterministic comparisons, plus 21 benchmark-case comparisons in benchmark mode.

Benchmarks measure the overlap application stage, including attributed-string copying and font application. They exclude entity normalization, earlier formatting, text measurement, and UI rendering. Fonts are real AppKit fonts held constant for both implementations. These results do not establish end-to-end chat latency or FPS. The full app was not built.

`paired` inputs have separated spans within each style, each intersecting one span of the other style. `disjoint` inputs have no positive-length intersections. `overlapping-stress` is deliberately synthetic: upstream entity normalization may merge many such ranges before this stage, so these numbers must not be treated as typical chat gains. The 512-per-style cases are stress workloads too.

The release harness warms both implementations, alternates measurement order, and records medians over seven batches. `results.json` includes the production helper hash, raw timings, and scope. For nonempty inputs the old overlap search is O(B × I); the large-input path is O(B log B + I log I) with linear scratch storage. The empty and singleton paths avoid sorting and scratch arrays.
