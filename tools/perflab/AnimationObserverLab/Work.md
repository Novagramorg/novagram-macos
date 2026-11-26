# Observer construction and hierarchy lookup work

The shared animation observer is used by table rows, chat titles, avatars, sticker/media views, reactions and other screens. Its convenience update method previously asked AppKit for the enclosing scroll view twice. Selector observers did that even for detached views, before discovering that there was no window to observe. They also allocated a forwarding receiver during construction, including for observers never attached to a window.

The receiver is now lazy. It is created on the first registration and retained for later reuse. Detached selector updates unregister without walking the scroll hierarchy. Attached selector and token updates obtain the scroll container once and use that same container for both content and document views. Existing callback delivery, registration identity and unregister behavior are preserved.

## Rejected consolidation

An experiment made the observer itself the NSObject notification receiver, removing the separate receiver. That changed lifetime behavior: when the client released the observer inside a callback, NotificationCenter still kept the receiver alive during delivery. A nested notification then invoked the callback again. The original implementation unregisters immediately when the separate owner is released.

The targeted test passed on the original implementation and failed with two assertions on the consolidated experiment: the owner was still alive, and two callbacks arrived instead of one. The experiment was rejected. Its source and failure log are preserved in Evidence/work/rejected-consolidation.*. The final implementation retains the separate receiver and passes the reentrant lifetime test.

## Measurements

BaselineCompactObserver.swift captures the implementation at d23460572, with renamed classes, the unchanged public options type imported from TGUIKit, a testable import and whitespace normalization. Benchmarks use real AppKit view hierarchies with zero, four or sixteen additional ancestor views between the observed view and its scroll document. Each case has 100 warmup operations and nine alternating baseline/candidate batches of 10,000 operations.

The construction case retains all 10,000 observer objects in an array, then releases them within the timed batch. Its measurement includes construction, array storage and cleanup. Binding cases repeatedly update actual observer instances after warmup. They do not measure rendering, animation callbacks or scrolling frame time. Times are small, in tens or hundreds of nanoseconds per operation; percentage changes do not represent whole-app speedups.

Median nanoseconds per operation from the expanded repeat run:

| Operation | Original | Updated |
| --- | ---: | ---: |
| Construct/store/release observer | 62.3 | 35.1 |
| Detached update, depth 0 | 32.0 | 11.4 |
| Detached update, depth 4 | 53.3 | 9.8 |
| Detached update, depth 16 | 115.8 | 10.6 |
| Selector binding, depth 0 | 110.3 | 97.3 |
| Selector binding, depth 4 | 101.0 | 83.9 |
| Selector binding, depth 16 | 164.0 | 116.9 |
| Token binding, depth 0 | 110.9 | 85.9 |
| Token binding, depth 4 | 100.2 | 75.5 |
| Token binding, depth 16 | 165.6 | 103.7 |
| Explicit-container selector binding | 43.6 | 46.4 |

Across the expanded runs, construction/cleanup was approximately 43–44% faster, attached hierarchy-based binding 12–37% faster and detached updates 64–91% faster. The explicit-container selector path was 5–6% slower, an absolute increase of approximately 2–3 nanoseconds per call. This small lazy-access cost is retained in exchange for deferred allocation and reduced hierarchy work. Initial measurements before adding the explicit case are retained separately. Other repository builds ran between measurements; the expanded runs started after checks found no live compiler or test process.

The allocation check inspects live objects with malloc_size. Both observer instances occupy 80 bytes. The original also allocates a 32-byte forwarding receiver immediately; the updated unused observer has no receiver. Once observation starts, the receiver is allocated and reused even after detach. This avoids one allocation for observers that have not yet registered; it does not reduce the receiver storage of already-used observers or establish a resident-memory saving.

## Validation

Eight new functional tests cover attached and detached hierarchy lookup counts, explicit-container updates, lazy receiver creation and reuse, release during nested delivery, and detach/re-attach during delivery. The existing observer suite also checks retargeting, options, selectors, independent listeners, source/target lifetimes and table-row reparenting. The original six-test fixture produced five expected lookup-count failures; the final fixture adds two receiver-allocation tests.

The final implementation passed all 306 TGUIKit and 134 chat mini-app functional tests in release and AddressSanitizer: 440 in each configuration. Each suite skipped 14 optional benchmarks. Only the opt-in timing harness was subsequently expanded; the eight observer regressions and the expanded benchmark were rerun successfully.

Raw measurements, the failed experiment, source hashes and validation logs are in Evidence/work/ and work-provenance.json. These are working-tree package and mini-app checks, including unrelated pending changes. The full Telegram application was not built or benchmarked.

```sh
swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release -c release --filter 'Animat(ionObserver|ableContentObserver)'
OBSERVER_WORK_BENCHMARK=1 swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release -c release --filter AnimationObserverWorkBenchmarkTests
```
