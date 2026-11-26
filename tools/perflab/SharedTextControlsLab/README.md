# Shared header and label text reuse

Navigation headers used by chat, profile and media screens previously created fresh TextNodes and measured both title and status on every layout or presentation-inset update. Changing only status also rebuilt the title. TextViewLabel allocated an eager spare node, then created separate nodes for ordinary attributed-string updates; autosizing repeatedly invalidated its drawing layer even when the measured text was unchanged.

The candidate reuses each control's existing node and measured layout. Labels retain no spare node, release their node when cleared, and invalidate text drawing only when text or geometry changes. Header title/status updates preserve the unchanged counterpart. Presentation assignments still refresh constraints, including dynamic space reserved by ChatTitleBarView's call/status controls. The drawing algorithms and interactions remain unchanged.

Two existing header bugs are corrected: assigning a title image now immediately updates available text width, and reassigning a mutated title/status attributed string updates its layout without waiting for another layout pass.

## Reproduce

From the repository root:

```sh
python3 tools/perflab/SharedTextControlsLab/prepare.py
SHARED_TEXT_BENCHMARK=1 swift test --package-path tools/perflab/SharedTextControlsLab --scratch-path /tmp/SharedTextControlsLab-release -c release
swift test --package-path tools/perflab/SharedTextControlsLab --scratch-path /tmp/SharedTextControlsLab-asan --sanitize address
swift test --package-path tools/perflab/SharedTextControlsLab --scratch-path /tmp/SharedTextControlsLab-tsan --sanitize thread
```

This mini-app test package uses actual TGUIKit controls. `prepare.py` obtains both original controls from `c2a11539d`, renames their types and adds a testable import. Both variants use the same actual TextNode implementation. Generation metadata records original, candidate and generated reference hashes.

## Regression evidence

The first seven tests produced 15 expected assertion failures against unchanged production sources. The expanded suite contains 14 functional tests and one opt-in benchmark. It covers node/layout identity, redraw requests, release on clearing, cleared pixels, mutable title/status reassignment, immediate image-width refresh, and dynamic header insets.

A regression in the first candidate was caught before committing: skipping constraint refresh for unchanged presentation properties missed changes in a subclass's dynamic inset. The final implementation always reevaluates constraints and avoids work through TextNode's reuse check. The regression test compares exact geometry with the original control; it also checks that the available text width shrinks. This preserves existing CoreText rounding, which can produce a 151-point measured width for a nominal 150-point constraint.

There are 448 exact nonblank bitmap comparisons: 256 label pairs and 192 header pairs. Label sequences cover Latin, RTL, emoji and multiline text, autosizing, alignment, insets, frame changes, fitting and text replacement. Header cases cover status visibility, title images on either side, offsets, truncation and title rectangles. Rendering contexts use 1x and 2x scales; label layers use the matching contentsScale. Detached header views retain the harness's 2x backing scale for text smoothing in both variants. These are native control drawings, not whole Telegram screenshots.

The full TGUIKit and chat-layer suites are run after the focused tests; results and exact input hashes are recorded in `provenance.json`. No full Telegram build was performed.

## Benchmark and memory scope

Nine paired release batches alternate original/candidate order, with 1,000 operations per batch. Views and attributed strings are prepared outside timing. Header status changes alternate two prebuilt strings. The conditional-display case calls `display()` only when the label layer requests it; it models work after layout and is not an FPS measurement. Bare autosizing layout is roughly unchanged across samples; the meaningful gain is avoiding redraws.

The label's runtime instance size changes from 1,024 to 1,016 bytes, but its direct allocation remains in the same 1,024-byte allocator bucket. Direct retained-object totals include that view object and unique TextNode/TextNodeLayout objects only:

| Label state | Nodes before/after | Direct bytes before/after |
| --- | --- | --- |
| Empty | 1 / 0 | 1,056 / 1,024 |
| Ordinary text | 2 / 1 | 1,216 / 1,184 |
| Autosizing text | 1 / 1 | 1,184 / 1,184 |
| Cleared after autosizing | 1 / 0 | 1,184 / 1,024 |

These totals exclude layers, AppKit internals, strings and CoreText storage. They are not whole-process memory measurements. There is no global cache or added per-control cache field.

## Recorded release medians

Microseconds per operation, limited to these control operations:

| Operation | Original | Candidate |
| --- | ---: | ---: |
| Assign unchanged label text | 4.4474 | 0.0964 |
| Autosizing label layout | 0.1335 | 0.1293 |
| Label layout plus display if requested | 3.7804 | 0.1234 |
| Header layout | 6.4842 | 0.1551 |
| Update header status | 6.7664 | 2.8427 |
| Repeat header inset assignment | 6.9997 | 0.1275 |

Raw batches and object measurements are in `results/benchmark.json`. No timing threshold is used as a correctness assertion, and no end-to-end chat-opening or scrolling gain is claimed.
