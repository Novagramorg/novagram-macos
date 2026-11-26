# LiteHTML drawing optimization log

Goal: scripted HTML bubbles at 60 fps under heavy load, less CPU than WebKit, and every frame pixel-exact.

## How it's measured

`tools/perflab/LiteHTMLLab` (SwiftPM, depends only on `packages/LiteHTML`):

- `record`: runs every scripted message in `packages/HTMLBubbles/.../Resources/chats` for 4 s and saves each frame's HTML (`traces/`, about 70 traces and 4.3k frames).
- `bench --verify`: replays the traces through the app's render path (wrap, `LHDocument`, layout with width hint, display-list diff, tile raster) on one thread. It reports thread CPU per stage and checks every frame.
- `compare A B`: per-trace speedup and whether frame hashes match.
- `clipcheck`: redraws random sub-rectangles of tiles and checks they equal a full tile render.

**Correctness reference:** a fresh, non-incremental render of the same frame on the same tile grid. The verification counts frames whose incremental result differs from it by even one bit.

## Results (lab, Apple Silicon, scale 2, width 400)

| Step | CPU per frame | Frames ≠ fresh render | Commit |
|---|---|---|---|
| Baseline (beta 847d50790) | 1.54 ms | 1009 / 4299 | |
| `wrap()` byte scan instead of case-insensitive `range(of:)` (was 25% of CPU) | 1.15 ms | 1009 | 66d804e20 |
| Cache parsed message `<style>` (was 22% of document creation) | 1.01 ms | 1009 | 049fb85f1 |
| Gradients and images from cached device-size bitmaps | 1.01 ms | 217 | e68c13bb9 |
| Redraw changed tiles whole, 64 pt bands | **1.00 ms** | **0** | 8fa1ae87a |

Total so far: **1.53× less CPU**, and every frame equals a fresh render. Static first frames versus the old code: 53/70 byte-identical, the rest within 2/255 (gradient dither).

## Iteration 2: real-world cost and WebKit

The single-thread numbers above leave out putting tiles on screen. `LiteHTMLLab present` shows frames at 60 fps in a real window with layers and counts all process CPU. `WebKitLab` feeds the same recorded frames to a WKWebView at 60 fps and adds up our process plus WebKit's WebContent and GPU processes. Traces were re-recorded after merging sam/new-wallet (4323 frames).

| | CPU per frame at 60 fps |
|---|---|
| WebKit, `innerHTML` per frame | 5.48 ms (app 0.99 + WebContent 3.14 + GPU 1.35) |
| WebKit, DOM morph per frame | 6.64 ms |
| LiteHTML, start of iteration 2 | 4.08 ms |
| + tiles drawn in the window's color space (59acb4a6d) | 3.35 ms |
| + script frames patch the previous document (7dc4281ea, ca855b3f5) | **2.99 ms** |

**Now 1.83× less CPU than WebKit on the same frames**, and every frame is still bit-identical to a fresh build.

- **Color space:** sRGB tiles were color-converted by Core Animation on every commit (vImage/ColorSync was the top cost, 1.55 ms per frame). Drawing in the window's space removes it (commit 0.12 ms).
- **In-place documents:** 84% of script frames change only inline `style` values and/or text (54% style only, 23% style + text, 6% text only, 3% structure). These are now patched instead of reparsed (3624/4323 frames). Inside the patch: gumbo reparse 39%, restyle 31%, render tree about 12%.
- **Paced cost is about 3× the tight-loop cost** (render 1.0 → 2.8 ms): short bursts at 60 Hz run at low clocks. WebKit is measured the same way.
- **Tried and dropped:**
  - 2D tile grids: less area, but no faster, because raster is CoreGraphics fill-bound and large shapes are re-rasterized per tile.
  - A recycled tile-buffer pool: kernel and render time went down, but Core Animation then copies the buffers at commit, so no net change. Zero-copy needs IOSurface tiles.

## Iteration 3

Merged sam/new-wallet again (189596b1e; conflict in HTMLBubbleView's pin call, kept both the new `opensOrCloses` condition and the stored pin bounds).

| | CPU per frame at 60 fps (3 runs each) |
|---|---|
| WebKit | 5.31 / 5.73 / 5.71 ms, mean **5.58** |
| LiteHTML after template matching (cd5e0e2ce) | 2.79 / 2.89 / 2.93 ms, mean **2.87** |

**1.94× less CPU than WebKit** (1.81–2.05× across runs), with every frame bit-identical to a fresh build.

- **Template matching (cd5e0e2ce):** a patched frame no longer reparses with gumbo. The previous frame is kept as literal text with holes at its style values and text nodes, and a new frame is matched against it. Document creation 0.26 → 0.20 ms (tight loop).
- **Tried and dropped:**
  - Restyling only the element when its changed properties can't reach descendants. The fast path applied 26,655 times, but those subtrees held only ~6,600 descendants in total (animated elements are mostly leaves), so no measurable gain.
  - Cached text-run bitmaps. litehtml draws text word by word, and the per-word key, lookup and image copy cost more than drawing the word (raster 0.49 → 0.51 ms).
- **Exact cache keys (15b3b8cb3):** gradient and image cache keys use exact floats.
- **Ceiling for drawing work:** with raster switched off, the paced cost would be 1.36 ms per frame. Raster is now about half of what's left, and it's CoreGraphics pixel work (fills 33%, text 26%, gradients 18%, borders 9%).

The next real step for raster is compositing changed elements as Core Animation layers so the window server draws them. That can't be bit-identical to CoreGraphics; it would be verified to a tolerance instead, and only as an opt-in engine.

## Iteration 4

| | CPU per frame at 60 fps (3 runs each) |
|---|---|
| LiteHTML after shaped-line reuse (5734c2a55) | 2.52 / 2.91 / 2.87 ms, mean **2.77** |

- **Shaped-line reuse (5734c2a55):** each drawn word built a new `CTLine` (17% of raster). Lines are now cached per font, text and color. Raster 0.487 → 0.420 ms (tight loop), every frame hash equal to the previous code.
- **Composited layers (the opt-in engine) were measured before building and dropped.** Positioned elements and paint groups were tagged as units, with a content key taken relative to the unit's origin and excluding its own transform and opacity. Per frame across all traces:
  - Changed area in units whose content changed: 19,778 pt².
  - Units that only moved, rotated or faded: 289 pt².
  - Changed static content: 25,854 pt².

  The demo scripts change what's inside elements (clock hands, bar widths, colors, text) rather than moving them, so Core Animation compositing would cut raster area by at most 1.16×, roughly 7% of the paced cost.
- **Tried and dropped:**
  - IOSurface tiles drawn in place and shown directly: pixel-identical and kernel time halves (0.45 → 0.23 ms), but Core Animation's commit triples (0.13 → 0.40 ms). Paced mean 2.92 ms against 2.77 ms for image tiles.
  - Partial tile redraws. CoreGraphics output depends on the clip only for rounded fills and borders, gradients and images (`clipcheck` per op kind; text, paths and shadows are clip-independent). Growing the dirty rect until it contains every rounded corner, gradient and image it touches makes partial redraws exact (0/4323), but raster only drops about 5% (0.44 → 0.42 ms), because the pixel copy and region growth eat most of the smaller area.
  - Data-URI images are decoded once each. Scripts generate a new SVG for most frames, so the decode is real work, not a cache miss.

## Iteration 5: twidget's architecture for litehtml messages

Message scripts now run in the same three stages as twidget, with litehtml as the renderer: a sandboxed script, then a validator, then the renderer. JavaScriptCore stays the script engine (QuickJS was measured and was as fast, but we kept the native engine).

- **Validator (6900bc279):** twidget's rules as native code inside litehtml's own parse (element, declaration and at-rule hooks plus structure limits), so no extra pass. It reports nothing on any of the 4,438 demo documents. Pixels are identical to the build before it, and CPU is within noise (interleaved runs: 0.77 against 0.78 ms per frame). Every case in a hostile test document is caught. Deviations from twidget, on purpose: `sf:` and `app:` images, and `https`/`http`/`chat`/`tg`/`mailto` links, which go to the app's link handler.
- **Script engine (72e3d617b):** the new `packages/HTMLScript` replaces `LHScript`.
  - One shared JavaScriptCore virtual machine on a dedicated thread.
  - One shared 60 fps frame clock; all timers share one wake-up, and changes reach the main thread in one hop per batch.
  - twidget's `CpuBudget` quota: heavy scripts are slowed down instead of stopped.
  - The 50 ms per-call stop stays, and a call that grows memory by 128 MB stops the script.

`LiteHTMLLab live` runs all 70 demo scripts at once (no drawing), six alternating 20-second runs, medians:

| Per second | Old engine (main thread) | New engine |
|---|---|---|
| CPU | 55.0 ms | 48.5 ms |
| Main-thread time | 32.8 ms | 1.8 ms |
| Wakeups | 258 | 228 |
| Renders | 186 | 190 |

- **Dropped on the way:**
  - A serial GCD queue: JavaScriptCore re-enters on different worker threads.
  - A GCD timer per script timer: costs more energy.
  - Reading the process footprint around every call: about 10% of CPU. The guard now reads it only after a call longer than 2 ms, since allocating 128 MB takes longer than that.
  - Swift `String` operations on JavaScriptCore strings: slow; NSString is used until the HTML is published.

## Iteration 6: 120 Hz and a GPU renderer

- **120 Hz (2bfde0a78):** the script clock is a CVDisplayLink on the bubble's screen, so `requestAnimationFrame` runs at 120 fps on ProMotion (300 frames in 2.5 s). The render interval follows the display. At 120 fps the exact engine's p99 frame time is 6.4 ms, inside the 8.3 ms budget.
- **GPU renderer (branch `litehtml-gpu`, be701148c, not on beta):** a Metal hybrid.
  - Drawn natively on the GPU: solid fills (analytic coverage), text (glyph atlas, glyphs rasterized by CoreGraphics at their exact sub-pixel phase), and rounded fills (corner coverage masks plus pixel-aligned slabs).
  - Every other op is captured once by CoreGraphics into zero-copy atlas pages and composited.
  - Fidelity against the exact engine on all traces: interior pixels within 1 level, 0.000% of pixels off by more than 8, no structural differences.
  - Tight loop: 0.55 ms against 0.71–0.81 ms per frame.
  - On screen at 120 fps (4 alternating runs, medians): **1.97 against 2.16 ms per frame (−9%)**. That misses the 1.6 ms gate set beforehand, so it isn't shipped.
  - Why it falls short: at 120 Hz most of the per-frame CPU is restyle, layout and the draw traversal; Metal submission adds about 0.1 ms of kernel time per frame.
  - Trap: IOSurface tiles tagged with the display's ICC profile make Core Animation rebuild a ColorSync profile on every commit (commit 0.1 → 0.35 ms). A named color space such as Display P3 is a small number tag and costs nothing.

## Iteration 7: restyle and layout

Every change below is exact. All 4,374 frames are byte-identical to the code before this session (aae0cf859); this time the bench records frame hashes on both sides of the comparison.

- **Image sources patched in place (cc551ad37):** an `<img src>` change used to force a full parse. Charts regenerate an SVG data URI each frame, 11% of frames. Patched frames went from 3,608 to 4,100 of 4,374. Each new source still goes through the sanitizer's image policy. `el_image` loads each source once instead of on every restyle.
- **Inline style declaration cache (10ebee239):** style strings are split at top-level `;`, and each declaration replays the exact add/remove property operations recorded on first parse. Document creation 0.170 → 0.138 ms.
- **Keep the render tree (62651f436):** when a patch changes no text and only geometry or paint declarations (whitelist; font properties excluded), the render tree is reused. 49% of patched frames keep it. Document creation 0.118 → 0.106 ms.
- **Overall:** about 1.3× less CPU than the code before this session in the tight loop. The GPU engine's recording dropped to 0.47 ms per frame.
- **On screen at 120 fps** (4 alternating runs, medians): CPU engine 2.22 ms, GPU engine 1.97 ms (−11%). The GPU engine spends 0.5–0.6 ms in the kernel per frame (Metal submission and wait), which eats most of its main-thread savings.
- **Tried and dropped:** memoizing each text op's glyph list. It was exact, but copying the cached ops cost as much as recomputing them.
- **What's left:** restyle and layout are now about 0.15 ms of a 0.69 ms frame (CPU engine). For the GPU engine the next costs are Metal submission overhead (batch all bubbles into one command buffer per display frame, never wait on the render thread) and gradient or image ops recaptured into bitmaps instead of being drawn from their cached textures.

## Iteration 8: GPU submission

- **Measurement fix:** separate runs of each engine drifted by up to 40% with machine state, so 10% differences were unreadable. `present --modes cpu,gpu,async` now plays each trace with every engine back to back in one process. Run it in both orders and average.
- **Result** (120 fps on screen, averaged over both orders):

  | Engine | CPU per frame | Kernel |
  |---|---|---|
  | CPU (exact) | 2.03 ms | ~0.38 ms |
  | GPU, commit and wait | 1.78 ms (−12.5%) | ~0.50 ms |
  | GPU, async completion | 1.85 ms (−9%) | ~0.51 ms |

  A repeat without IOSurface in-use checks gave GPU −8 to −13% again, with the same kernel time.
- **Async completion doesn't help.** Kernel time is identical, so waiting wasn't the cost. The extra ~0.12 ms of kernel time per frame is Metal's own command buffer submission, not something in our code.
- **Conclusion:** the GPU engine is a steady ~12% CPU win at 120 fps. That's real but not a 2× breakthrough. More would need drawing gradients and images from their cached bitmaps without capture copies (about 15% of recording, so ~4% overall) or moving work off the per-frame path entirely.

## Findings

- **The shipped incremental path wasn't exact.** CoreGraphics output depends on the clip (gradient dither, image resampling) and on the bitmap geometry (anti-aliased curves such as rounded borders come out ±1–5 levels depending on where the bitmap starts). Partial redraws therefore left stale or slightly-off pixels in 23% of animated frames. Whole-tile redraws are exact by construction and cost the same.
- **Stage costs now** (tight loop, ms per frame): document creation 0.20 (patched frames, mostly restyle + render tree), raster 0.49, layout 0.04, display list 0.03, diff 0.02.
- `css_properties` sharing and the master stylesheet cache were already in (see earlier sessions).

## Next

0. **Per-frame CPU at 120 Hz** is now mostly restyle, layout and the draw traversal, not pixels. That's where the next big step is (incremental render tree, skipping restyle for transform-only changes).
0. **Hidden scripted bubbles** still wake the script thread for repeating timers; twidget slows hidden widgets to 1 Hz. That's the next energy step for scripts.
1. **Restyle** is now the largest exact target: document creation for patched frames is mostly `compute_styles` and inline `style` parsing.
2. **GPU raster** is the only route left to a large raster cut, and it can't be bit-identical to CoreGraphics. Raster is CoreGraphics pixel work (solid fills, glyph masks, image blits).
