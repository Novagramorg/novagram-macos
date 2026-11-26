# Inline emoji binding comparison

## Final result (2026-10-18)

Fair four-process run (native/layer/layer/native, nine samples, 120 iterations, compiler-free boundaries), `results/2026-10-18-final`. The handoff column is the initial implementation (`results/initial-regression`).

| Phase | Blocks | Caption | Native µs | Layers µs | Ratio now | Ratio at handoff |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| caption_reorder | 1 | yes | 3.32 | 4.05 | 1.22 | 2.47 |
| caption_reorder | 4 | yes | 15.41 | 17.91 | 1.16 | 2.21 |
| caption_reorder | 12 | yes | 46.17 | 54.60 | 1.18 | 2.19 |
| changed_source | 1 | no | 21.04 | 21.43 | 1.02 | 1.20 |
| changed_source | 1 | yes | 20.57 | 23.39 | 1.14 | 1.20 |
| changed_source | 4 | no | 83.90 | 80.39 | 0.96 | 1.16 |
| changed_source | 4 | yes | 81.23 | 82.67 | 1.02 | 1.18 |
| changed_source | 12 | no | 247.00 | 234.99 | 0.95 | 1.17 |
| changed_source | 12 | yes | 250.74 | 254.59 | 1.02 | 1.20 |
| construction | 1 | no | 55.52 | 45.61 | 0.82 | 0.94 |
| construction | 1 | yes | 72.75 | 68.07 | 0.94 | 0.98 |
| construction | 4 | no | 157.41 | 116.57 | 0.74 | 0.85 |
| construction | 4 | yes | 209.83 | 185.70 | 0.88 | 0.94 |
| construction | 12 | no | 419.81 | 306.71 | 0.73 | 0.83 |
| construction | 12 | yes | 573.03 | 481.56 | 0.84 | 0.94 |
| edited | 1 | no | 7.40 | 5.68 | 0.77 | 1.39 |
| edited | 1 | yes | 5.47 | 6.43 | 1.18 | 1.89 |
| edited | 4 | no | 21.30 | 15.58 | 0.73 | 1.55 |
| edited | 4 | yes | 22.38 | 25.06 | 1.12 | 1.86 |
| edited | 12 | no | 56.24 | 41.94 | 0.75 | 1.61 |
| edited | 12 | yes | 68.82 | 74.79 | 1.09 | 1.80 |
| same | 1 | no | 3.28 | 3.65 | 1.11 | 2.43 |
| same | 1 | yes | 3.33 | 4.24 | 1.27 | 2.52 |
| same | 4 | no | 10.80 | 12.01 | 1.11 | 2.64 |
| same | 4 | yes | 12.84 | 16.22 | 1.26 | 2.48 |
| same | 12 | no | 30.39 | 34.63 | 1.14 | 2.69 |
| same | 12 | yes | 38.73 | 45.86 | 1.18 | 2.44 |
| visibility | 1 | no | 3.84 | 4.43 | 1.15 | 1.23 |
| visibility | 1 | yes | 3.00 | 3.60 | 1.20 | 1.30 |
| visibility | 4 | no | 3.42 | 4.41 | 1.29 | 1.77 |
| visibility | 4 | yes | 3.72 | 5.54 | 1.49 | 1.97 |
| visibility | 12 | no | 5.02 | 6.87 | 1.37 | 2.46 |
| visibility | 12 | yes | 5.61 | 11.15 | 1.99 | 2.80 |

Changes since the handoff: the custom-emoji check is folded into the existing Core Foundation attribute scan; visibility follows the native `updateInlineStickerPlayback` contract (no geometry work when the window is not key or emoji are lite, no `isVisibleForFetching` writes, which are a no-op for `.always` layers); the host computes its visible region and the body root's region once per refresh and each block walks only to the root; the scroll selector takes no `Notification` argument (bridging was about 25 % of the callback). Remaining costs: unchanged rebinding 1.1–1.27× native (+0.4–8 µs) and scroll visibility 1.15–2× native (+0.6–5.5 µs per row and scroll event, the worst case being a 12-caption album); construction is 6–27 % faster and edited bodies 23–27 % faster. One NSView per body/caption instead of 1 + one per block.


This compares the actual immediate-pre-inline body/caption binding and eligibility methods captured from commit `41a9837eef539288e1319ca480012623d75b408c` against current production methods. Both variants compile the same current full `FoldingTextView` implementation and TGUIKit. The captured files and their hashes are under `Reference/`; the original host source is retained as provenance. The baseline signatures share the current engine module, but its eligible benchmark inputs must instantiate native `FoldingTextView`, never an engine host. The candidate must instantiate the layer host. Failing either condition aborts preflight.

Both variants consume the exact same account and sticker module types and the same deterministic media-layer implementation. The native harness's older local media types are replaced by aliases to those shared modules, so native code actually constructs and renders every emoji. Native playback-counter instrumentation is removed. Media-layer counters and constructor callbacks are absent from the timed stand-in. The remaining avatar/key/policy compatibility surface only lets the unmodified native source compile; avatars and one-shot policies are not timed.

The tests first require exact source IDs, account identity, base/explicit tint, measured sizes, row-relative frames, bitmap contents, copied custom-emoji metadata, selection ranges and exact pixels. Native and candidate must agree at 1×/2×/3× with 1, 4 and 12 blocks in body and caption hierarchies. Five binding variants plus selected text produce 108 bitmap comparisons. Visibility checks compare native and candidate playback flags before/after scrolling. Every timed process repeats the complete preflight. Any mismatch throws before timing starts; a missing/unrendered native baseline cannot produce benchmark results.

Timing phases separate unattached row construction/binding/teardown, identical-text reuse with freshly prepared models, edited text, changed emoji sources, caption reordering and attached scroll-notification handling. Text layouts and account/source fixtures are prepared outside timing. Both renderers use the same static bitmap producer. The time interval measures synchronous binding and AppKit mutation; Core Animation commit/flush occurs after the interval. It does not measure display latency or GPU work. Construction includes inner autorelease-pool cleanup, while transaction-retained objects may release at commit. Results include per-sample values, view counts and rendered-media counts. Static bitmap creation can dominate source-change timing; interpret that phase separately.

This is not a real Lottie/decode/network/player benchmark, an RSS measurement, an end-to-end chat-open measurement, or a scrolling FPS claim. The production `.always` fetch constructor can initialize resources synchronously and cancels subscriptions only on deinitialization; this lab cannot prove reduced media work. Use live playback validation and profiling before generalizing results.

Prepare only into a fresh `/tmp` directory:

```sh
python3 tools/perflab/InlineEmojiBindingLab/prepare.py /tmp/InlineEmojiBindingCheck
```

Preparation reuses the existing isolated engine generator, then creates separate candidate/native binding harness modules and records production, captured-reference, template, and recursive compiler/dependency hashes in `binding-provenance.json`. TGUIKit is copied; some other local package dependencies retain absolute paths. The runner verifies every recorded compiler input before and after each process and aborts if any dependency changed. It does not silently regenerate a snapshot.

After all other builds and benchmarks finish, run serially:

```sh
python3 tools/perflab/InlineEmojiBindingLab/run.py /tmp/InlineEmojiBindingCheck /tmp/InlineEmojiBindingBuild /tmp/InlineEmojiBindingResults
```

The runner builds and executes preflight, then launches separate native/layer/layer/native processes to expose order and warming effects. It records its executing source and hash, and checks for competing compiler processes before and after each timed process; these are boundary checks, not continuous monitoring. It stops at the first build, preflight, timing, or hash failure. Raw process logs and unaggregated measurements remain available; do not report speedups until the full reversed-order sequence passes and run-to-run variability is assessed.
