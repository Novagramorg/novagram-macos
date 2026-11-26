# Counter update lifecycle

This native harness links the actual TGUIKit package and compares counter behavior with a renamed source snapshot from `8f8c448ca`. Generate the reference with `python3 tools/perflab/CounterUpdateLab/prepare.py`.

## Reproduced problems

The initial seven tests produced 27 assertion failures against unchanged production code:

- Repeating the same text with a different available width left old truncation and view sizes installed.
- Changing kerned spacing could leave old positions installed.
- Updating a number while resizing could retain an incorrectly measured prefix view.
- Switching between regular and rolling modes retained both sets of views; clearing afterwards could leave the inactive set visible.
- Remeasuring an existing value did not refresh regular counter geometry.

The refactor updates changed geometry while keeping unchanged regular segments free of redraw requests. Switching modes removes active and outgoing text views and clears their animations. Existing numeric direction, fade, rolling, and overflow behavior is checked against the frozen original.

## Storage and work

Regular segments use integer indices instead of full text keys and duplicated text values. The counter stores text metadata rather than a second array retaining every prepared layout, allowing unused layouts for reused segments to be released. Number parsing is performed only for changed, animated regular values. Animation constants are shared rather than stored on every counter. Rolling positions are calculated as views are processed rather than collected in a temporary array. Regular segments are matched with one forward pass through their factory-assigned, ordered indices. Unchanged rolling text skips removal checks; style-only changes use set membership, preserving linear cleanup work.

Runtime instance payload is 952 -> 944 bytes; both objects still occupy a 1,024-byte malloc block on this machine. Regular dictionary key/value payload is 24+32 -> 8+8 bytes per slot. These are object/element sizes, not total process or dictionary heap measurements.

## Validation

The tests exercise width changes, kerned spacing, reused prefixes, remeasurement, both animation modes, clearing, outgoing animation cleanup, weak-reference release, font/color/fade changes, preserved view identity, unchanged redraw state, and additive position animations for geometry updates. Animation parameters and model-layer rendering are compared for increments, decrements, digit-count changes, and integer overflow, in normal/reversed and fade/rolling modes. The final suite has 18 functional tests and three opt-in benchmarks. It includes 70 nonblank exact pixel comparisons and 40 animation-parameter comparisons. The separate CounterLayoutLab checks real font metrics and another 96 exact pixel comparisons.

The first implementation fixed the bugs but unnecessarily rebound every existing text view. Its benchmark showed an equal-value regression; its source, log, and timings are preserved under results/initial-*. The final path retains the old drawing layout when text and geometry agree, and refreshes it when the requested geometry differs.

Run paired benchmarks with:

```sh
COUNTER_UPDATE_BENCHMARK=1 swift test --package-path tools/perflab/CounterUpdateLab --scratch-path /tmp/CounterUpdateLab-release -c release
```

Benchmarks alternate original/candidate order over nine batches of 1,000 updates; the long changing-counter stress cases use batches of 50 updates to bound temporary allocations. Values are prepared outside the timed region. Functional and sanitizer runs omit the environment variable. Raw batches, regression logs, source hashes, and broader TGUIKit/chat results are retained in results/ and provenance.json.

This does not measure end-to-end chat scrolling or total app memory, and no full Telegram build was performed.

## Long-label regression caught during development

An intermediate candidate replaced a set with repeated linear searches during rolling cleanup. At 128 segments it took 327.622 microseconds per unchanged update versus 76.173 for the original, despite improving the short timer case. The final implementation skips cleanup for unchanged content and uses a set for style changes. The intermediate source, raw measurements, and validation logs are retained under results/pre-long-* and results/long-before.*.

## Final release measurements

Times are median microseconds per update. Values are already prepared; these measurements isolate control update work.

| Case | Original | Candidate | Reduction |
|---|---:|---:|---:|
| Timer: regular changed | 14.856 | 13.572 | 8.6% |
| Timer: regular equal | 0.683 | 0.609 | 10.8% |
| Timer: rolling changed | 63.861 | 63.178 | 1.1% |
| Timer: rolling equal | 3.262 | 2.626 | 19.5% |
| Long unchanged: regular 32 | 4.581 | 3.661 | 20.1% |
| Long unchanged: regular 128 | 22.318 | 15.325 | 31.3% |
| Long unchanged: rolling 32 | 18.461 | 15.574 | 15.6% |
| Long unchanged: rolling 128 | 74.709 | 63.575 | 14.9% |
| Long regular changed: 32 | 407.348 | 381.148 | 6.4% |
| Long regular changed: 128 | 1833.666 | 1583.395 | 13.6% |

The approximately 1% change for a changing rolling timer is too small to treat as a meaningful improvement. No app-wide speedup or total memory percentage is inferred from these component results.
