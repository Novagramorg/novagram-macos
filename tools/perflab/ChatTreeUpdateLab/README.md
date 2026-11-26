# Chat layer child-update validation

`ChatLayerNode.setChildren` now recognizes unique subsets and permutations of the node's existing children. These operations preserve the tree's validated identifier/cycle invariants and avoid revalidating every identifier in the root tree. The existing retained-object set proves membership and uniqueness; no persistent membership cache is added. Updates introducing new children, duplicate objects or invalid parent relationships retain the original complete validation and error behavior.

Pure permutations also reuse the scene's node lookup, while still invalidating hit geometry, validating input, and scheduling layout. Membership changes mark the lookup invalid before attachment/removal callbacks can run. A reentrant permutation rebuilds an invalid lookup, preserving publication inside callbacks. Initial root installation starts with an invalid lookup and retains the original forced rebuild. A boolean stored beside the existing validity flag tracks this state.

## Reproduce

```sh
python3 tools/perflab/ChatTreeUpdateLab/prepare-isolated.py /tmp/ChatTreeUpdateValidation
swift test --package-path /tmp/ChatTreeUpdateValidation --scratch-path /tmp/ChatTreeUpdateValidation-build -c release --filter TreeUpdateTests
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/ChatTreeUpdateValidation --scratch-path /tmp/ChatTreeUpdateValidation-asan --sanitize address --filter TreeUpdateTests
TREE_UPDATE_BENCHMARK=1 swift test --package-path /tmp/ChatTreeUpdateValidation --scratch-path /tmp/ChatTreeUpdateValidation-build -c release --skip-build --filter TreeUpdateBenchmarkTests
cp /tmp/chat-tree-update-benchmark.json /tmp/tree-forward.json
TREE_UPDATE_BENCHMARK=1 TREE_UPDATE_REVERSE=1 swift test --package-path /tmp/ChatTreeUpdateValidation --scratch-path /tmp/ChatTreeUpdateValidation-build -c release --skip-build --filter TreeUpdateBenchmarkTests
cp /tmp/chat-tree-update-benchmark.json /tmp/tree-reverse.json
```

Use a fresh output directory. Timing should run without competing compiler work. The generator uses the existing ChatLayerEngineLab host, freezes TGUIKit, and creates two complete engine modules differing only in ChatLayerScene.swift. The baseline restores the exact captured original file. Both modules receive the same test-only state-allocation inspector. No inspector is included in production.

Omit the filter to run the complete host regression suite. Its actual copy-icon asset test needs `CHAT_COPY_ICON_BUNDLE` pointing at the existing asset-only app bundle; final validation used `/tmp/PrecomposedTintFinalAssets/Probe.app`. Other theme images and account models are supplied by the existing standalone fixtures.

## Measurements

Release medians in microseconds per operation, nine alternating paired batches and a separate process with reversed initial order. Positive percentages mean less CPU time. Transactions drain between batches outside timing. Raw timings are retained in results.

| Workload | Forward order | Reversed order |
| --- | ---: | ---: |
| append_and_remove_one | 108.720 → 84.601 (+22.2%) | 106.241 → 78.332 (+26.3%) |
| append_and_remove_one_small_tree | 13.731 → 11.954 (+12.9%) | 12.909 → 11.751 (+9.0%) |
| attached_reorder_12_background64_hover_false | 59.865 → 9.675 (+83.8%) | 55.292 → 10.185 (+81.6%) |
| attached_reorder_12_background64_hover_true | 66.338 → 16.316 (+75.4%) | 59.017 → 15.975 (+72.9%) |
| attached_reorder_4_background0_hover_false | 8.197 → 3.254 (+60.3%) | 7.728 → 3.151 (+59.2%) |
| attached_reorder_4_background0_hover_true | 11.688 → 6.707 (+42.6%) | 11.175 → 6.512 (+41.7%) |
| attached_row_rebind | 12.160 → 12.211 (-0.4%) | 12.024 → 11.953 (+0.6%) |
| nested_shrink_and_restore_16 | 171.895 → 123.866 (+27.9%) | 159.700 → 125.816 (+21.2%) |
| premeasured_row_construction | 63.681 → 63.608 (+0.1%) | 61.755 → 61.379 (+0.6%) |
| replace_all_12 | 56.614 → 56.160 (+0.8%) | 49.104 → 47.064 (+4.2%) |
| unchanged_children_12 | 0.296 → 0.299 (-1.0%) | 0.291 → 0.296 (-1.8%) |

The compact reorder fixture has four interactive children, each with one leaf, and three grouping/root nodes: eleven nodes total. The larger fixture has twelve interactive children with leaves, three grouping/root nodes and sixty-four noninteractive background nodes: ninety-one nodes total. Reordering is measured in real views attached to a hidden NSWindow and includes layout. Hover-enabled cases send a pointer-move event first, recording the pointer position so subsequent tree changes recalculate hover. Both layer order and node membership are exercised.

Compact reordering uses 59–60% less time without hover and 42–43% less with hover. Compact append/remove cycles use 9–13% less. The larger reorder fixture uses 82–84% less without hover and 73–75% less with hover. Large append/remove and shrink/restore workloads use 21–28% less. These gains apply to structural tree updates; unchanged row rebinding is approximately flat (-0.4% to +0.6%), and premeasured row construction changes by only +0.1% to +0.6%. Replacing every child retains full validation and is approximately flat to 4% faster. The unchanged-children early return is 1.0–1.8% slower in the final runs, roughly 3–5 nanoseconds per call.

Shrink/restore includes both removing half of sixteen children and restoring them, alongside 128 background nodes. Append/remove includes both operations. Replacement swaps between twelve old nodes with leaves and twelve new nodes. The row construction/rebind fixture uses four premeasured PlainRowFixture variants and the actual LayerPlainRow implementation; it excludes text measurement, decoding, onscreen frame presentation and a complete Telegram account. No whole-app scrolling FPS improvement is claimed.

The scene State heap allocation measures 160 bytes in both modules on the tested arm64 machine; the new boolean fits existing allocation space. Pure reordering avoids the identifier/object validation sets and the replacement node dictionary. A counted-identifier test proves the original reordering hashes identifiers more than 128 times for 64 nodes, while the candidate performs zero identifier hash calls. These checks do not measure whole-process memory or total transient allocation bytes.

## Regression evidence

Nine focused tests cover all 65 unique subsets/permutations of four children, complete lookup and parent/scene membership, retained non-node sublayers, invalid updates and original error priority, replacing a node with the same identifier, detached reparenting, counted identifier hashing, hover/focus/capture/cancellation, reentrant hover mutation, attachment-time reordering, reentrant owned-root installation, and removed-subtree release.

All nine pass release and Address Sanitizer, with sanitizer leak detection disabled. The full chat/folding-text suite passes 346 functional tests with 34 optional measurements skipped, including the actual icon-loader fixture. The final benchmark snapshot differs from that full-suite snapshot only in additional small-tree benchmark cases; every production source and functional test is byte-identical. Both input manifests are retained and verified. The changed production file passes Swift syntax parsing.

A fresh generator reproduced all 99 engine/harness sources, 73 host test files, 177 TGUIKit sources and 76 TGUIKit test files exactly. All 578 recorded final compiler inputs remain unchanged, and the production file equals the measured source. A complete application build has not been performed by this lab.

## Issues caught during development

The initial hover-reentrancy fixture failed in both modules because calling updateHover directly did not record lastPointer. It now sends handlePointer(.moved), and the prior sibling-order benchmark report explicitly records that earlier fixture's narrower scope.

An additional attachment-reentrancy test then reproduced a real regression in the initial candidate: a callback that reordered children could observe stale node lookup results before the outer update finished. The baseline passed that assertion. The final validity flag fixes this case and initial owned-root installation. The failing prototype, regression test source, logs, and preliminary measurements are retained under results/experiments. Final performance claims use only the corrected implementation.

Archived text logs normalize trailing whitespace; their test content and timing batches are otherwise preserved.
