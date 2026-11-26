# Transform image argument delivery

TransformImageView now uses SwiftSignalKit's existing ValuePromise with repeated-value filtering. Previously every set(arguments:) built a single-value Signal, subscriber and disposable, updated a Promise, and only then filtered duplicates downstream. The new path retains and compares the current value before publishing. New image data still renders with unchanged arguments, and new subscriptions replay the latest arguments after clear, dispose or signal replacement. No extra argument cache or new framework is introduced.

This pass also fixes rendering/cache identity:

- TransformImageArguments equality now includes intrinsicInsets and resizeMode. Previously these fields were hashed but compared equal, and changing them could suppress the render or leave alreadyRendered active.
- ImageCorner equality now compares radii exactly. The old epsilon comparison was non-transitive near zero and inconsistent with exact radius hashing.
- Corner hashing includes the enum case and associated radius. Previously every Tail hashed its corner getter, which is always zero, producing the same TransformImageArguments cache key for different tail radii and zero-radius ordinary corners. PhotoCache uses the resulting hash as its lookup key, so these systematic collisions could return the wrong image geometry.

The regression tests reproduce the original failures: resize mode and inset changes produce only one render instead of four; rendered-cache invalidation fails; small distinct corner radii compare equal; different tail geometry has identical cache hashes. The saved before log contains 18 assertions failing across these cases. All pass after the fix.

## Measurements

Tests compile the real TGUIKit and SwiftSignalKit implementations. LegacyTransformImageView.swift is the complete source from a3a810b1d with class names prefixed, a testable TGUIKit import, and whitespace normalization; provenance.json records and verifies this capture. Both benchmark variants use the corrected TransformImageArguments equality, isolating delivery overhead rather than comparing a correct renderer with one that skips necessary updates.

Nine alternating release batches after warmup, microseconds per operation. The repeat run is shown; the first run is also retained.

| Operation | Original pipeline | Value promise | Reduction |
| --- | ---: | ---: | ---: |
| Repeated arguments without a subscriber | 0.5046 | 0.0989 | 80.4% |
| Repeated arguments with a subscriber | 0.5251 | 0.1011 | 80.7% |
| Changed arguments with a subscriber | 0.9620 | 0.5680 | 41.0% |
| Construct/destroy an image view | 4.8810 | 4.8085 | 1.5% |

The initial run measured 80–81% less repeated-update work and 41.4% less changed-update work. The small construction difference should be treated as noise. Each update batch has 20,000 operations; construction batches have 2,000. Rendering is a counting closure that returns nil, so these timings cover argument/signal handling rather than image decoding or drawing. Execution counts match between variants: one render for repeated arguments and one for each changed value. Whole-app scrolling, resident memory and decoding performance were not measured.

## Validation

Ten focused functional tests cover all argument fields, exact/transitive corner equality, cache keys, required redraws, argument replay, clear/dispose/rebind, new data with unchanged arguments, already-rendered invalidation, exact image pixels against the original pipeline, synchronous reentrant argument replay, background rendering, main-thread delivery and real protected sample-buffer generation. Nonblank images differ across mode/inset changes, while each original/current pixel pair is exact. The pixel comparison uses a small DrawingContext renderer; full Telegram media decoding is outside this harness.

The complete TGUIKit suite passed 260 functional tests (8 optional benchmarks skipped), and the chat mini-app passed 134 functional tests (14 optional benchmarks skipped), in both release and AddressSanitizer builds: 394 functional tests per configuration, with zero failures. Full Telegram is not built. Results and original failure logs are in results/; OriginalArguments.swift.txt retains the old equality and hashing for inspection.

```sh
swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release -c release --filter 'TransformImageArgumentsTests|TransformImageViewTests'
TRANSFORM_IMAGE_BENCHMARK=1 swift test --skip-build --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release -c release --filter TransformImageBenchmarkTests
```
