# TGUIKit text button performance lab

This standalone AppKit mini-app benchmarks the real TGUIKit package without building Telegram or TelegramCore. TextButton appears throughout chat actions, chat-list controls, and shared navigation. `--preview` opens a scrollable window with 100 buttons; click to change their selection and animate their subtitles.

The baseline is `TitleButton.swift` at commit `4d3f1f417`. `prepare.py` copies the current TGUIKit package into a temporary directory, substitutes only that file for the baseline, and uses identical dependencies and benchmark code for both variants. It records the source hashes and compiler version. It does not switch or overwrite the working checkout.

```sh
bash tools/perflab/TextButtonLab/run.sh baseline > tools/perflab/TextButtonLab/Evidence/baseline.json
bash tools/perflab/TextButtonLab/run.sh candidate > tools/perflab/TextButtonLab/Evidence/candidate.json
python3 tools/perflab/TextButtonLab/compare.py
bash tools/perflab/TextButtonLab/run.sh candidate --preview
```

Run variants sequentially without other CPU-heavy work. Each of the six cases has seven trials, 400 controls per trial, and ten update passes. The cases cover title-only and subtitled state changes followed by sizing, genuinely different hover styles, changing title and subtitle content, width-only changes, and repeated setters. Each trial records construction/configuration time, update time, and the change in live malloc bytes after construction while the controls remain retained. A nested autorelease pool drains temporary construction objects before memory is sampled. The malloc measurement includes AppKit activity and is approximate; it is not total process memory or allocation traffic.

## Measured results

Median update times for 4,000 operations on this Apple Silicon machine, in release mode:

| Fixture | Baseline | Optimized | Reduction |
|---|---:|---:|---:|
| Title state + sizing | 93.80 ms | 6.08 ms | 93.5% |
| Title/subtitle state + sizing | 157.02 ms | 9.61 ms | 93.9% |
| Distinct hover font/color + sizing | 185.98 ms | 128.97 ms | 30.7% |
| Changing title and subtitle + sizing | 248.69 ms | 109.06 ms | 56.1% |
| Width-only sizing | 69.27 ms | 6.81 ms | 90.2% |
| Repeated setters | 354.86 ms | 22.79 ms | 93.6% |

Construction/configuration time fell 17.9–49.2% across these fixtures. Live malloc differences were below 0.05%, so this pass demonstrates CPU savings, not a meaningful reduction in retained memory. Timing and heap figures are local measurements, not universal guarantees.

## Change

TextButton previously rebuilt and measured its title and subtitle on every state application, even if nothing about the text changed. Sizing measured them again. It now retains a description of each current measured layout and reuses it while the resolved string, font, color, scale, and layout validity remain unchanged. It prepares the subtitle font and color only when a subtitle exists. No historical layouts are cached or shared between buttons; removing the subtitle clears its cache.

Dynamic colors bypass reuse. Content/style/scale changes and detectable external layout replacements, attribute changes, resizing, or invalidation use the existing measurement path. State handlers, image/background updates, accessibility, layout positioning, and subtitle animations still execute.

## Validation

`TextButtonLayoutTests` compares against `LegacyTextButton`, copied from the baseline with only its declaration/imports adapted for the test target. Coverage includes unchanged-state glyph reuse, repeated setters, sizing, title/subtitle independence, disabled and selected states, fonts, colors, glass tint, dynamic colors, backing scale, external layout changes, mutable-layout isolation, subtitle lifetime/removal/readdition, automatic sizing, empty/multiline/Unicode strings, accessibility actions, state callbacks, and subtitle animations in an AppKit window. Rendering uses 24 zero-tolerance pixel comparisons: 1×/2× scales, three image directions, with/without subtitles, and narrow/wide sizes.

```sh
swift test --package-path packages/TGUIKit
swift test --package-path packages/TGUIKit -c release
swift test --package-path packages/TGUIKit --scratch-path /tmp/telegram-textbutton-asan --sanitize=address --filter 'TextButtonLayoutTests|TextButtonBarViewTreeTests|ImageButtonTreeTests'
```

All 163 TGUIKit tests passed in both debug and release configurations. Address Sanitizer passed 36 focused tests without reported memory errors. Raw measurements and medians are in `Evidence`. Validation results include source hashes. These are control-level CPU measurements, not proof of faster Telegram chat opening, scrolling frame delivery, or GPU rendering. No full Telegram app build is required by this lab.
