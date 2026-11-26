# Shared color equality fast path

Both `Colors` and `TGUIKit` define an `NSColor ==` overload that compares packed ARGB values. Each operand previously converted to device RGB even when both operands were the same object. Both overloads now return true immediately for identical objects, then use the unchanged ARGB comparison for distinct objects. No cache or retained state is added.

This also reduces the cost of `ControlStyle` equality, which compares foreground and background colors. `Control.style` uses that equality when deciding whether to reapply a style. The optimization benefits callers that reuse palette color objects; different objects still take the existing conversion path, including different objects representing the same packed color.

## Native validation

Separate probe modules import the real `Colors` and `TGUIKit` packages so the two overloads are tested independently. Candidate probes invoke the actual production operators. `prepare.py` extracts the original operator bodies from baseline `33863a272` for reference probes and verifies that ARGB conversion code is unchanged. It also verifies the original and current `ControlStyle` predicates against the reference style wrapper. The style reference uses the old color probes, while the candidate invokes actual `ControlStyle` equality.

Eight functional tests cover:

- Counting NSColor subclasses prove that identical-object comparisons perform zero conversions, versus two before, and that distinct-object comparisons retain both conversions.
- A 128×128 randomized matrix runs against both modules: 32,768 comparisons of candidate and baseline results.
- Packed-color rounding, alpha, grayscale, sRGB, Display P3, and CMYK behavior remain equivalent to the reference for tested inputs.
- Dynamic and system colors are compared under light, dark, and both high-contrast appearances.
- Optional color equality keeps its Foundation behavior.
- Seventy-two real ControlStyle pairs preserve comparison results; shared foreground/background objects avoid four conversions per style comparison.

The baseline reproduced four expected conversion-count assertion failures. The initial harness lacked TGUIKit's default presentation resources and stopped during style setup; the standard mini-app bootstrap supplies those resources, and that diagnostic log is retained. Tests exercise AppKit colors and real framework implementations. They do not render the full Telegram application or estimate end-to-end scrolling improvements.

## Benchmark

Each color batch compares 128 pairs 100 times. Nine paired batches alternate order after warmup; a separate run reverses the initial ordering. Result counts are checked for every batch. Equality between distinct-but-equal colors is measured separately, with an identity assertion ensuring the objects really differ. Reference and candidate color probes are marked non-inline to keep the comparison loops observable. Style timings include the wrapper/predicate calls, so they are microbenchmark results rather than complete control update times.

| Case | Before µs/comparison, first / repeat | After µs/comparison, first / repeat |
|---|---:|---:|
| TGUIKit, shared objects | 1.109 / 1.057 | 0.0052 / 0.0048 |
| TGUIKit, half shared | 1.053 / 1.047 | 0.527 / 0.521 |
| TGUIKit, different values | 1.067 / 1.044 | 1.067 / 1.051 |
| TGUIKit, equal distinct objects | 1.076 / 1.040 | 1.070 / 1.043 |
| Colors, shared objects | 1.090 / 1.054 | 0.0052 / 0.0051 |
| Colors, half shared | 1.056 / 1.046 | 0.531 / 0.532 |
| Colors, different values | 1.075 / 1.050 | 1.094 / 1.043 |
| Colors, equal distinct objects | 1.090 / 1.053 | 1.073 / 1.050 |
| ControlStyle, shared colors | 2.483 / 2.353 | 0.0406 / 0.0382 |

Shared colors are roughly 200× cheaper in these runs, shared-color style comparisons roughly 60× cheaper, and the half-shared case roughly halves the work. Distinct-object comparisons remain near baseline. These ratios apply only to the measured comparisons; total app CPU, memory, and frame-time gains remain unmeasured.

## Reproduce

```sh
python3 tools/perflab/ColorEqualityLab/prepare.py
swift test --package-path tools/perflab/ColorEqualityLab -c release
COLOR_EQUALITY_BENCHMARK=1 swift test --package-path tools/perflab/ColorEqualityLab -c release
COLOR_EQUALITY_BENCHMARK=1 COLOR_EQUALITY_REVERSE=1 swift test --package-path tools/perflab/ColorEqualityLab -c release
swift test --package-path tools/perflab/ColorEqualityLab --sanitize address
swift test --package-path tools/perflab/ColorEqualityLab --sanitize thread
swift test --package-path packages/TGUIKit -c release
```

Use separate scratch paths and sequential builds. Save `/tmp/color-equality-benchmark.json` before each repeat. `results/` preserves logs, raw samples, source hashes, reference probes, production changes, and the final validation summary. Source parsing separately checks both modified files.

Final validation passed: eight new functional tests, 371 existing TGUIKit functional tests (389 total, 18 opt-in tests skipped), both benchmark orders, and all eight color tests under each of Address Sanitizer and Thread Sanitizer. Both modified source files parsed successfully. No sanitizer errors were reported.
