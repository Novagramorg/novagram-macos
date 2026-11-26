# Native image assignment cost

`ImageView.image` previously read its layer's current contents on every assignment, although only animated updates needed that value. The final change reads previous contents inside the animated path. Nonanimated, nonempty assignments continue writing every image but avoid the contents read. Clearing an already-empty layer skips the write; clearing a layer containing an image still works even if the stored `image` property was already nil.

Only `packages/TGUIKit/Sources/ImageView.swift` changes. No cache, retained state, or extra allocation is introduced. `nsImage` assignments remain unchanged because NSImage is mutable. `TransformImageView` and `ChatRightIconLayer` are unchanged controls in the final benchmark.

## Native regression tests

The candidate uses the actual TGUIKit ImageView and TransformImageView. `prepare.py` copies their complete reference implementations from `89e1ce0ee`, with class renaming and a test import. The private ChatRightIconLayer is extracted verbatim from both versions of ChatRightView, with class renaming only. `generation.json` records source and generated-reference hashes. The standard test bootstrap supplies named presentation icons and screen scale.

Thirteen functional tests cover:

- Zero contents reads for 100 nonanimated nonempty assignments, versus 100 before; all 100 writes remain.
- Repeated images, distinct images, repeated empty values, and clearing foreign contents.
- Restoring content after external layer changes, including mixed image/nsImage assignments.
- Repeated assignment of a mutable NSImage after changing its size.
- Identical explicit animations for repeated images and nil values, including switching animation policy.
- Reentrant TransformImageView callbacks, capture protection, repeated signal animations, and fully-loaded state.
- Thirty-six nonblank byte-for-byte raster comparisons across three backing scales, including matching frames, bounds, and sizeToFit results.

Setter/getter instrumentation is used only in functional tests. Benchmarks use native, uninstrumented layers attached to AppKit windows. These tests do not build or exercise the complete Telegram app; they cannot establish whole-app scrolling, memory, GPU, or frame-time gains.

## Measurements

Forty attached objects receive 500 assignments each per batch. Nine paired batches alternate baseline/candidate order after warmup. A second run reverses the initial ordering. Timings include a final Core Animation transaction flush; final contents are verified outside the timed region. Table values are median microseconds per assignment.

| ImageView workload | Before, first / repeat | After, first / repeat |
|---|---:|---:|
| Repeated nonempty image | 0.09695 / 0.09875 | 0.06435 / 0.06810 |
| Alternating images | 0.19705 / 0.19720 | 0.16655 / 0.16260 |
| Repeated empty image | 0.06085 / 0.06175 | 0.03805 / 0.03960 |

This is roughly 31–34% less time for repeated images, 15–18% for changing images, and 36–37% for repeated empty assignments. The absolute savings are only about 22–35 nanoseconds per call. This is a small shared-control improvement, not evidence of visibly faster chat scrolling.

## Rejected proposal

The first proposal checked CGImage identity before assigning contents in ImageView, TransformImageView, and ChatRightIconLayer. It passed functional and raster tests and reduced setter calls, but native timings rejected it: changing ImageView images became roughly 18–23% slower, repeated TransformImageView images about 32% slower, and repeated ChatRightIconLayer images also slowed down. Checking/bridging existing contents cost more than the redundant native write. `results/rejected-broad-*` preserves those samples, logs, and the rejected production diff.

An intermediate ImageView-only empty-assignment guard improved empty updates but retained the unnecessary read for nonempty updates. `results/empty-only-*` preserves that experiment. The final implementation removes that read without adding an identity comparison. Unchanged TransformImageView and ChatRightIconLayer measurements are retained as controls; small timing differences between their identical implementations are not claimed as gains.

The initial baseline log contains three expected assertion failures from the original broad experiment. Those assertions were revised when that proposal was rejected. The final read-count test directly compares baseline and candidate behavior in the same process.

## Reproduce

```sh
python3 tools/perflab/ImageContentsLab/prepare.py
swift test --package-path tools/perflab/ImageContentsLab -c release
IMAGE_CONTENTS_BENCHMARK=1 swift test --package-path tools/perflab/ImageContentsLab -c release
IMAGE_CONTENTS_BENCHMARK=1 IMAGE_CONTENTS_REVERSE=1 swift test --package-path tools/perflab/ImageContentsLab -c release
swift test --package-path tools/perflab/ImageContentsLab --sanitize address
swift test --package-path tools/perflab/ImageContentsLab --sanitize thread
swift test --package-path packages/TGUIKit -c release
```

Run builds sequentially with separate scratch paths. Save `/tmp/image-contents-benchmark.json` before repeating a benchmark. Raw results, generated references, source hashes, and validation logs are retained under `results/`.

Final validation passed on arm64 macOS 26.4: 13 new functional tests plus 371 existing TGUIKit functional tests (389 total, 18 opt-in tests skipped), both benchmark orders, and all 13 new tests under each of Address Sanitizer and Thread Sanitizer. No sanitizer errors were reported. The modified production file also parsed successfully. All 259 recorded source/test inputs remained unchanged through final verification.
