# Merge retile lab

Why a chat history merge cost 7–10 ms during a fast scroll, and the fix. Standalone package on the real TGUIKit; a chat-style table (`TableView(isFlipped: false)`, also flipped and with sticky headers) of 200 variable-height rows in a real window, history-window shifts applied with `TableView.merge` and `.saveVisible(.upper/.lower, false)` exactly like `ChatController`.

```sh
cd tools/perflab/MergeRetileLab
swift test
```

## What happened

`merge` ran deletions and insertions as two separate NSTableView update batches and restored the scroll position (`saveVisible`) only after both. When the history window drops ~80 rows before the visible range, NSTableView re-tiles the old clip rect over shifted content at the first `endUpdates`, binds views for rows that are never shown, recycles the views of the rows that were on screen, and `saveVisible` then binds those again. In the app (16,000 pt/s fling, "Telegram macOS Talk") every visible row was re-bound on each `.upper` merge.

## Fix

`TableView.mergesSaveVisibleInOneGroup` (opt-in, set for the chat table): a non-animated `.saveVisible(.upper/.lower)` merge whose table is taller than the clip and whose frame equals `listHeight` runs as one NSTableView update — deletions, insertions, `saveVisible`, replacements — so NSTableView tiles once, in the final state. Inside the group two things NSTableView would only do at `endUpdates` are done first, because `saveVisible` reads them:

- `noteHeightOfRows(withIndexesChanged:)` for inserted rows — otherwise `rect(ofRow:)` ignores rows inserted in front (`testRowGeometryInsideUpdateGroup`: 8110 instead of 11340).
- the table frame is set to the final list height — otherwise the clip clamps to the old document and unflipped row origins use the old height.

Anything else (animated, `aroundIndex`, short tables, frames with extra height) keeps the previous path.

## Results

`testGroupInOneKeepsPlacementAndBindsLess`: 42 cases (two orientations plus sticky headers, both shift directions, deletions of visible rows, inserts at the document ends, a replaced visible row) — final visible rows, their window positions and the window pixels (scroller hidden: the overlay knob's flash timing differs) are identical to the previous path; binds drop from 6–8 to 0 for typical shifts. `testOracleCatchesOnePointShift` proves both oracles see a 1 pt difference.

In the app (Debug, `-PerfLabScrollSpeed 16000`, interleaved, `-PerfLabMergeGrouped 0` = old path): hitches 0 / 0 vs 5 / 2 per pass, merge time 30 / 22 ms vs 77 / 45 ms per pass, worst merge 4.9–6.0 ms vs 9.7–10.3 ms, visible rows' maximum on-screen shift across merges 0 in both. At the default 2400 pt/s both paths are identical (no hitches, same merge cost).
