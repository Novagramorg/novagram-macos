# Shared attributed-text factory

`NSAttributedString.initialize(string:color:font:)` previously created an empty mutable string, appended a separate attributed string, applied its attributes, and copied the result. Styled text now initializes the mutable builder with its final string, applies the same attributes, and retains the immutable-copy boundary. Unstyled, nil, and empty inputs construct the immutable result directly.

This removes intermediate construction and append work without a cache or extra retained state. The separate mutable-string `append(string:color:font:)` method is unchanged, including its attribute inheritance behavior. Default arguments and public signatures are unchanged. The factory is used throughout the app: a source inspection found 212 `.initialize(string:` occurrences in ChatUI, 62 in ChatListUI, 38 in TGUIKit, 16 in PeerInfoUI, 13 in PeerMediaUI, and 14 in ShortPeerRow. These are textual occurrences, not runtime invocation counts.

## Native validation

The candidate invokes the real TGUIKit implementation. `prepare.py` extracts the original method from `b134e8654`, renames it for the reference, and verifies that its original append and setFont dependencies remain unchanged. `generation.json` records hashes. A small AppKit bootstrap provides the named presentation icons required by TGUIKit.

Eight functional tests cover:

- 350 combinations of nil/empty/Unicode text, optional fonts, and optional colors. Every UTF-16 position has matching attribute values, keys, and effective ranges.
- Default arguments and explicitly omitted attributes.
- Fifty empty/nil combinations followed by mutable-copy insertion and append, preserving subsequent inheritance behavior.
- Independent mutable copies without mutation of other returned strings.
- Dynamic color identity and comparison under four system appearances.
- 1,000 deterministic randomized Unicode and attribute combinations.
- 2,000 concurrent construction comparisons across eight workers, including independent mutable-copy edits.
- Matching line geometry and 48 exact rendered-pixel comparisons across three scales, nil/explicit colors, Latin, RTL, CJK, emoji, combining marks, wrapping, and empty text. Nonempty samples must produce nonblank pixels.

The unchanged baseline passes the original seven functional tests. An initial harness compile error used an unavailable italic-font convenience name; the corrected harness uses AppKit's font manager. Its diagnostic log is retained.

## Performance

Nine paired release batches alternate original/candidate order after warmup. A separate run reverses the initial order. Factory cases perform 4,000 calls per batch with a per-call autorelease pool. The row-binding case performs 400 calls, constructing a real TextViewLayout, measuring it at 180 points, and updating a real TextView with one of 40 message previews. Result lengths are consumed. The view is not attached to a live Telegram chat.

Median microseconds per call:

| Input | Before, first / repeat | After, first / repeat |
|---|---:|---:|
| Short styled label | 0.8240 / 0.8332 | 0.7438 / 0.7310 |
| Styled emoji | 0.8548 / 0.8568 | 0.7705 / 0.7545 |
| Long styled text | 1.1822 / 1.1838 | 1.1153 / 1.1015 |
| Font only | 0.6290 / 0.6290 | 0.5565 / 0.5475 |
| Color only | 0.6212 / 0.6167 | 0.5605 / 0.5537 |
| Plain text | 0.4550 / 0.5205 | 0.0677 / 0.0810 |
| Empty text | 0.3175 / 0.3220 | 0.0452 / 0.0440 |
| Nil text | 0.2465 / 0.2470 | 0.0492 / 0.0472 |
| Construction, measurement, and view update | 18.6625 / 18.3150 | 18.2050 / 17.9499 |

Styled creation saves roughly 6–13%, plain/empty/nil creation roughly 80–86%, and the synthetic row-binding sequence about 2–2.5%. This is not an estimate of full chat opening or scrolling gains. No full app build, process-memory reduction, or GPU performance measurement is claimed.

## Alternatives and rejected work

The first version built a Swift attributes dictionary incrementally and passed it to the immutable initializer. It preserved behavior but slowed short styled strings (about 0.829 to 0.902 microseconds in the first run) and the row-binding case. The rejected diff and measurements are saved under `results/incremental-dictionary*`.

The alternatives benchmark rotates four implementations across ten batches, discards the first batch, checks output equality, and records nine samples. Literal dictionaries were better for long styled input but gave little benefit for common short styled labels. Direct mutable construction was fastest for short styled labels and font-only labels; direct immutable construction was fastest for plain input. The chosen implementation improves all measured cases without a machine-specific string-length threshold. The alternatives are retained for future investigation. Initial alternative code and results are archived; the reproducible version keeps the rejected incremental implementation locally instead of calling the now-updated production method.

## Reproduce

```sh
python3 tools/perflab/AttributedTextFactoryLab/prepare.py
swift test --package-path tools/perflab/AttributedTextFactoryLab -c release
TEXT_FACTORY_BENCHMARK=1 swift test --package-path tools/perflab/AttributedTextFactoryLab -c release
TEXT_FACTORY_BENCHMARK=1 TEXT_FACTORY_REVERSE=1 swift test --package-path tools/perflab/AttributedTextFactoryLab -c release
TEXT_FACTORY_ALTERNATIVES=1 swift test --package-path tools/perflab/AttributedTextFactoryLab -c release
swift test --package-path tools/perflab/AttributedTextFactoryLab --sanitize address
swift test --package-path tools/perflab/AttributedTextFactoryLab --sanitize thread
swift test --package-path packages/TGUIKit -c release
```

Run sequentially with separate scratch paths. Save `/tmp/attributed-text-factory-benchmark.json` before repeating the primary benchmark; the alternatives write `/tmp/attributed-text-alternatives.json`. Raw samples, logs, the reference source, and input hashes are retained in `results/`.

Final validation passed on arm64 macOS 26.4: eight new functional tests, 371 existing TGUIKit functional tests (389 total, 18 opt-in tests skipped), both benchmark orders, and all eight new tests under each of Address Sanitizer and Thread Sanitizer. No sanitizer errors were reported. The changed production source parsed successfully, and all 257 recorded source/test inputs remained unchanged through final verification.
