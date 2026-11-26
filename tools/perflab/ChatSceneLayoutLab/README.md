# Reusing chat scene hit geometry across unchanged layouts

ChatLayerSceneView previously cleared its hit index and advanced its geometry version on every layout. The next hit query rebuilt the index by walking the node tree and converting every interactive node's bounds into scene coordinates. Link tooltip synchronization also repeated coordinate conversion after every version change.

The candidate retains the existing index when the scene root frame is unchanged. Frame, transform, sublayer-transform, child-order, hierarchy, pointer-eligibility and custom-region changes continue to invalidate through the node APIs. Live visibility, enabled state, clipping and custom hit predicates remain checked during each hit. Layout still synchronizes tooltips, recalculates hover, and refreshes link hover; callbacks are not suppressed. Scene resize and bounds-origin changes still invalidate.

Sender and forwarded names can temporarily leave the scene's layer hierarchy during the bubble shake animation. ChatLayerRowView detects this native hosting and preserves layout-time invalidation while either name is outside the root layer. The existing invalidation method becomes module-visible for that adapter. No new fields, persistent collections or public package APIs are added.

The engine's existing geometry contract still applies: normal clients use node frame/transform/sublayerTransform/zIndex/setChildren APIs. Direct backing-layer geometry mutations bypass those APIs; an adapter doing such work must invalidate the scene. Native name hosting is handled by the row adapter. Hit testing still follows model-layer geometry, not animated presentation-layer positions.

## Reproduce

```sh
python3 tools/perflab/ChatSceneLayoutLab/prepare-isolated.py /tmp/ChatSceneLayoutValidation
CHAT_COPY_ICON_BUNDLE=/tmp/PrecomposedTintFinalAssets/Probe.app swift test --package-path /tmp/ChatSceneLayoutValidation --scratch-path /tmp/ChatSceneLayoutValidation-build -c release
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/ChatSceneLayoutValidation --scratch-path /tmp/ChatSceneLayoutValidation-asan --sanitize address --filter SceneLayoutTests.SceneLayoutTests
SCENE_LAYOUT_BENCHMARK=1 swift test --package-path /tmp/ChatSceneLayoutValidation --scratch-path /tmp/ChatSceneLayoutValidation-build -c release --skip-build --filter SceneLayoutBenchmarkTests
cp /tmp/chat-scene-layout-benchmark.json /tmp/scene-forward.json
SCENE_LAYOUT_BENCHMARK=1 SCENE_LAYOUT_REVERSE=1 swift test --package-path /tmp/ChatSceneLayoutValidation --scratch-path /tmp/ChatSceneLayoutValidation-build -c release --skip-build --filter SceneLayoutBenchmarkTests
cp /tmp/chat-scene-layout-benchmark.json /tmp/scene-reverse.json
```

Use a fresh output directory. Build, test and benchmark sequentially, with no competing compiler work during timing. The icon environment variable points at the local asset-only app fixture used by ChatLayerEngineLab; supply an equivalent bundle when reproducing the real copy-icon test elsewhere. Omitting it skips that test.

The baseline is commit ac8b2d907. The generator uses ChatLayerEngineLab's standalone host and freezes two complete engine modules, differing only in ChatLayerScene.swift and ChatLayerRowView.swift. It freezes current TGUIKit sources and tests, records root dependency hashes, and appends the same test-only index/state-allocation inspector to both scene files. Production sources do not contain that inspector. Source guards require the recorded original or candidate revision; use the recorded checkout if subsequent changes have modified these files.

The fixture uses real AppKit views/windows, Core Animation layers and production engine methods. Account models and some assets come from the existing standalone host. It does not build Telegram or simulate the full message/media pipeline.

## Coverage

Eight focused tests cover:

- 1,000 unchanged layouts with eight interactive nodes, with and without a recorded pointer. The baseline makes 8,000 index coordinate conversions per mode; the candidate makes zero, with identical targets. Counters override the real layer rectangle-conversion method and are not present in timing fixtures.
- 54,600 target comparisons and 54,600 conservative may-hit comparisons while changing node frames, transforms, root sublayer transforms, z-order, pointer eligibility, custom regions, child order, scene size and scene bounds origin.
- 100 changing custom-region/visibility/opacity/enabled/clipping cases, comparing event traces, focus and custom-region call counts. Predicates still run on unchanged layouts.
- Reentrant hover callbacks moving their own parent, followed by repeated layout/hit checks.
- Tooltip rectangles through 40 parent/frame/transform/mutable-text transitions, plus 400 unchanged layouts.
- Both sender and forwarded names moved into native backgrounds, moving those backgrounds, then restoring the names. Hit targets follow the real hosted layers.
- 39,936 hit comparisons with transformed roots and repeated layouts.
- Deferred scenes that remain unallocated and indexed nodes that release after removal.

The scene State allocation size is also compared between baseline and candidate. This checks the fixture's state object, not process memory or total transient allocations.

## Measurement method

Release timings use nine alternating paired batches, then a separate process with reversed initial order. Transactions drain outside each timed batch. The environment is arm64 macOS 26.4 (25E246), Apple Swift 6.3.3. Results include unchanged layouts, layout plus hit queries, recorded-pointer hover, changed node geometry, changed scene size, representative row construction/rebinding, and normal/native-hosted sender-name layout.

Row fixtures use premeasured text. Construction and rebinding therefore exclude text measurement, media decoding and resource loading. The full-row fixture is representative of engine composition, not a full account-backed ChatRowItem. No whole-chat opening latency, scrolling FPS, GPU timing or process-memory reduction is claimed.

## Development findings

The initial tooltip test used the default disabled-tooltip setting and failed before providing meaningful tooltip coverage. The final fixture enables tooltips explicitly.

The first optimization passed ordinary geometry tests but failed a new native-hosted sender-name test. The preserved baseline passed: moving the native background after the index was built produced a stale candidate target. The row adapter now keeps invalidation active while names are hosted externally. The failing source change, tests and log are retained under Experiments/native-hosting-failure. Final coverage includes both sender and forwarded names.

The corrected exploratory benchmark is retained separately. Its final production code is unchanged, while final coverage and timing add forwarded-name, transformed-root and native-hosted-name cases. Exploration.md records the rounded-clip candidate rejected before benchmarking because current production callers rarely use that path.

## Final validation and timings

The final frozen suite passes 345 functional chat/folding-text tests, with 34 optional measurements skipped (379 total). The real copy-icon asset fixture passes. All eight focused tests pass under Address Sanitizer, with leak detection disabled. The full suite also includes the existing CPU bitmap, bounded Metal frame, selection, accessibility, lifecycle and animation checks; those retain their existing scope and tolerances. Production Swift files pass syntax parsing.

A fresh generator reproduces 432 Swift files and both manifests after normalizing the temporary path. All 584 recorded compiler/dependency inputs remain unchanged. The measured engine source matches production, and the frozen TGUIKit source/tests match the current worktree. Baseline and candidate modules differ only in the two intended production files. The complete Telegram app was not built.

No matching swift-frontend, xcodebuild or clang processes were present in either final run's pre/post checks. The full table and all nine batches per variant are retained in [results/medians.md](results/medians.md) and the timing JSON files.

| Workload | Less time across both measurement orders |
| --- | ---: |
| Representative row layout with recorded hover | 44.8–45.6% |
| Eight-node unchanged layout with recorded hover | 47.8–48.9% |
| Eight-node layout followed by hit lookup | 71.3–71.9% |
| One-node unchanged layout with recorded hover | 17.5–19.0% |
| 32-node unchanged layout with recorded hover | 73.1–73.4% |
| Normal sender-name layout with recorded hover | 7.9–9.0% |

The representative row layout decreases from 1.78–1.80 µs to 0.977–0.982 µs. The eight-node hover layout decreases from 1.20–1.21 µs to 0.620–0.626 µs. These results apply to repeated layout work with unchanged geometry, not whole-row rendering or scrolling FPS. Layout without a subsequent hit query saves only about 0.01–0.02 µs.

Changing node geometry remains approximately flat, from 0.6% slower to 1.6% faster across fixture sizes/orders. A real scene resize with one node is 1.2–3.7% slower, adding 0.014–0.042 µs. Changed row rebinding is 0.4–0.8% slower, adding 0.06–0.10 µs; unchanged row rebinding is 0.8–1.3% slower, adding 0.06–0.09 µs. The native-hosted sender fallback is 0.4–1.3% slower, adding 0.01–0.04 µs. Construction ranges from 0.9–4.4% less time and is not treated as a stable construction-performance claim. All controls and regressions remain in the results.

The change reuses the engine's existing index storage and avoids coordinate conversions and rebuild work. It does not establish a reduction in retained app memory. Archived text logs normalize trailing whitespace without changing test content or raw measurements.
