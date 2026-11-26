# TGUIKit control performance lab

This standalone AppKit app builds the real TGUIKit package without the Telegram app or TelegramCore. It benchmarks controls used by chat rows, grouped-message selection, general rows, and chat-list buttons. `--preview` opens 200 sample rows; scroll them and click an icon to animate selection.

The baseline is the implementation at `ee780ff8b`. `prepare.py` copies the current TGUIKit sources into a temporary package and substitutes only `ImageButton.swift` and `SelectingControl.swift` for the baseline. Both variants use identical dependencies and benchmark code. The working checkout is never switched or overwritten. Source hashes are recorded in each temporary package's `provenance.json`.

```sh
bash tools/perflab/ControlLab/run.sh baseline > tools/perflab/ControlLab/Evidence/baseline.json
bash tools/perflab/ControlLab/run.sh candidate > tools/perflab/ControlLab/Evidence/candidate.json
python3 tools/perflab/ControlLab/compare.py
bash tools/perflab/ControlLab/run.sh candidate --preview
```

Run variants sequentially with other CPU-heavy work stopped. Each control case has seven trials, 2,000 controls per trial, and ten update passes. The row fixture mounts 200 rows in an AppKit scroll view and performs 300 scroll/layout updates. Timings include construction/configuration and CPU-side layout, not real Telegram history loading or on-screen GPU frame delivery. `mallocBytes` is the change in live malloc bytes while the controls are retained; it is approximate and includes AppKit activity, not total process memory. View counts exclude layers and detached objects, so the plain-button view count does not expose its previously allocated, detached background view.

The changes under test are:

- Allocate `ImageButton`'s additional background only when a color, corner style, or scale animation needs it. Keep its NSView when needed to preserve ordering with blur and glass views. Preserve the public `imageView` API and the interactive parent.
- Skip redundant opacity animation requests when the image is already fully opaque.
- Replace `SelectingControl`'s private image views with `SimpleLayer` instances. Preserve the parent control, accessibility, responder chain, centering, and selection animations. Refresh layer geometry when replacement icons have different dimensions.

The complete TGUIKit suite includes regression tests for lazy background allocation, state changes, late background insertion, glass/blur ordering, radius and multiplier configuration, opacity restoration, image replacement, selection interruption, object lifetime, accessibility actions, and real-window mouse forwarding. Selection rendering is compared directly against the previous implementation at 1× and 2× rasterization scales, in both states and three sizes, with zero pixel tolerance. Direct layer rendering avoids the existing general snapshot helper's duplication of semitransparent image contents.

```sh
swift test --package-path packages/TGUIKit
swift test --package-path packages/TGUIKit -c release
swift test --package-path packages/TGUIKit --scratch-path /tmp/telegram-control-asan --sanitize=address --filter 'SelectingControlTests|ImageButtonTreeTests|ControlStateApplyTests'
```

The existing merge-list tests needed an explicit protocol import because the `TGUIKit` struct shadowed its module name. The background-animation regression test now counts animation requests rather than assuming a zero-duration animation remains installed. These repairs restore the intended tests without changing production behavior.

See `Evidence/comparison.json` for medians and all raw trials in `baseline.json` and `candidate.json`. `validation.json` records test results and source hashes. The row fixture does not demonstrate a scrolling speedup; the measured gains are control construction, state updates, and allocation. No full Telegram app build or end-to-end chat-opening measurement was performed.
