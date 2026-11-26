# Passive reaction layers

This isolated AppKit fixture compares the previous reaction count `TextView`, selected-background `View` and selected tag `NinePathImage` with the new `ChatReactionTextLayer`, `SimpleLayer` and `ChatReactionTagBackgroundLayer`. It also checks deferred creation of the ordinary reaction's avatar container. The interactive outer `Control` remains native.

`Reference/ChatReactionsView.swift.txt` is the complete source captured immediately before this change; `Reference/provenance.json` records its SHA-256. `generate.py` extracts the count binding, selected-background binding, layout, and candidate accessibility methods into four fixture classes. It copies the production text helper verbatim. Generated manifests record the extracted methods and source hashes. `prepare.py` freezes the lab, real TGUIKit, and local package dependencies into a new directory and verifies that the inputs did not change during capture.

The media icon is a plain eventless `View`. Avatar insertion, media retrieval/playback, stars effect players, real reaction actions, account data, and full chat scrolling are outside this fixture. The tag background image is bitmap-backed (`NSImage(cgImage:size:)`), like production `tagImage`. These tests do not replace an app build or live media/interaction smoke test.

## Layer parity findings (2026-10-18)

- AppKit backing layers have `edgeAntialiasingMask = 0`. A plain `CALayer` antialiases rounded corners, so the selected fill differed on every corner pixel (155 failures). Both selected backgrounds copy the native mask; the ordinary fill also keeps `View`'s `isOpaque = true`.
- A text sublayer added before AppKit attached the lazily inserted tag `NinePathImage` ended up below it, so the translucent tag tinted the glyphs. This is a production ordering bug, not a fixture artifact. The tag background is now a layer inserted at index 0, which makes the order deterministic and removes one drawn NSView per selected tag.
- The native `NinePathImage` backing layer is geometry-flipped relative to its flipped parent; the tag layer sets `isGeometryFlipped = isFlipped` (an asymmetric marker in the fixture image catches a wrong flip).
- AppKit's private content-layer rasterization of the nine-part image cannot be reproduced bit for bit from `CALayer.draw(in:)`: stretched regions differ by at most 12/255 in about 20 pixels at 1x. Only the selected tag background uses a bounded oracle (max channel delta 32, at most max(32 px, 0.5 %) pixels above 3/255). `testResampledTagOracleRejectsFlippedMissingAndRecoloredBackgrounds` proves that oracle rejects a flipped, hidden or faded background at all scales. Every other comparison stays exact.

## Correctness

Prepare a new fixture and run it serially on macOS:

```sh
python3 tools/perflab/ReactionPassiveLayerLab/prepare.py /tmp/ReactionPassiveCheck
swift test --package-path /tmp/ReactionPassiveCheck -c release --filter PassiveReactionTests
```

The nine tests cover 288 text-bearing and 12 text-free native-versus-layer pixel pairs, explicit missing-text/wrong-tint negative controls, count reuse and replacement during removal, selected-fill geometry/animation keys, paused interrupted-opacity removal, native overlay ordering, lazy avatar host retention, static-text accessibility value/frame/hit/identity changes, outer control accessibility activation, and weak ownership after removal. The interrupted animation test presents a small borderless window and pauses the animation clock; it checks measured presentation opacity rather than assuming an elapsed animation fraction. Set `REACTION_PASSIVE_DIAGNOSTICS` to an output directory to save up to 12 failing image pairs and layer-tree metadata per test. The fixture window's backing scale tracks each rendering scale so native and layer text use the same font-smoothing policy.

For a failing-before animation check, change only the generated `CurrentFull` deselection block in a separate frozen fixture back to `performSublayerRemoval(layer, animated: animated, scale: true)`, preserving all other fixture files. The interrupted deselection test should detect its extra `transform.scale` key, retained entrance transform, different outgoing transform, and model-opacity restart. Keep the original fixture and mutation output separate.

## Timing and allocation

Run timing only after correctness passes. Use both process orders and separate output files:

```sh
REACTION_PASSIVE_BENCHMARK=1 REACTION_PASSIVE_OUTPUT=/tmp/reaction-passive-forward.json swift test --package-path /tmp/ReactionPassiveCheck -c release --skip-build --filter PassiveReactionBenchmarkTests.testConstructionAndBindingCosts
REACTION_PASSIVE_BENCHMARK=1 REACTION_PASSIVE_REVERSE=1 REACTION_PASSIVE_OUTPUT=/tmp/reaction-passive-reverse.json swift test --package-path /tmp/ReactionPassiveCheck -c release --skip-build --filter PassiveReactionBenchmarkTests.testConstructionAndBindingCosts
REACTION_PASSIVE_MEMORY=native REACTION_PASSIVE_OUTPUT=/tmp/reaction-passive-native-memory.json swift test --package-path /tmp/ReactionPassiveCheck -c release --skip-build --filter PassiveReactionBenchmarkTests.testRetainedAllocationFootprint
REACTION_PASSIVE_MEMORY=layers REACTION_PASSIVE_OUTPUT=/tmp/reaction-passive-layers-memory.json swift test --package-path /tmp/ReactionPassiveCheck -c release --skip-build --filter PassiveReactionBenchmarkTests.testRetainedAllocationFootprint
```

Timing uses independent premeasured text per variant, 20 warmups, nine alternating batches, and reports microseconds per operation for construction, repeated/changed binding, text removal/restoration, and attached resizing. Memory uses a fresh process per variant, warms both variants, and retains 2,000 ordinary selected count chips with shared premeasured text. It records recursive NSView counts, physical footprint, and resident memory. Memory samples are unattached and unrasterized and include allocator/framework storage; repeat them before drawing conclusions. Neither result measures end-to-end chat speed.

Validation and benchmark results are pending; no performance claim is established by this fixture's source alone.
