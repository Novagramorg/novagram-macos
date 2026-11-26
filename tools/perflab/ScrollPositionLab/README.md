# Scroll position geometry reads

ScrollView now reads its clip view, bounds and document rectangle once per position/reset call. TableView reads the document rectangle once when an observer exists and avoids reading it when no observer needs a position. Its live-scrolling and point-transform callbacks still execute in their original order. The observer is checked after the point callback, allowing that callback to install or remove it. There is no persistent geometry cache or new instance state.

## Reproduce

```sh
python3 tools/perflab/ScrollPositionLab/prepare-isolated.py /tmp/ScrollPositionValidation
swift test --package-path /tmp/ScrollPositionValidation --scratch-path /tmp/ScrollPositionValidation-build -c release
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/ScrollPositionValidation --scratch-path /tmp/ScrollPositionValidation-asan --sanitize address
POSITION_BENCHMARK=1 swift test --package-path /tmp/ScrollPositionValidation --scratch-path /tmp/ScrollPositionValidation-build -c release --skip-build --filter PositionBenchmarkTests
cp /tmp/scroll-position-benchmark.json /tmp/position-forward.json
POSITION_BENCHMARK=1 POSITION_REVERSE=1 swift test --package-path /tmp/ScrollPositionValidation --scratch-path /tmp/ScrollPositionValidation-build -c release --skip-build --filter PositionBenchmarkTests
cp /tmp/scroll-position-benchmark.json /tmp/position-reverse.json
swift test --package-path /tmp/ScrollPositionValidation/TGUIKit --scratch-path /tmp/ScrollPositionValidation-kit -c release
```

Use a fresh output directory. Run timing without other builds. The generator freezes complete TGUIKit libraries for both implementations, restoring the captured original ScrollView.swift and TableView.swift in the baseline. Other production sources match. The TableView reference includes unrelated pending changes already present before this optimization; only the scroll-observer block is changed by this experiment and commit.

## Measurements

Release medians in microseconds per operation; nine alternating paired batches and a second process with reversed initial order. Positive percentages mean less CPU time. Final batches contain one million reporting/reset calls or twenty thousand move-and-report calls. Preliminary shorter batches are retained separately; final claims use the longer batches.

| Workload | Forward | Reversed |
| --- | ---: | ---: |
| attached_move_and_report_observed_false | 4.571 → 4.494 (+1.7%) | 4.317 → 4.239 (+1.8%) |
| attached_move_and_report_observed_true | 4.581 → 4.502 (+1.7%) | 4.314 → 4.242 (+1.7%) |
| attached_table_observed | 0.134 → 0.118 (+12.1%) | 0.139 → 0.125 (+9.9%) |
| attached_table_transformed_observed | 0.148 → 0.115 (+22.4%) | 0.143 → 0.127 (+10.8%) |
| attached_table_unobserved | 0.123 → 0.095 (+22.6%) | 0.131 → 0.094 (+27.9%) |
| reset_scroll | 0.073 → 0.036 (+50.5%) | 0.074 → 0.037 (+49.3%) |
| scroll_position | 0.077 → 0.039 (+49.0%) | 0.076 → 0.039 (+48.6%) |

Scroll-position reporting saves approximately 0.037–0.038 microseconds per call (about 49%). Reset reporting saves approximately 0.037 microseconds (49–51%). Table callbacks save 0.014–0.037 microseconds; observed callbacks vary between 10% and 22% less time across the runs. These are small absolute savings despite substantial relative percentages.

The broader fixture attaches two 1,000-row tables to a hidden native window, moves their clip offsets, and explicitly calls the changed reporting paths. It takes 1.7–1.8% less time. It does not drain the run loop, rasterize/present every row, or measure complete scroll events, live chat frame pacing, text measurement, or media decoding. Transactions drain between timing batches. This is evidence of reduced shared reporting work, not a whole-app FPS estimate. No memory reduction is claimed.

## Validation

Seven focused tests run against each implementation, fourteen total, passing release and Address Sanitizer with leak detection disabled. The geometry matrix checks 144 sequential states per implementation, covering both document orientations, fractional offsets, unchanged positions, changing document/viewport sizes, short documents, content insets and direction history. Further tests cover resetting history, removing the document, fresh geometry after mutation, measured document-query counts, unobserved point callbacks, observer installation/removal during callbacks, document resizing during callbacks, and reentrant row removal. The baseline and candidate have different expected query counts but identical behavior expectations.

The seven candidate tests are also installed in the production TGUIKit test target. The full frozen suite passes 404 functional tests, with 18 optional measurements skipped. Existing tests include coalesced final-position delivery, row mutation during scroll listeners, sticky headers, visible ranges and animation completion.

A fresh generator reproduces 512 Swift source/test files across both modules and the lab. All 665 recorded compiler inputs remain unchanged. Both measured production files exactly match the current worktree. Only benchmark iteration counts changed after Address Sanitizer and complete-suite validation; production and functional tests are unchanged. The earlier benchmark source and input manifest are retained. The full application has not been built by this lab.

The first test compilation caught a fixture name colliding with AppKit's Objective-C flipped getter and an ambiguous optional .none assertion. Both test issues were fixed before any measurements; that diagnostic log is retained. Callback fixtures clear their closures at teardown to avoid retaining test tables. Archived text logs normalize trailing whitespace.
