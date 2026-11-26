# Inline emoji layer ownership lab

The helper-only frozen release snapshot passed 14 tests, including six exact bitmap pairs; historical evidence is recorded in `results/helper-release`. The current helper has since gained synchronous-reentry protection and live integration is under development in ChatLayerEngineLab. Those changes require a fresh snapshot and validation. This lab does not establish a performance improvement or validate the live row integration.

`prepare.py` copies the exact current `ChatLayerInlineEmoji.swift` into a fresh directory under `/tmp`, without rewriting its declarations or imports. It recursively freezes TGUIKit and its local Swift-package dependencies, rewrites only dependency paths, checks source stability, and records original-source and frozen-file SHA-256 hashes. Builds run entirely against that snapshot. The checked-in lab is a template and must be prepared before building.

The helper compiles against real TGUIKit, TextViewLayout, TextView, AppKit views/windows, and Core Animation layers. Minimal modules named TelegramContext, InputView and InlineStickerLayer stand in for account and media services. They model account identity, source descriptors, immutable base/tint colors, layer ownership, playback flags and resource lifetime. The media stand-in produces a deterministic static bitmap. It does not run Lottie, resolve Telegram files, perform asynchronous fetching, decode real media, share player contexts, or exercise production media completion callbacks. Those remain integration gates.

Visibility follows the native `updateInlineStickerPlayback` contract: when the window is not key or emoji are in lite mode, every layer is paused without geometry work; otherwise each layer's clipped visibility decides playback. The helper no longer writes `isVisibleForFetching` (a no-op for `.always` layers; the tests assert it stays false). One visible region is computed per host refresh and shared by every block's helper. The real emoji initializer uses `fetchMode = .always`. Setting `isVisibleForFetching = false` therefore does not suppress or cancel its media requests. Pausing controls playback; subscription cleanup relies on the removed layer actually reaching deinitialization. The initializer can also synchronously initialize resources before the helper assigns `isPlayable = false`. The native implementation uses the same constructor. This slice does not change those media APIs, and the stand-in tests do not prove fetch cancellation or absence of work before playback is disabled.

The functional tests cover immutable-source/color/size/account/context/occurrence reconciliation, duplicate and reordered occurrences, tiny measured items, unsupported source kinds/policies, removal/deallocation, weak ownership, pause/resume, coordinate conversion, nested ancestor clipping, mask bounds, hidden and zero-alpha ancestors, scrolling, key-window state and lite mode. Visibility notifications are driven explicitly; this tests the helper's visibility decision, not the future scene observer wiring.

Six exact bitmap comparisons cover deterministic media placement against native TextView embedded-layer coordinates at 1×/2×/3× scales with LTR and RTL prefixes. Both sides use identical static test imagery. This checks geometry/layer composition, not real emoji rendering or loading behavior.

Eligibility for future live integration must still reject spoilers, streaming, non-looping policies, avatars and folding masks until their dedicated behavior is implemented and tested. The helper treats nonempty mask frames as conservative clipping bounds; it does not sample arbitrary alpha masks or presentation-layer animation frames.

Run the following serially after other builds and benchmarks finish:

```sh
python3 tools/perflab/InlineEmojiLayerLab/prepare.py /tmp/InlineEmojiLayerCheck
swift test -c release --package-path /tmp/InlineEmojiLayerCheck --scratch-path /tmp/InlineEmojiLayerCheck-release
ASAN_OPTIONS=detect_leaks=0 swift test --sanitize address --package-path /tmp/InlineEmojiLayerCheck --scratch-path /tmp/InlineEmojiLayerCheck-asan
swift test --sanitize thread --package-path /tmp/InlineEmojiLayerCheck --scratch-path /tmp/InlineEmojiLayerCheck-tsan
```

Do not rerun preparation into an existing snapshot. `provenance.json` records every frozen input before compilation; source changes require a new snapshot.
