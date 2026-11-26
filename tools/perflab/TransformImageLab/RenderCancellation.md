# Cancellation checkpoints for image rendering

TransformImageView previously rejected stale results at delivery, but a transform already executing still finalized its DrawingContext, converted pixels into the display color space, and built a protected-content sample buffer when requested. A synchronous source could also cancel its own binding during startup and still enter the transformation before its returned subscription was disposed.

The view now cancels its render state before disposing the upstream subscription. The rendering pipeline checks that state at entry, after drawing returns a non-nil context, and before protected-buffer conversion. Clear, replacement, explicit disposal and view deallocation all invalidate the state. Work already inside a drawing or conversion operation is not interrupted; these are cooperative checkpoints. Cancellation just after a checkpoint can still allow that stage to finish.

The render state replaces the existing Atomic used for the already-rendered shortcut. It uses a small os_unfair_lock, the same primitive already used by TGUIKit's display-link gate. No lock is held while invoking transformations, comparing arguments, converting pixels or disposing subscriptions. Replaced argument values are released outside the lock. Existing source-version guards continue to protect delivery and reentrant callbacks.

## Evidence and baseline

LegacyImageRenderView.swift captures TransformImageView at aac2dcb7c, with class names changed, a testable import and whitespace normalization. The seven final regression tests exercise cancellation during source startup, drawing and image generation; background dispose, clear, replacement and deallocation; context release; active pixel/protected-buffer parity; and invalidation of the already-rendered shortcut by incomplete data. The initial six-test baseline run produced ten expected failures because cancelled work still executed or finalized. The final suite adds coverage for replacement during image generation.

The first candidate kept an Atomic tuple for cancellation and cached arguments. It passed the full release suite but increased trivial nil-transform costs. The final compact state removes that overhead and uses less object storage. Its predecessor, logs and benchmark data are retained separately as atomic-* artifacts for comparison.

## Measurements

The release benchmark alternates baseline/candidate order across nine batches after warmup. Cached and nil-transform cases use 10,000 operations per batch, active 32-by-32-pixel rendering uses 1,000, and cancellation cases use 20. Large fixtures draw a 1,024-by-1,024-pixel context at scale 1 with Display P3 conversion enabled. Cancellation is injected at a known synchronous boundary; functional tests separately verify cancellation from the main thread while a worker is drawing. These timings exclude network requests, decoding real media, scrolling and application-level scheduling.

Median microseconds per operation from the final repeat:

| Operation | Original | Updated |
| --- | ---: | ---: |
| Cached image rebind | 1.1417 | 1.1230 |
| Cached image stream | 0.2891 | 0.2891 |
| Nil transform rebind | 4.3860 | 4.3775 |
| Nil transform stream | 0.3716 | 0.3695 |
| Active 32-pixel image stream | 5.5633 | 5.5553 |
| Active protected image stream | 64.2068 | 64.6847 |
| Cancel after drawing, ordinary image | 401.5625 | 51.6500 |
| Cancel after drawing, protected image | 3,096.2667 | 51.4333 |
| Cancel during image generation, protected image | 3,163.6271 | 382.9563 |

Across the two final runs, cancellation after drawing reduced fixture time by approximately 83–87% for ordinary images and 98% for protected images. Cancellation during image generation reduced the protected fixture by approximately 88% by avoiding the subsequent buffer conversion. Active rendering and cached delivery remained close to baseline; the protected active stream was 0.6–0.7% slower. These are fixture measurements, not whole-app speedups. Other repository compiler activity was observed during exploration; the final runs started after checks found no live compiler/test process.

For each cancellation-after-drawing scenario, the original finalized 190 images across warmup and measured batches; the updated pipeline finalized zero. Both finalized 190 images in the during-generation scenario, where the later checkpoint skips protected-buffer creation. Active output/callback counts must match in the benchmark.

The allocation check uses malloc_size on real instances. Both view instances occupy 640 bytes. The original Atomic state occupies 320 bytes and the new state 224 bytes: one state allocation in either implementation, with 96 fewer object bytes per transform binding on the tested host. This does not measure resident memory, allocator metadata or whole-app memory.

The final implementation passed all 298 TGUIKit functional tests and all 134 chat mini-app functional tests in both release and AddressSanitizer: 432 in each configuration. There were 13 and 14 optional benchmarks skipped, respectively. All 21 image lifecycle tests also passed ThreadSanitizer without a race report.

Source hashes and raw logs are recorded in render-cancellation-provenance.json and results/render-cancellation/. Tests use the current working tree, including unrelated pending changes. The full Telegram application was not built or benchmarked.

```sh
swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release -c release --filter TransformImageRenderCancellationTests
IMAGE_RENDER_BENCHMARK=1 swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release -c release --filter TransformImageRenderBenchmarkTests
swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-tsan --sanitize thread --filter 'TransformImage(RenderCancellation|Signal)Tests'
```
