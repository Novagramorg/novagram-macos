# Profile and shared-media regression lab

This command-line mini-app compiles the changed production algorithms and signal pipelines without building Telegram. Run from the repository root:

```sh
python3 tools/perflab/PeerMediaProfileLab/prepare.py
swift run --package-path tools/perflab/PeerMediaProfileLab --scratch-path /tmp/PeerMediaProfileLab-debug PeerMediaProfileLab
PEER_MEDIA_RESULTS=tools/perflab/PeerMediaProfileLab/results.json swift run -c release --package-path tools/perflab/PeerMediaProfileLab --scratch-path /tmp/PeerMediaProfileLab-release PeerMediaProfileLab --benchmark
swift run --sanitize address --package-path tools/perflab/PeerMediaProfileLab --scratch-path /tmp/PeerMediaProfileLab-asan PeerMediaProfileLab
```

## Changes

- `PeerInfoController` builds activity dictionaries in place and suppresses identical dictionaries before rebuilding profile entries. TelegramCore can publish a refreshed activity record even when the visible activity is unchanged. Activity changes, removals, and last-value-wins handling of duplicate peer IDs are retained.
- `PeerMediaController` suppresses identical tab tuples before preparing the selected controller and subscribing to its readiness. The later deduplication remains in place. Tab order, selection, and loading changes still propagate, including when a different controller becomes ready later.
- `convertEntries` appends rows while grouping, then reverses each collected group once. This replaces repeated front insertion, which moves the existing array for each message. Existing sorting, stable tie order, date headers, external-search gallery messages, and row styles are preserved.
- Photo/GIF grid state equality now includes the pagination boundaries, hole flags, and anchor used by grid grouping and scrolling. Previously a metadata-only history update could be suppressed, leaving the displayed grid and scroll handler with stale information. Equivalent metadata still deduplicates even across different history-view objects.
- Shared grid sizing always retains at least one column and a positive page size. The previous loops could return zero columns or fail to terminate at zero/negative widths. Ordinary widths retain the same thresholds and page counts. Invalid or unrepresentable geometry falls back to a minimal request.
- The older `PeerMediaGifsController` now preserves message order and shares array storage for loading-only updates. Its history-update path reverses once instead of three times. The current profile GIF tab uses `PeerMediaPhotosController`, so this legacy cleanup is not a measured improvement to the current profile GIF tab.

## Validation

The runner extracts the actual entry conversion, both media state types, profile activity pipeline, tab/readiness pipeline, grid-sizing helper, TGUIKit row-style helper, Postbox `MessageIndex`, and chat date-grouping implementation. It uses the real SwiftSignalKit package. `Reference.swift` and `ReferenceTabPipeline.txt` preserve the corresponding behavior from commit `bea877776`. `provenance.json` records source hashes.

The harness supplies lightweight message, settings, history-view, activity, and controller fixtures. It does not load accounts, fetch resources, instantiate the full UI controllers, measure text, or render views. Media expansion is a fixture transformation shared by both implementations; its production implementation is outside this change. Benchmark messages are lightweight reference objects, so absolute timings are not a measurement of the full Telegram data model.

94,985 debug/sanitizer checks cover 1,200 randomized list conversions, ordered/reversed/shuffled inputs, multiple months and time offsets, equal indexes and duplicates, expanded-media namespaces, empty/loading/search states, stable IDs, activity updates and removals, tab readiness cancellation, equivalent history snapshots, pagination metadata changes, and grid geometry. Normal-size grid results are compared against the old formula across 91,584 combinations, with additional fractional threshold, tiny, zero, negative, nonfinite, and extreme-value cases. Legacy GIF checks compare order and array-buffer identity through repeated loading changes. Release benchmark mode performs 13 additional parity checks.

## Performance evidence and limits

`results.json` records paired medians and raw batches after warmup, alternating baseline/candidate order. In the recorded run, list conversion improved from 268 to 173 microseconds for 1,000 messages and from 3.62 to 0.85 milliseconds for a 5,000-message stress case. Small lists improve only slightly. In a replay of four distinct selected-tab states repeated 100 times each, preparation calls drop from 400 to 4 with identical output; this counts method calls, not controller allocations, because existing code already guards view creation.

Activity deduplication has a small cost: initial subscription adds roughly 0.5–0.6 microseconds, and a changed one-peer event adds about 0.1 microseconds in this harness. Changed 8–10-peer events are similar or faster, while repeated identical events no longer reach profile-entry rebuilding. TelegramCore currently returns at most 10 active peers; larger activity benchmarks are synthetic scaling tests, not typical profile workloads.

These measurements exclude profile-entry creation, table differencing/rendering, resource fetches, and UI interactions. The full app and account-backed profile/media flows were not built or exercised. The edited controller files pass Swift syntax parsing, and the extracted code is compiled and executed by this harness. End-to-end profile-opening latency, scrolling FPS, and visual parity are not established by these results.
