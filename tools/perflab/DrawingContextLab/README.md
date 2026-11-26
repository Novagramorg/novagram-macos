# Drawing-context settings snapshot

`DrawingContext` now reads `DeviceGraphicsContextSettings.shared` once during construction and uses the bitmap context's actual color space when exporting an image. Previously construction independently read four locked settings snapshots, and export read the current global color space. A format change between drawing and export could label existing sRGB pixels as Display P3. The focused regression test reproduces that error in the original implementation and checks the corrected output.

The change adds no stored property, cache or allocation. It does not change buffer sizing, clearing, drawing transforms, image-provider lifetime or bitmap encoding.

## Reproduce

The repository directory is a template. Generate an isolated lab before running Swift Package Manager:

```sh
python3 tools/perflab/DrawingContextLab/prepare-isolated.py /tmp/DrawingContextValidation
swift test --package-path /tmp/DrawingContextValidation --scratch-path /tmp/DrawingContextValidation-build -c release
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/DrawingContextValidation --scratch-path /tmp/DrawingContextValidation-asan --sanitize address
swift test --package-path /tmp/DrawingContextValidation --scratch-path /tmp/DrawingContextValidation-tsan --sanitize thread
DRAWING_CONTEXT_BENCHMARK=1 swift test --package-path /tmp/DrawingContextValidation --scratch-path /tmp/DrawingContextValidation-build -c release --skip-build --filter ContextBenchmarkTests
cp /tmp/drawing-context-benchmark.json /tmp/drawing-context-forward.json
DRAWING_CONTEXT_BENCHMARK=1 DRAWING_CONTEXT_REVERSE=1 swift test --package-path /tmp/DrawingContextValidation --scratch-path /tmp/DrawingContextValidation-build -c release --skip-build --filter ContextBenchmarkTests
cp /tmp/drawing-context-benchmark.json /tmp/drawing-context-reverse.json
```

Use a fresh output directory and run benchmarks without competing compilers. The generator compiles two complete copies of TGUIKit. The baseline restores the captured original DrawingContext class; all other source files are identical. Both public APIs are called from the same test module, avoiding the different optimization boundaries of an extracted reference class. The default benchmark runs before installing custom settings; separate cases cover installed sRGB, half-float linear sRGB and display conversion to P3. Nine paired batches alternate execution order, and a second process reverses the initial order.

## Validation scope

Five functional tests cover 120 exact raw-pixel/geometry comparisons across three formats, four sizes, five scales and two flip combinations; six exact display-conversion comparisons; the reproduced color-profile bug; image lifetime after the drawing context is released; and 2,000 concurrent creations while another worker changes source formats 2,000 times. Tests compare color spaces, bitmap formats, dimensions, row bytes and pixel data.

The format-changing concurrency test disables display conversion. Simultaneous source-format changes with an active global display converter are outside this change's scope. Display conversion is tested with a fixed source format. Address Sanitizer runs disable leak detection. These tests and benchmarks do not build the complete application or measure scrolling FPS, media decoding or total app memory.

## Measurements

Release results from two complete TGUIKit libraries, in microseconds per operation. Percentages are time saved; negative numbers indicate more time.

| Workload | Forward order | Reversed order |
| --- | ---: | ---: |
| default_16x16_construct | 1.067 → 1.028 (+3.6%) | 1.039 → 1.040 (-0.1%) |
| default_16x16_paint_export | 7.831 → 7.794 (+0.5%) | 8.048 → 8.231 (-2.3%) |
| default_120x80_construct | 1.577 → 1.554 (+1.5%) | 1.659 → 1.632 (+1.6%) |
| default_512x288_paint_export | 664.907 → 663.569 (+0.2%) | 685.139 → 683.618 (+0.2%) |
| default_four_workers_800_contexts | 1342.578 → 1304.125 (+2.9%) | 1323.995 → 1286.833 (+2.8%) |
| installed_srgb_four_workers_800_contexts | 1315.089 → 1266.302 (+3.7%) | 1306.708 → 1254.771 (+4.0%) |
| installed_float_four_workers_800_contexts | 1458.323 → 1393.042 (+4.5%) | 1388.292 → 1331.224 (+4.1%) |
| display_p3_16x16 | 11.126 → 11.311 (-1.7%) | 10.289 → 10.404 (-1.1%) |

Four-worker construction/export uses 2.8–2.9% less time under app-default settings and 3.7–4.5% less under installed settings. Default small-context creation ranges from effectively unchanged to 3.6% faster. Complete painting/export and display conversion are mixed and close to unchanged; the small default painting workload is 2.3% slower in the reversed run, and small P3 conversion is 1.1–1.7% slower. These results support a modest reduction in synchronization overhead, not a broad rendering-speed claim. Both context objects allocate 112 bytes; retained memory is unchanged.

The color-profile regression requires graphics settings to change. Current AppDelegate calls to install settings are commented out, so the regression demonstrates API correctness rather than a confirmed visible bug in current app usage.

## Recorded regression results

Release, Address Sanitizer and Thread Sanitizer each pass all five focused functional tests; each skips the opt-in benchmark. The frozen TGUIKit suite passes 397 tests and skips 18 optional measurements. The chat/folding-text suite passes 336 tests and skips 34; its fixture-dependent asset-loader test is then run separately with the compiled icon bundle and passes, bringing functional coverage to 337 tests. The icon-tint suite passes all 14 functional tests with one benchmark skipped.

Both complete library source trees and their test sources reproduce exactly. All 1,316 recorded compiler inputs remain unchanged after validation. The final production source matches the frozen tested implementation. Results include raw paired batches, complete compressed logs, candidate/baseline drawing sources and input hashes. Exploratory extracted-reference timings are excluded from the reported results because their compilation boundary differed from production.
