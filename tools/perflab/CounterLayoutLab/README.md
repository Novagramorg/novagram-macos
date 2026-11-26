# Counter digit measurement

The native test harness links the real TGUIKit package and compares DynamicCounterTextView with its frozen source from commit `3d21a5571`. Run `python3 tools/perflab/CounterLayoutLab/prepare.py` before building the lab. The generated reference only adds the TGUIKit import and renames the class.

## Change

Each counter value previously constructed and measured ten temporary TextViewLayout objects solely to find the widest digit. The implementation now uses CoreText directly with the same rounded typographic width calculation. A locked cache stores at most 16 font identities and scalar widths. It retains no layouts or CoreText lines, and adds no per-view fields. Measurement happens outside the lock, with duplicate insertion checked under the lock. Fonts whose digit runs select a fallback font are measured afresh, so font fallback is not frozen in the cache.

The change applies to all existing callers, including media timers, chat headers, recording timers, story counts, and group call controls. Segmentation, visible text measurement, placement, and animation code are unchanged.

## Validation

The suite contains nine functional tests and one opt-in benchmark:

- Exact digit widths against TextViewLayout for every installed font at four integral/fractional sizes, on first and subsequent lookup.
- Font feature settings, affine transforms, and the actual app font factories, including rounded and monospaced digits.
- Full counter geometry, offsets, text, and numeric classification across up to five fonts, eight text/count fixtures, three widths, and fade/kerned variants.
- 96 nonblank, byte-identical renders against the original control at 1x and 2x, across sequential value updates and regular/rolling modes.
- Bounded eviction, identity hits, fallback exclusion, and 2,400 concurrent accesses.
- Counter view instance size does not grow.

The initial expanded validation caught two harness issues: rendering the container layer produced blank output, and the five default fixture fonts did not exercise fallback. The renderer now calls the actual TextView drawing layer, with a nonblank assertion; the fallback test scans installed fonts and requires at least one fallback case. The initial log is retained.

Run the release benchmark with:

```sh
COUNTER_BENCHMARK=1 swift test --package-path tools/perflab/CounterLayoutLab --scratch-path /tmp/CounterLayoutLab-release -c release
```

Sanitizer runs omit COUNTER_BENCHMARK and use separate scratch directories. Broader TGUIKit and chat-layer test results are recorded in provenance.json. No full Telegram build or end-to-end chat latency measurement is claimed.

## Measurements

Paired release batches alternate original/candidate order, nine batches of 1,000 operations. Times below are median microseconds per operation (numerically equal to milliseconds per 1,000).

| Operation | Original | Candidate | Reduction |
|---|---:|---:|---:|
| Participant counter value | 47.552 | 14.060 | 70.4% |
| Kerned timer value | 60.618 | 26.975 | 55.5% |
| Plain text value | 39.409 | 6.277 | 84.1% |
| Cold digit width, fresh cache each time | 31.555 | 14.573 | 53.8% |

Raw batches are in results/benchmark.json. These measure component CPU work, not overall app speed or retained process memory. A cache hit removes ten temporary layout constructions and digit shaping passes; a miss still avoids the ten full layouts.
