# Emoji suggestion performance regression checks

From the repository root:

```sh
python3 tools/tests/emoji-suggestions/run.py
python3 tools/tests/emoji-suggestions/run.py --release
python3 tools/tests/emoji-suggestions/run.py --benchmark
```

The runner extracts the current `recentEmojiSuggestions` helper and candidate-list expression from `ChatInterfaceStateContextQueries.swift`, verifies both suggestion paths use them, and compiles them in a temporary directory. `Reference.swift` preserves the original algorithms from that file's `d1facc04e` version. The fixture types adapt media IDs, file accessors and featured packs without loading Telegram or an account. Their file objects allow identity comparisons and track parsing and featured-file access counts. String `fixed` currently returns its input in production and in the fixture.

The 30,083 comparisons cover empty inputs, missing files, repeated IDs, duplicate available files with different contents, namespaces, optional emoji text, Unicode, ordered object identity, unchanged parse counts, and featured packs that end before or after the 400-file limit. Candidate collection preserves every installed file and the first 400 featured files, including duplicates. It reads at most 400 featured file accessors. The recent lookup returns the first matching accessor and still parses once per selected recent entry.

The old featured-pack collector repeatedly concatenated the growing result, copying earlier entries for every pack, then discarded everything beyond the first 400 files. The new lazy traversal stops at that limit. Recent lookup uses `first(where:)` instead of allocating a complete filtered array for each ID. Text suppression keeps the original array membership behavior; empty recent lists and empty suppression lists avoid unnecessary filtering.

Release measurements on 2026-10-15 used seven measured batches after warmup, alternating baseline and candidate order. Each synthetic pack contains 20 files; all cases also include 200 installed files:

| Featured packs | Baseline | Optimized |
| --- | ---: | ---: |
| 5 | 3.42 µs | 3.09 µs |
| 20 | 22.97 µs | 9.95 µs |
| 100 | 396.05 µs | 10.01 µs |
| 500, stress case | 9,467.53 µs | 10.23 µs |

These measure isolated algorithms with lightweight adapters, not complete suggestion latency or application FPS. Real flat-buffer decoding, preference normalization, signals, and UI rendering are outside the harness. Debug and release checks passed, and the edited production file passed Swift syntax parsing. A full ChatUI build and signed-in UI smoke test were not run.
