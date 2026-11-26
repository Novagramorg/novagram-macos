# Stars widget particles, colors, and layout

Three correctness issues were present in `StarsWidgets.swift`:

- `BadgeStarsViewEffect.whiteParticle` initialized itself from itself. On the tested Swift runtime, initialization returned normally but both emitter cells had nil textures, so the slider particles were invisible. The corrected slider shares the button's actual precomposed particle image.
- `Star_SliderView.updateColors` and `Star_BadgeView.updateColors` ignored their gradient argument and always installed the default gold gradient. They now apply the requested colors.
- Both effects read their particle color only during initial setup. Later color assignments now refresh the color-over-life behavior while preserving emitter motion and playback settings.

The effects also remember their last size or size/position pair, avoiding repeated geometry writes and attractor-position KVC work when layout is unchanged. Fixed component colors update through the property setter; catalog/dynamic colors are checked again during layout so appearance changes remain visible. Resizing and movement still update geometry. Clearing emitter cells triggers complete setup. Initial setup assigns fully configured cells once.

## Validation

Nine functional tests pass in debug, release, and Address Sanitizer builds; the tenth test is an opt-in benchmark. They cover:

- The original missing-texture bug, nonblank production particle data, and shared image identity.
- Initial emitter configurations across four colors and four sizes, including Display P3 and transparency.
- Unchanged geometry/color identity, seeds and timeline, resize/movement, attractor position, and rebuilding cleared emitters.
- Gradient arguments, color changes after setup, paused playback, and preserved motion parameters after recoloring.
- Dynamic appearance changes during layout.

The separate bounded initializer probes both return successfully: the original has zero textured cells, the candidate has two. Results are recorded in `initialization-proof.json`. The first exploratory probe assumed the self-reference would trap or hang; inspecting emitter contents established the actual missing-texture failure.

The Metal/CARenderer harness produces 24 exact, nonblank frame pairs across steady playback, resizing, recoloring, pause/resume, and directional motion. Seeds and render time are fixed. Candidate geometry updates repeat every five frames. The 48 PNGs and hashes are in `renders/`; a motion frame was also visually inspected. Recoloring is configured before emission in these raster scenarios; mid-playback color changes are covered by configuration/playback tests rather than a claim of pixel-identical color-transition timing.

`prepare.py` extracts the entire production effect classes and both actual `updateColors` methods. The untouched original source is checked against `89aab78a1`. For configuration, timing, and GPU comparisons, the reference repairs only the self-referential particle initializer; otherwise the baseline would render no slider particles. The untouched broken class remains available for the regression probe and test.

The lab uses real TGUIKit layers/views, Core Animation emitters/behaviors, and the production 1×/2× star asset. A small hook fixture loads those assets with their 22-point logical size. Gradient methods run in minimal containers with the real effect instances. It does not build the full auction/reaction controllers, accounts, inline sticker playback, or main application. Production source passes Swift frontend parsing.

## Reproduce

From the repository root:

```sh
python3 tools/perflab/StarsWidgetLab/prepare.py
swift test --package-path tools/perflab/StarsWidgetLab --scratch-path /tmp/StarsWidgetLab-debug
swift test --package-path tools/perflab/StarsWidgetLab --scratch-path /tmp/StarsWidgetLab-release -c release
swift test --package-path tools/perflab/StarsWidgetLab --scratch-path /tmp/StarsWidgetLab-asan --sanitize address
swift run --package-path tools/perflab/StarsWidgetLab --scratch-path /tmp/StarsWidgetLab-debug --skip-build StarsWidgetProbe broken
swift run --package-path tools/perflab/StarsWidgetLab --scratch-path /tmp/StarsWidgetLab-debug --skip-build StarsWidgetProbe fixed
swift run --package-path tools/perflab/StarsWidgetLab --scratch-path /tmp/StarsWidgetLab-release -c release --skip-build StarsWidgetRender tools/perflab/StarsWidgetLab/renders
STARS_WIDGET_BENCHMARK=1 swift test --package-path tools/perflab/StarsWidgetLab --scratch-path /tmp/StarsWidgetLab-release -c release --skip-build --filter EffectsTests.testBenchmark
swiftc -frontend -parse packages/StarsUI/Sources/StarsUI/StarsWidgets.swift
```

## Performance evidence

Release measurements on Apple Silicon with Swift 6.3.3, using the default fixed gold color. Medians of five alternating-order passes of 10,000 updates. New-effect cases create new objects in an already-running process with cached assets. Builds, functional suites, and GPU captures finish before timing. The reference includes only the texture repair described above.

| Scenario | Reference µs | Candidate µs |
|---|---:|---:|
| Button, unchanged size | 0.083 | 0.040 |
| Slider particles, unchanged layout | 0.711 | 0.059 |
| Slider particles, moving | 0.915 | 0.944 |
| Slider particles, resizing | 0.975 | 0.975 |
| New button effect | 3.275 | 3.053 |
| New slider effect | 17.518 | 17.369 |

These are isolated emitter-update timings with no account/controller work or window-server rendering. They do not claim an app-wide FPS or GPU-utilization improvement. Dynamic/catalog colors require resolution during layout for correctness; explicit color changes rebuild their color behavior. Default fixed-color layouts avoid that repeated resolution. Raw timing samples and final suite logs are included.
