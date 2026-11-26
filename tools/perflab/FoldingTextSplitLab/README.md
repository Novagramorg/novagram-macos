# Folding text split lab

`FoldingTextLayout.make` splits attributed chat text into ordinary and quoted blocks before measuring it. The old splitter enumerated all style attributes and constructed attributed substrings merely to inspect their first character. The candidate enumerates only quote attributes and reads the first UTF-16 code unit directly. It retains the existing leading-newline rules, including trimming the final quoted block.

`prepare.py` extracts the actual production method and quote key. `Reference.swift.txt` preserves the original method from `a878b977c`; `provenance.json` records source hashes. Both implementations run against real Foundation attributed strings in the same executable. There is no retained cache or new lifetime assumption.

## Validation

Seven functional tests pass in debug, release, and Address Sanitizer builds. One additional opt-in benchmark is skipped in normal runs. Coverage includes:

- All quote boundaries in selected UTF-16 strings, including surrogate pairs, combining sequences, flags, RTL, CRLF, and Unicode separators.
- 2,500 deterministic randomized strings with overlapping quote/style mutations and exact range and attributed-block equality against the original.
- Adjacent quote objects, nonnil false-valued attributes, dense unrelated styles, empty input, newline-only input, final quoted blocks, and input mutation between calls.
- A real NSAttributedString subclass records temporary substring requests: the original requests them, the candidate makes zero.

Production Swift syntax parsing and `git diff --check` pass. Logs and their hashes are included. This isolates the production splitting method; it does not build Telegram or measure whole-message layout/rendering.

## Release benchmark

Apple Silicon, Swift 6.3.3. Median microseconds per split, nine alternating batches of 500 iterations after warmup, with autorelease pools. All cases first verify output equality. Raw trials are in `benchmark.json`.

| Input | Original µs | Candidate µs | Speedup |
|---|---:|---:|---:|
| Short plain message | 0.230 | 0.157 | 1.47× |
| Long plain message | 0.246 | 0.148 | 1.66× |
| 4,096 characters, 512 style runs | 162.546 | 9.709 | 16.74× |
| Many quote blocks | 104.623 | 12.569 | 8.32× |
| Many quote blocks with dense styles | 955.143 | 31.844 | 29.99× |

The larger gains apply to styled/quoted synthetic inputs, not overall chat performance. Plain-message savings are small in absolute terms. Eliminating temporary attributed substrings is independently verified; peak memory was not measured.

## Reproduce

```sh
python3 tools/perflab/FoldingTextSplitLab/prepare.py
swift test --package-path tools/perflab/FoldingTextSplitLab --scratch-path /tmp/FoldingTextSplitLab-debug
swift test -c release --package-path tools/perflab/FoldingTextSplitLab --scratch-path /tmp/FoldingTextSplitLab-release
swift test --sanitize address --package-path tools/perflab/FoldingTextSplitLab --scratch-path /tmp/FoldingTextSplitLab-asan
FOLDING_SPLIT_BENCHMARK=1 swift test -c release --skip-build --package-path tools/perflab/FoldingTextSplitLab --scratch-path /tmp/FoldingTextSplitLab-release --filter testSplitBenchmark
```

Run the benchmark after builds and other performance tests finish. It writes `/tmp/folding-text-split-benchmark.json`.
