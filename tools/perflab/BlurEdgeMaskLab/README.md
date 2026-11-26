# Weak sharing of modal blur masks

ModalHeaderView uses BlurEdgeView for the header edge. Its layout, update and window-attachment paths previously rasterized the same full-width grayscale gradient repeatedly. The final change preserves the original gradient calculation and shares immutable CIImage masks while an existing owner still retains them.

The private cache contains at most sixteen weak entries keyed by exact size, padding and direction. It does not retain image pixels or add fields to each view. Expired entries are reused before replacing a live entry. A lock protects lookup and replacement; generation occurs outside the lock, followed by a second lookup so concurrent generators can reuse an existing live result. Padding and direction are captured together before generation so the cached key matches the generated mask.

Every update still creates and resets its CIFilter. Radius changes, foreign filter mutations, layer-filter replacement, tint updates and zero-size behavior retain their original behavior. A cached image never captures its view, filter or mutable theme color.

## Reproduce

```sh
python3 tools/perflab/BlurEdgeMaskLab/prepare-isolated.py /tmp/BlurEdgeMaskValidation
swift test --package-path /tmp/BlurEdgeMaskValidation --scratch-path /tmp/BlurEdgeMaskValidation-build -c release
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/BlurEdgeMaskValidation --scratch-path /tmp/BlurEdgeMaskValidation-asan --sanitize address
swift test --package-path /tmp/BlurEdgeMaskValidation --scratch-path /tmp/BlurEdgeMaskValidation-tsan --sanitize thread
BLUR_EDGE_BENCHMARK=1 swift test --package-path /tmp/BlurEdgeMaskValidation --scratch-path /tmp/BlurEdgeMaskValidation-build -c release --skip-build --filter BlurEdgeBenchmarkTests
cp /tmp/blur-edge-mask-benchmark.json /tmp/blur-forward.json
BLUR_EDGE_BENCHMARK=1 BLUR_EDGE_REVERSE=1 swift test --package-path /tmp/BlurEdgeMaskValidation --scratch-path /tmp/BlurEdgeMaskValidation-build -c release --skip-build --filter BlurEdgeBenchmarkTests
cp /tmp/blur-edge-mask-benchmark.json /tmp/blur-reverse.json
swift test --package-path /tmp/BlurEdgeMaskValidation/TGUIKit --scratch-path /tmp/BlurEdgeMaskValidation-kit -c release
```

Use a fresh output directory and run builds sequentially. Measure without competing compilers. The generator creates two complete TGUIKit libraries that differ only in BlurEdgeView.swift, restoring the captured original implementation in the baseline. Test-only extensions expose the actual private mask method in both modules and the candidate's bounded-cache operations. They add no instance fields; production contains no inspection API. Selective imports avoid the existing TGUIKit class/module name collision; the initial test-import compilation failure is retained.

## Measurements

Release medians in microseconds per operation, nine alternating paired batches plus a second process reversing initial order. Positive percentages mean less CPU time. Real views are attached to a hidden NSWindow. Core Animation transactions drain between batches, outside timing.

| Workload | Forward order | Reversed order |
| --- | ---: | ---: |
| attached_radius_changes | 54.796 → 1.982 (+96.4%) | 54.864 → 1.954 (+96.4%) |
| attached_repeated_layout | 54.855 → 1.935 (+96.5%) | 55.507 → 1.934 (+96.5%) |
| attached_repeated_update | 56.050 → 2.856 (+94.9%) | 56.241 → 2.798 (+95.0%) |
| changing_size_17_values | 60.912 → 44.794 (+26.5%) | 60.834 → 44.571 (+26.7%) |
| create_destroy_17_sizes | 65.232 → 37.884 (+41.9%) | 64.219 → 37.707 (+41.3%) |
| unique_padding_cache_misses | 55.120 → 55.576 (-0.8%) | 54.642 → 55.271 (-1.2%) |

Repeated 420×48-point layouts use about 96.5% less CPU time; repeated updates use about 95% less. Changing radius still reuses the mask, saving about 96.4%. These are component-update measurements, not whole-app FPS or onscreen blur-rendering measurements. Filters are installed but backdrop composition is outside timing.

The resize and construction cases cycle through seventeen sizes and include all internal view work; they are not claimed to be pure cache misses. The explicit miss case uses a new padding value on every layout while keeping size fixed. It costs about 0.46–0.63 microseconds more, or 0.8–1.2%, because it pays cache lookup/maintenance as well as the original rasterization.

Sixteen simultaneously retained, identical 420×48 views have sixteen unique masks/CGImages before and one after. Unique source-bitmap storage is 344,064 versus 21,504 bytes. Each view allocation is 640 bytes in both modules. The cache adds bounded global metadata and weak-reference bookkeeping; these figures do not count that metadata, filter wrappers, GPU surfaces or total process memory. With only one matching live view, bitmap sharing does not reduce its source storage. Weak-lifetime tests verify that unused masks are released rather than retained by the cache.

## Correctness and validation

Eight focused tests cover 120 exact mask-pixel comparisons across widths, fractional heights, negative/positive padding and both directions; 36 exact complete CIMaskedVariableBlur output comparisons at three radii; non-vacuous checks that positive radii actually change the input; parameter changes and foreign filter reset; tint/frame equivalence; zero-size behavior; shared source identity; the sixteen-entry bound; eviction; weak release; concurrent same-key misses; and concurrent eviction across different keys.

All eight pass release, Address Sanitizer and Thread Sanitizer. Address Sanitizer disables leak detection. The complete frozen TGUIKit suite passes 397 functional tests with 18 optional measurements skipped. The production file passes Swift syntax parsing. No complete Telegram build or whole-app scrolling measurement was performed.

A fresh generator reproduces both libraries' 177 source files and 76 test files each, plus all three lab test files. The final Thread Sanitizer and complete-suite snapshot matches production exactly, with the recorded test-only extension appended. Four whitespace-only blank lines were cleaned after the timing/Address Sanitizer snapshot; all nonblank lines and all tests are unchanged. Both sets of 662 input hashes are retained and verified.

## Rejected rendering alternative

An initial experiment rendered a one-pixel-wide gradient and stretched/clamped it to the original extent. The original raster has small horizontal channel variations; the one-column version changes pixels. Among 120 mask comparisons, 89 differed by one channel value, and 12 of 18 filtered-output cases also differed. The proposal was rejected. Its source, measurements and detailed diagnostics are retained under results/experiments. The final cache reuses the original full-width raster and passes exact pixel comparisons.

Archived text logs normalize trailing whitespace; their test content and timing batches are otherwise preserved.
