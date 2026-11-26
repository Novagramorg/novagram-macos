# Chat layer sibling ordering

`ChatLayerNode.sortChildren` now scans sibling z-indices once. If they are already ordered, the ordered list shares the children array through Swift copy-on-write instead of allocating and sorting another list. When ordering is needed, a temporary array captures each node's z-index and original offset, sorts in place, and projects the nodes. Equal z-indices retain source order explicitly through their original offsets. Every call still invalidates the scene hit index. No persistent cache, new instance field, public API, or scene lifecycle change is introduced.

The inspected ChatUI call sites currently leave node z-indices at their default zero. The fallback remains tested for arbitrary values, ties, negative values and integer extremes. The keys are local to a single sort and are never reused across updates.

## Reproduce

```sh
python3 tools/perflab/ChatSiblingOrderLab/prepare-isolated.py /tmp/ChatSiblingOrderValidation
swift test --package-path /tmp/ChatSiblingOrderValidation --scratch-path /tmp/ChatSiblingOrderValidation-build -c release --filter SiblingOrderTests
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/ChatSiblingOrderValidation --scratch-path /tmp/ChatSiblingOrderValidation-asan --sanitize address --filter SiblingOrderTests
SIBLING_ORDER_BENCHMARK=1 swift test --package-path /tmp/ChatSiblingOrderValidation --scratch-path /tmp/ChatSiblingOrderValidation-build -c release --skip-build --filter SiblingOrderBenchmarkTests
cp /tmp/chat-sibling-order-benchmark.json /tmp/sibling-forward.json
SIBLING_ORDER_BENCHMARK=1 SIBLING_ORDER_REVERSE=1 swift test --package-path /tmp/ChatSiblingOrderValidation --scratch-path /tmp/ChatSiblingOrderValidation-build -c release --skip-build --filter SiblingOrderBenchmarkTests
cp /tmp/chat-sibling-order-benchmark.json /tmp/sibling-reverse.json
```

Use a fresh output directory and run timing without competing compilers. The generator uses the existing ChatLayerEngineLab host and creates two complete engine modules differing only in ChatLayerScene.swift. Both use the same frozen TGUIKit and model stubs. The baseline restores the captured original scene file. Identical test-only extensions expose private ordering and array storage in each module; production code has no inspection API. The generator verifies the module difference and records source hashes.

The complete host regression suite runs by omitting the test filter. Its real copy-icon fixture needs `CHAT_COPY_ICON_BUNDLE` pointing to an app bundle containing the theme assets; final validation used the existing `/tmp/PrecomposedTintFinalAssets/Probe.app` fixture. Without that fixture the asset test may be skipped. Placeholder theme icons bootstrap the other tests equally in both engines.

## Measurements

Release medians in microseconds per operation. Nine alternating paired batches are repeated in a separate process with reversed initial order. Positive percentages mean less CPU time. Core Animation transactions drain between batches, outside timing. All raw batches and storage checks are saved in results.

| Workload | Forward order | Reversed order |
| --- | ---: | ---: |
| sort_3_equal | 0.194 → 0.043 (+77.8%) | 0.194 → 0.041 (+78.6%) |
| sort_3_mixed | 0.222 → 0.219 (+1.0%) | 0.220 → 0.212 (+3.8%) |
| sort_12_equal | 0.392 → 0.089 (+77.3%) | 0.388 → 0.080 (+79.3%) |
| sort_12_mixed | 1.037 → 0.397 (+61.7%) | 0.995 → 0.392 (+60.6%) |
| sort_64_equal | 1.425 → 0.345 (+75.8%) | 1.412 → 0.345 (+75.6%) |
| sort_64_mixed | 9.707 → 1.539 (+84.1%) | 9.391 → 1.518 (+83.8%) |
| sort_64_late_inversion | 2.828 → 1.534 (+45.8%) | 2.733 → 1.547 (+43.4%) |
| premeasured_row_construction | 67.364 → 64.638 (+4.0%) | 63.676 → 63.187 (+0.8%) |
| attached_row_rebind | 12.362 → 12.250 (+0.9%) | 12.009 → 11.982 (+0.2%) |
| active_scene_reorder_12 | 14.716 → 15.127 (-2.8%) | 14.113 → 14.393 (-2.0%) |

Already-ordered groups of 3–64 nodes take about 76–80% less ordering time. The 64-node mixed case takes about 84% less, and the late-inversion case takes 43–46% less. Small unsorted groups are approximately flat to slightly faster. These are microsecond-level operations, not equivalent gains in total message rendering.

The premeasured row fixture uses real LayerPlainRow instances and four layouts with different widths/content. Construction improves by 0.8–4.0%; attached row rebind/layout is approximately flat (0.2–0.9% less time). The active scene fixture replaces the order of twelve overlapping interactive siblings with a primed hover path and then performs layout/hit testing. It calls updateHover directly, which does not record the last pointer position; child replacement therefore does not recalculate hover in that fixture. It is 2.0–2.8% slower, about 0.28–0.41 microseconds per operation. Thus the broader scene operation is not universally faster even though its sorting component is improved. The fixture excludes complete Telegram message models, media decoding, onscreen frame presentation, and full-app scrolling.

Nonempty already-ordered siblings retain one array buffer instead of two. Tests verify shared buffer identity and correct copy-on-write behavior. This removes an array allocation and a second retained node-reference list; it is not a measured percentage reduction in process memory. Unordered lists still retain a separate ordered buffer, and the fallback uses temporary key storage.

## Correctness and validation

Six focused tests compare the original and candidate modules. Coverage includes all 1,093 lists of lengths zero through six over three z-values; 120 larger mixed/nearly sorted lists of 12, 64 and 129 nodes checked against an independent expected ordering; integer extremes; equal-key stability; retained snapshots; caller mutation; repeated z-index and source-order changes; primed hit indexes; accessibility order; pointer capture across reordering; cancellation on removal; and release of removed nodes.

The final release suite passes 343 functional tests with 34 optional measurements skipped, including all six new tests and the real icon-loader fixture. All six focused tests also pass Address Sanitizer with leak detection disabled. The changed production file passes Swift syntax parsing. No full-app build or scrolling FPS measurement is claimed.

A fresh generator invocation reproduced all 99 engine/harness source files, 73 host test files, 177 TGUIKit source files and 76 TGUIKit test files byte-for-byte. The final compiled source and production source match; compiler-input and production hashes are retained with the logs.

## Alternatives checked

An initial allSatisfy scan helped ordered siblings but regressed mixed lists. A local single-pass scan reduced that overhead but still regressed late-inversion lists by roughly 10–13%. Capturing sort keys improved larger mixed lists but allocating another sorted key array regressed small mixed lists by roughly 20%. Sorting that temporary key array in place removed the measured small-list regression. Raw experimental runs are retained. The first chained key expression exceeded Swift's type-checking limit; the final code uses an explicit tuple type and separate statements, and that compiler failure is retained for provenance.

Archived text logs normalize trailing whitespace; test output content and timing batches are otherwise preserved.
