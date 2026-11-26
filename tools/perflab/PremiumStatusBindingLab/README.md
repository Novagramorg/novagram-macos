# Stable premium status binding

`PremiumStatusControl` previously compared the resolved media file to decide whether to reuse its emoji layer. Before resolution, every update replaced the layer and restarted its loading setup. Once resolved, the same check could incorrectly reuse a layer after changes to account, inline-sticker context, dimensions, playback policy, or tint. Rebinding a default status with a custom color also reset its intended 0.4 opacity to 1.0.

The control now compares the layer's stable requested file ID and a configuration created with the layer. The configuration checks source identity, size, playback policy, selection, tint, and custom-color presence where those affect rendering. Untinted resolved emoji still reuse their layer across selection and palette changes. A finished finite animation retains its stopped state when only tint changes; changes to source or loop policy reset that state. The configuration is released when the control becomes static.

`InlineStickerItemLayer.hasFileResolutionResult` distinguishes a pending lookup from a lookup that returned nil. Pending layers can be reused; an empty result allows the next binding to retry as before. The flag is visible before the file callback runs and is preserved in layer copies. The getter also recognizes immediately supplied files, whose initializer assignment does not invoke Swift property observers.

Tint comparison uses identity followed by `NSColor.isEqual`, avoiding the app's packed-RGB equality overload. Tests distinguish two colors that round to the same packed RGB value, while retaining reuse for equal colors.

## Harness and coverage

`prepare.py` extracts the complete old and candidate controls, changing only class names. The baseline is `a120843a3`. It also copies the production file property, resolution flag, and getter into the animation-layer fixture. The same resolution API is available to both controls; the old control does not use it.

The harness uses real AppKit windows, TGUIKit controls, SimpleLayer, notifications, and removal animations. Peer/account services, file resolution, media decoding, icons, and particle rendering are fixtures. The fixture can delay resolution, return nil, expose the configured colors, and count layer construction. It does not measure network requests, actual decoder startup, or complete app frame times. The whole production files are parsed separately; the full application and complete feature packages are not built.

Fifteen binding tests cover repeated pending updates, successful and empty resolution, immediate files, pending configuration changes, loaded source/size changes, palette/custom-color changes, precise color equality, untinted reuse, default-status opacity, loop-policy changes, completed-playback preservation, source changes, and configuration release. Fourteen lifecycle tests retain the previous pass's observer, visibility, callback, removal-frame, reparenting, and geometry checks.

The original binding behavior produced 26 failed assertions across the initial suite. An initial resolution-state implementation failed two immediate-file assertions; the final getter fixes that initializer case. A rejected fast path using overloaded color equality measured about 1.8 µs per update; those raw results are preserved separately. The final identity/precise-equality check removes that regression.

## Measurements

Nine alternating paired batches of 1,000 updates follow warmup; a second run reverses the initial order. Timing includes the batch autorelease-pool drain. Every batch checks the exact number of layer constructions. Both controls remain attached to native windows and run their complete extracted binding method.

| File state | Before µs/update, first / repeat | After µs/update, first / repeat | New layers per 1,000 repeated updates |
|---|---:|---:|---:|
| Pending | 1.518 / 1.467 | 0.336 / 0.332 | 1,000 → 0 |
| Resolved | 0.317 / 0.314 | 0.335 / 0.321 | 0 → 0 |

The pending case is about 4.4–4.5× faster in this fixture. Resolved binding is about 0.007–0.018 µs slower per update in these runs. Reuse avoids repeated initialization; it does not remove the first layer creation or the cost of rendering its media.

There is a memory tradeoff: an active emoji control retains an 80-byte configuration allocation according to `malloc_size`. Repeated updates reuse that allocation, and static controls do not create it. Both extracted control objects occupied the same 1,536-byte allocation bucket in this run. The added resolution-state field's effect on the complete production animation-layer allocation and total application memory was not measured. This change reduces transient layer churn, not proven steady-state process memory.

## Reproduce

```sh
python3 tools/perflab/PremiumStatusBindingLab/prepare.py
swift test --package-path tools/perflab/PremiumStatusBindingLab -c release
STATUS_BINDING_BENCHMARK=1 swift test --package-path tools/perflab/PremiumStatusBindingLab -c release
STATUS_BINDING_BENCHMARK=1 STATUS_BINDING_REVERSE=1 swift test --package-path tools/perflab/PremiumStatusBindingLab -c release
swift test --package-path tools/perflab/PremiumStatusBindingLab --sanitize address
swift test --package-path tools/perflab/PremiumStatusBindingLab --sanitize thread
```

Use separate scratch paths and sequential builds. Save `/tmp/premium-status-binding-benchmark.json` before the next run. Logs, generated sources, production changes, source hashes, raw benchmark batches, and validation summaries are preserved in `results/`.

Final validation passed: all 29 functional tests in release and under each of Address Sanitizer and Thread Sanitizer, both final benchmark orders with exact allocation counts, and parsing of both complete production source files. No sanitizer errors were reported.
