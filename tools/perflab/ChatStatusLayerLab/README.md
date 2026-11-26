# Chat status layer lab

This harness compiles the actual `ChatRightTextLayer` extracted from `ChatRightView.swift` against real TGUIKit/AppKit. `Reference.swift` preserves its implementation at `c4a15e92f`. No drawing or geometry behavior is stubbed; the harness only provides the named app icons required by TGUIKit initialization.

Run from the repository root:

```sh
python3 tools/perflab/ChatStatusLayerLab/prepare.py
swift test --package-path tools/perflab/ChatStatusLayerLab --scratch-path /tmp/ChatStatusLayerLab-build
STATUS_LAYER_BENCHMARK=1 swift test -c release --package-path tools/perflab/ChatStatusLayerLab --scratch-path /tmp/ChatStatusLayerLab-release
swift test --sanitize address --package-path tools/perflab/ChatStatusLayerLab --scratch-path /tmp/ChatStatusLayerLab-asan
```

The former implementation assigned the unpadded frame, then expanded the bounds for glyph padding on every update. Even an unchanged layout therefore shrank and expanded the child bounds. The new implementation assigns the final padded bounds and centered position only when they differ. Padding, rendering, redraw invalidation, and the parent layer's animation behavior are unchanged.

Four regression tests cover:

- 1,000 unchanged layout calls: 2,000 actual bounds changes in the reference, zero in production, observed using KVO.
- Exact bounds, frame, and position equality through 500 fractional resize/move cases, including zero sizes and nonzero bounds origins.
- Byte-for-byte rendered-pixel equality for timestamps, edited labels, counts, Arabic, emoji, and empty strings at 1x, 2x, and 3x scale. Nonempty text must produce nontransparent pixels.
- A mutable layout changing its text and color: an explicit update still invalidates drawing, changes pixels, and matches the reference.

The opt-in fifth test measures 100 real layers over 1,000 unchanged layout passes per batch, alternating reference/candidate order across nine batches and reporting medians. It writes `/tmp/chat-status-layer-benchmark.json`. This measures status-layer geometry updates only, not a complete chat frame or app FPS. The full application was not built. The saved `results.json` records the source hash and validation scope.
