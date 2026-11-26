# Image assignment and display registration

This follow-up fixes reentrant image assignment and removes redundant display-cache work in TransformImageView. It builds on the argument-delivery changes documented in README.md.

The image setter previously notified imageUpdated before committing the new stored image. Observers could read the old value, assigning the same image again could recursively notify, and a replacement or clear inside the callback left stored image state inconsistent with layer contents. The setter now commits the stored image before notifying. Three regression cases produced nine failed assertions with the original implementation; all pass with the new one.

Fresh transformation results previously called noteImageDisplayed inside the setter and again after cacheImage. The first scan happens before the new image enters the cache. The internal update path now defers display registration until after cacheImage, preserving the registration needed for screen-scoped eviction while removing the earlier registry/cache scan. Public image assignments and cached-result delivery continue to register immediately. The temporary sample-buffer property is removed; supplied buffers travel directly to the internal update method.

Repeated nil assignments avoid setting already-empty layer contents, including the parent layer of capture-protected views. Assigning an image still restores externally changed contents. Nonempty assignments continue through Core Animation's own handling: an initial explicit identity check made repeated image updates 31% slower and restoration 20% slower, so that candidate was rejected. Its measurements are retained in results/assignment/rejected-identity-guard.json.

## Measurement

LegacyImageAssignmentView.swift is the complete production view from commit 569374b56, with class names changed, a testable import added, and whitespace normalized. assignment-provenance.json records the source and test hashes. Both variants use the same current argument type and ValuePromise implementation.

The release fixture uses actual AppKit views attached to a window, real CALayer contents, six live ScopedImageCache instances (the number of cache types in PhotoCache.swift), and real protected content layers. Nine batches alternate execution order. Each batch has 20,000 operations, except fresh rendering, which has 2,000. Both variants must produce the same notification counts and final images. Fresh rendering creates a 16-point solid-color DrawingContext, generates its image, stores it in the cache, and registers the display scope. Its final images are compared pixel-for-pixel.

Median microseconds per operation from the repeat run:

| Operation | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| Fresh render, cache insertion and display | 8.8785 | 8.5065 | 4.2% |
| Repeated nonempty image | 0.0621 | 0.0565 | 9.1% |
| Repeated empty image | 0.0347 | 0.0241 | 30.5% |
| Repeated protected image | 0.0628 | 0.0468 | 25.5% |
| Alternating images already cached | 1.0487 | 1.0342 | 1.4% |
| Repeated cached-result signal | 0.9414 | 0.9002 | 4.4% |
| Restore externally replaced layer contents | 0.2845 | 0.2751 | 3.3% |

The first run measured 7.4% less fresh-render work, 9.2% less repeated nonempty work, 30.3% less empty work and 26.1% less protected work. Differences for cached-result delivery and alternating cached images are small and variable. These are operation-level measurements, not whole-app scrolling or decoder improvements. Memory usage was not benchmarked.

## Regression coverage

Seven new functional tests cover committed state during callbacks, same-image callback assignment, replacement and clearing during callbacks, restoring externally modified layer contents, capture toggling during callbacks, repeated empty layer assignments, and distinct images with identical pixels. The existing image pipeline tests cover background transforms, supplied protected buffers, cache skips, replay, and exact image pixels. ScopedImageCache tests cover fresh and cached display attribution, attachment to a window, shared scopes and eviction after screen closure.

The complete suites passed in both release and AddressSanitizer: 267 TGUIKit functional tests (9 optional benchmarks skipped) and 134 chat mini-app functional tests (14 optional benchmarks skipped), totaling 401 functional tests per configuration. No full Telegram build or whole-app frame-time measurement was performed.

```sh
swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release -c release --filter 'TransformImageAssignmentTests|TransformImageViewTests|ScopedImageCacheTests'
IMAGE_ASSIGNMENT_BENCHMARK=1 swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release -c release --filter TransformImageAssignmentBenchmarkTests
```
