# Gift controls and wallet preload lab

Run `python3 tools/perflab/GiftControlsLab/prepare.py`, then `swift test --package-path tools/perflab/GiftControlsLab --scratch-path /tmp/GiftControlsLab-build`.

The harness extracts the current production gift ActionView and QR glass button. They run against real TGUIKit and AppKit, including native glass when available. InteractiveTextView is also extracted from production; its inline emoji renderer and account-dependent item are fixtures; the QR reveal mask is a fixture. Tests cover backing view order, unclipped wrappers, reuse, tint changes, resizing, fallback, and click handler replacement. QR tests exercise appearance changes and wrapper reuse; the coordinated reveal animation is outside this harness.

Wallet tests extract the production preload entrypoint and cache/load methods. Real SwiftSignalKit drives them; account/network/model-rendering boundaries are fixtures. They check the ten-sticker cap, duplicate and invalid entries, build gating, embedded gifts, warm and in-flight cache reuse, and retry after failed metadata lookup. They do not measure real network latency or sticker decoding.

Use `-c release` to verify optimized controls and release preload gating. Use `--sanitize address` for the AppKit/control lifetime checks. Use a separate scratch directory for each configuration.
