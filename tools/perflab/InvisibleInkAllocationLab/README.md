# Invisible ink view allocation lab

This isolates removal of five retained but unused mask/spot views from `InvisibleInkDustView`. The active emitter host, CAEmitterLayer, cell configuration, reveal transitions and window observation stay the same. The owned view count including the dust view falls from seven to two; the attached view tree remains two views. This is not a migration of chat spoilers to the layer engine.

The original class is captured in `Reference/InvisibleInkDustView.swift.txt`. Its compiled copy adds imports and renames the class; provenance records both hashes. Both variants use the same current TGUIKit dependencies. The separate `MediaDustView` class is unchanged and its original hash is recorded.

Four functional tests compare owned versus attached structures, emitter configuration and rectangle hit testing through geometry/color updates, window key changes/reveal/detach/reattach, and weak lifetime after pending reveal timers. A deterministic named speckle asset is installed so emitter contents are nonnil. Random emitter seeds and particle bitmap output are not compared; these tests validate configuration and lifecycle, not a GPU particle rendering benchmark.

Create a frozen fixture with `python3 prepare-isolated.py /tmp/InkDustFinal`. The script copies the lab and TGUIKit source/tests, rewrites local dependency paths and records source hashes. Run release tests with `swift test --package-path /tmp/InkDustFinal -c release`. Address and thread sanitizer runs should use separate scratch directories and run sequentially.

Optional timing: set `INK_DUST_BENCHMARK=1` and filter `InkDustBenchmarkTests/testConstructionAndUpdateCosts`. The test records nine alternating batches for construction, construction plus configuration, and repeated updates. Run a second fresh process with `INK_DUST_REVERSE=1`. `INK_DUST_OUTPUT` selects the JSON path; the default is `/tmp/ink-dust-benchmark.json`.

Optional retained footprint: set `INK_DUST_MEMORY=original` or `current` and filter `InkDustBenchmarkTests/testRetainedAllocationFootprint`. Run fresh processes in original/current/current/original order. Each retains 2,000 configured dust views after warming both implementations. Footprint includes allocator/framework storage; neither scenario attaches or rasterizes the views, and neither measures overall Telegram memory or scrolling.

No results are claimed until these tests and measurements are executed.

## Spoiler lifecycle regressions

The separate `results/spoiler-lifecycle` evidence covers two correctness fixes in TGUIKit, not an additional allocation or scrolling benchmark.

A spoiler reveal callback can synchronously replace or clear its TextView binding. The handler now stops if the binding changed, so the obsolete reveal cannot insert an old text overlay, remove the replacement ink, or overwrite caller-owned state. Three native-event tests cover replacement, clearing/reuse and ordinary reveal priority over multiple-click selection. They use a real TGUIKit.Window so the actual spoiler handler runs. The original handler fails three assertions; the corrected handler passes.

Both text and media dust now identify each reveal/hide transition. An old delayed reveal completion cannot freeze a newer reveal after a hide/reveal reversal. Five tests cover both types, ordinary and repeated reveals, hiding, detach/reattach, final model opacity and immediate release with pending timers. The race tests make old timers overdue and require a control emitter to finish before inspecting the new reveal. The original implementation fails four playback/reattachment assertions. The initial fixture additionally used two incorrect NSView.alphaValue expectations; these were corrected to layer.opacity, which is what the production transition changes. All negative and intermediate logs are retained.

Each dust instance gains one UInt64 generation field. The earlier allocation-removal fixture predates this generation field, so its results must not be presented as measurements of the final combined source.

The full frozen TGUIKit suite passes 428 functional tests in release, Address Sanitizer and Thread Sanitizer, with 18 optional measurements skipped (446 total). ASAN leak detection is disabled. All 416 compiler input hashes were checked after each completed run. A prior unchanged full run was interrupted by clamshell and maintenance sleep; its unrelated display-link and hover timeout failures and corresponding power events are retained. The unchanged full suite passed after waking, with idle sleep prevented for the command duration.

Reproduce against a fresh current-source snapshot with the existing `prepare-isolated.py`, then run `swift test --package-path <snapshot>/TGUIKit` using separate release, address-sanitizer and thread-sanitizer scratch paths. The archived fixture and compiler-input manifest preserve the exact validated source, including the small external local dependencies' hashes. These tests establish the covered TGUIKit lifecycle behavior; they do not establish a full Telegram build, real chat interaction coverage, GPU particle rendering parity, memory savings or scroll FPS.
