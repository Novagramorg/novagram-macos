# Gift-status sparkle lab

`StarsEffectLayer` appears in premium status controls and profile gift icons. Previously every update created a new color-over-life behavior, reassigned emitter cells and geometry, and changed the random seed, even when color and size were unchanged. Particle scale was set only during initial setup, so resizing an existing effect left particles at the original scale.

The candidate retains only the current resolved CGColor and size. Unchanged updates return without changing the emitter, behavior, or seed. Color changes rebuild the color behavior; size changes update geometry and particle scale while reusing that behavior. Actual configuration changes retain the original seed-randomization behavior. Initial setup and the existing playback flag remain intact, and cleared emitter cells trigger setup again. Resolving the color on each call handles dynamic appearance changes.

## Validation

Eight functional tests pass in debug, release, and Address Sanitizer builds; one benchmark is skipped unless enabled. They use real AppKit, TGUIKit SimpleLayer, CAEmitterLayer, CAEmitterCell, the existing color-over-life behavior factory, and the app's particle PNG. Tests cover:

- Initial emitter parameters, colors, geometry and particle image bytes across five colors and four sizes.
- 1,000 unchanged updates: the original replaces the color behavior 1,000 times, while the candidate keeps its behavior and seed.
- Equivalent newly allocated NSColor objects, dynamic light/dark appearance changes, and color transitions.
- Resize behavior matching a fresh effect at the new size; a baseline assertion reproduces the old fixed-scale bug.
- Pausing before setup, repeated pause/resume, updates while paused, and restoring cleared cells without resuming playback.

The standalone `StarsRenderLab` renders actual particles offscreen using CARenderer and Metal. Twelve baseline/candidate frame pairs match byte-for-byte at three points in each sequence: steady animation, resizing, recoloring, and pause/resume. The candidate receives an unchanged update every five frames; its reference is left undisturbed. The resize reference is freshly configured at the target size, because the old resize behavior is the bug being corrected. Seeds and render times are fixed for comparison. Resized and recolored cases are configured before emission begins.

The render verifier requires nonblank particles, different images at different animation times, zero particles after a paused effect drains, and visible particles after resuming. Snapshots use a 400×160 Metal canvas. All 24 PNGs and raw image hashes are retained in `Evidence/`; one resized snapshot was also inspected visually.

`prepare.py` extracts the production class and verifies the preserved reference from `2b88f9d2a`. Only class names and the particle resource bundle are substituted. The mini-app loads an exact copy of `Resources/premium/particle.png`; provenance records its hash. Both production files parse successfully. This does not build the entire PremiumStatusUI package or Telegram app, or measure live scrolling, peak memory, or GPU utilization.

## Release measurements

Apple Silicon, Swift 6.3.3, real Core Animation objects. Median microseconds per update, nine alternating batches of 5,000 operations after warmup, with autorelease pools. Both sides include the same emitter-size read to consume their output. GPU rendering runs separately before timing.

| Scenario | Original µs | Candidate µs |
|---|---:|---:|
| Unchanged | 2.295 | 0.418 |
| Color changes | 2.304 | 1.977 |
| Size changes | 2.586 | 0.984 |
| New effect layer | 3.797 | 3.574 |
| Paused, unchanged | 2.276 | 0.415 |

Unchanged updates are about 5.5× faster and size changes about 2.6× faster. Color changes and new layers also improve modestly in this run. These are isolated update costs, not application frame-rate gains. Avoided behavior replacement is measured independently of timing; resident memory is not measured. Each effect retains only its current color and size, without a history or global cache.

## Reproduce

```sh
python3 tools/perflab/StarsEffectLab/prepare.py
swift test --package-path tools/perflab/StarsEffectLab --scratch-path /tmp/StarsEffectLab-debug
swift test -c release --package-path tools/perflab/StarsEffectLab --scratch-path /tmp/StarsEffectLab-release
swift test --sanitize address --package-path tools/perflab/StarsEffectLab --scratch-path /tmp/StarsEffectLab-asan
/tmp/StarsEffectLab-release/release/StarsRenderLab /tmp/stars-effect-renders
python3 tools/perflab/StarsEffectLab/verify_renders.py /tmp/stars-effect-renders
STARS_EFFECT_BENCHMARK=1 swift test -c release --skip-build --package-path tools/perflab/StarsEffectLab --scratch-path /tmp/StarsEffectLab-release --filter testEffectBenchmark
```

Run the benchmark after builds and the Metal render check finish. Its output is `/tmp/stars-effect-benchmark.json`. Generation creates ignored source and resource files needed by the package.
