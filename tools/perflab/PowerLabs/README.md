# Power labs

Standalone measurements for `docs/perflab/power-audit.md`. None of them need an account or the app.

| Lab | Run | Measures |
|---|---|---|
| `Emitter/offscreen.swift` | `swiftc -O offscreen.swift -o /tmp/emitter && /tmp/emitter` | CARenderer render time and frames that need a render, 24 sparkle emitters playing vs `birthRate = 0`. Works with the screen locked |
| `Emitter/onscreen.swift` | `swiftc -O onscreen.swift -o /tmp/emitter-onscreen && /tmp/emitter-onscreen` | WindowServer CPU and GPU with the same emitters in a real window. Only meaningful while nobody uses the Mac |
| `Audio/idle-output.swift` | `swiftc -O idle-output.swift -o /tmp/audiolab && /tmp/audiolab` | coreaudiod CPU and power assertions with a HAL output unit running silence (a paused player) vs stopped |
| `Emitter/keyframes.swift` | `swiftc -O keyframes.swift -o /tmp/keyframes && /tmp/keyframes` | CARenderer frames needing a render with 8 typing-style infinite path keyframe animations, playing vs frozen |
