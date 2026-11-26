# Async text lab

Can chat text be rasterized off the main thread and still be byte-identical to today's `TextViewLayer` drawing? Standalone package on the real TGUIKit; every comparison is a WindowServer capture (`CGWindowListCreateImage`) of a real on-screen window, native `TextViewLayer` (CA backing store, drawn on main) against the candidate, byte for byte. Window color spaces: default (this Mac's "Color LCD", wide gamut), sRGB, Display P3.

```sh
cd tools/perflab/AsyncTextLab
swift test
ASYNC_TEXT_EXPLORE=1 swift test --filter "testManualRasterFormats|testContextSettingsSweep|testProbeBackingContext"
ASYNC_TEXT_BENCH=1 swift test -c release --filter testMainThreadCommitCost
```

The default run (about 4 minutes, needs an unlocked screen) asserts the findings below: native drawing is stable, `drawsAsynchronously` is not identical, the own raster stays within the measured gap (≤ 2/255 sRGB, ≤ 3/255 wide) and its wrong format is caught, fills are exact, detached CA display is exact in an sRGB window and not in a wide one, a 0.5 pt shift is detected. A future macOS that closes a gap shows up as a failing "became exact" assertion.

## Findings (2026-10-19, Apple Silicon, macOS 26.4)

| Candidate | sRGB window | Wide-gamut window (the app's default) |
| --- | --- | --- |
| `CALayer.drawsAsynchronously = true` | up to 54/255 off, first frames never final | up to 55/255 off |
| Own CG bitmap on a background queue, window color space, 8-bit BGRA (sRGB) / 16-bit RGBA (wide), layer's own flip | exact for colors with 0/1 components and for some mixed fixtures; text in colors that are exact multiples of 1/255 (all theme colors) off by ≤ 1–2/255 | exact for the mixed fixture with 3+ paragraphs; single-color text off by ≤ 2–8/255 |
| CA's own display of a detached `TextViewLayer` on a background queue (`contentsFormat = "AutomaticAppKit"`), backing store handed to the on-screen layer | **exact for every color and size tried** | up to 22/255 off: a detached layer's backing store is created in device RGB, not the window's color space, and there is no public API to choose it |
| Same, layer attached to a `CARenderer` with the window color space | empty contents (renderer-context backing stores do not transfer) | empty |

Other facts established here:
- CA calls `draw(in:)` with a display-list recording context (`colorSpace == nil`, `width == 0`); the backing store is filled when the list is replayed. On a wide-gamut window the AppKit automatic format is 16-bit integer RGBA in the window's color space (8-bit BGRA in an sRGB window); `window.canRepresent(.p3)` predicts which.
- Plain fills (solid, antialiased fractional edges, 50 % alpha) are byte-exact through the own-bitmap path in both windows; the residual is specific to glyph compositing with mid-range colors. Subpixel quantization, rendering intent, interpolation and flatness do not change it.
- A CGImage contents layer needs the image anchored like a backing store; with an integral layout size gravity does not matter.
- Main-thread commit time for 8 text layers, Release: native 1.1 / 4.2 / 7.9 ms (1 / 4 / 12 paragraphs each) vs 0.13–0.23 ms with prerendered contents. Total CPU of the 16-bit raster is about 2× the native draw (it runs off main); 8-bit about equal.

## Status

Not byte-exact on the app's default (wide-gamut) window with theme colors, so not shipped. The in-app Time Profiler capture of a 16,000 pt/s fling puts text glyph rasterization at about 2 % of the main thread and none of the hitching frames (history merges, see `docs/perflab/chat-optimization-log.md`), which bounds what moving it off main can buy on this machine.
