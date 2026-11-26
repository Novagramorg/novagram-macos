# Shared icon tint reuse

TGUIKit's `NSImage.precomposed` previously rendered a new bitmap on every call, even for the same icon, color and scale. This lab compares that original method with the public production API and an extracted copy of its private cache for inspecting retention invariants. `prepare.py` checks that the original fallback body is unchanged and copies the cache implementation without changing its logic. Only names and access control differ in the inspection fixture. `prepare-isolated.py` snapshots real TGUIKit sources and tests before building.

The production cache covers component-color tints of images no larger than 64×64 logical points, with no gradient or zoom. Untinted images, gradients, dynamic/pattern colors, zoomed images and larger images use the captured original renderer. Every eligible call still resolves the source bitmap, so replacing representations or modifying bitmap pixels can select new content. Logical size, scale, flips, source identity and immutable color distinguish entries; drawing-format changes invalidate them.

Sources are weakly referenced and checked on lookup. This prevents stale address reuse and avoids retaining large image data behind a small crop. Only rendered outputs are retained, limited to 64 entries, 64 KiB per output and 1 MiB of bitmap data in total, plus keys and bookkeeping. Rendering happens outside the lock. FIFO eviction uses a fixed-size ring. Rendering no longer clears a second time after `DrawingContext(clear: true)` has zeroed its buffer.

## Reproduce

```sh
python3 tools/perflab/ImageTintLab/prepare-assets.py /tmp/ImageTintAssets
python3 tools/perflab/ImageTintLab/prepare-isolated.py /tmp/ImageTintValidation
TINT_ASSET_BUNDLE=/tmp/ImageTintAssets/Probe.app swift test --package-path /tmp/ImageTintValidation --scratch-path /tmp/ImageTintValidation-build -c release
ASAN_OPTIONS=detect_leaks=0 TINT_ASSET_BUNDLE=/tmp/ImageTintAssets/Probe.app swift test --package-path /tmp/ImageTintValidation --scratch-path /tmp/ImageTintValidation-asan --sanitize address
TINT_ASSET_BUNDLE=/tmp/ImageTintAssets/Probe.app swift test --package-path /tmp/ImageTintValidation --scratch-path /tmp/ImageTintValidation-tsan --sanitize thread
TINT_BENCHMARK=1 TINT_ASSET_BUNDLE=/tmp/ImageTintAssets/Probe.app swift test --package-path /tmp/ImageTintValidation --scratch-path /tmp/ImageTintValidation-build -c release --skip-build --filter TintBenchmarkTests
TINT_BENCHMARK=1 TINT_REVERSE=1 TINT_ASSET_BUNDLE=/tmp/ImageTintAssets/Probe.app swift test --package-path /tmp/ImageTintValidation --scratch-path /tmp/ImageTintValidation-build -c release --skip-build --filter TintBenchmarkTests
```

Use fresh output directories. Run timing without competing compilers. The asset catalog contains real copy-code and peer-music PNGs, a PDF, an SVG, and a PDF configured to preserve its vector representation. Resource loading uses `Bundle.image(forResource:)`, the underlying implementation of the app's Xcode-generated `NSImage(resource:)` initializer. The initializer audit is in `../ChatLayerEngineLab/results/quote-icons/app-loader/generated-loader.json`.

## Measurements

Release measurements on arm64 macOS, with nine paired batches per workload and a second run reversing the starting order. The candidate path calls the public production `precomposed` API. Times are microseconds per operation:

| Workload | Original | Cached | Reduction |
| --- | ---: | ---: | ---: |
| Retained icon, one color | 14.48–15.17 | 1.84–1.93 | 87% |
| Retained icon, eight colors | 14.53–14.80 | 1.87–1.92 | 87% |
| Load and tint copy-code asset | 49.43–51.56 | 34.85–35.78 | 29–31% |
| Load and tint peer-music chevron | 48.79–51.94 | 34.35–35.81 | 30–31% |
| Load and tint vector collectible asset | 66.67–67.00 | 44.65–44.68 | 33% |
| Update two real ImageViews with peer-music icons | 101.84–102.81 | 71.85–72.33 | 29–30% |

The two-view workload loads the real waveform and chevron assets, assigns their tinted results to real TGUIKit ImageViews and runs `sizeToFit`. It excludes labels, surrounding profile/chat rows, display rasterization and presentation. It does not establish whole-app scrolling FPS or opening latency.

A cache-thrashing cycle of 128 colors costs 3.6–4.1% more (0.54–0.60 µs); 128 distinct sources cost about 4% more (0.49–0.51 µs). Untinted, gradient, zoom and large-image fallback workloads vary by less than 1% between implementations in these runs. The first version had 5–8% miss overhead; intermediate source and timing snapshots are retained to show the effect of constant-time eviction, avoiding repeated hashing/size reads, and eliminating the redundant clear. Hit rates in real app usage have not been measured, so these are component tradeoffs, not an unconditional app-wide speedup.

For 1,000 retained identical copy-code tints at 2×, the baseline has 1,000 unique output bitmaps (4,096,000 bytes) and the public API has one (4,096 bytes). Source images are released between requests. This counts unique rendered bitmap storage; it excludes array/reference overhead, cache metadata, image loading and total process memory.

## Validation scope

Fourteen functional tests compare both the extracted cache and public API against the captured original: exact normalized and raw pixels, bitmap format and color space, fractional geometry, scales including automatic scale, both flips, gradients/zoom/fallback cases, dynamic appearances, pattern colors, mutable bitmap data, animated frame changes, representation replacement, 16-bit floating-point output, graphics-format invalidation, eviction limits, source lifetime, and 1,200 concurrent requests. Raster/vector assets are tested at native and icon sizes. A crop test confirms that its 16 MiB source data is released while the tinted output remains cached. Repeated resource loads verify output sharing.

The app itself is not built or profiled by this lab. Sanitizer runs disable leak detection for Address Sanitizer and exercise this component, not the full application. The final release, Address Sanitizer and Thread Sanitizer runs each pass all 14 functional tests, with the optional benchmark skipped. The frozen TGUIKit suite passes 397 functional tests with 18 optional tests skipped. The chat-layer/folding-text suite passes 337 functional tests with 33 optional measurements skipped. Sources, input hashes, raw batches, compressed logs and earlier experiments are retained in `results/`.

A concurrent table-animation edit changed `TGUIKit/Sources/TableView.swift` after validation. It is preserved and is outside this frozen test snapshot. The tinting implementation and the other recorded test inputs are unchanged. The performance workload uses ImageViews and does not instantiate a table.
