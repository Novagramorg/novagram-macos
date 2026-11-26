# Main app performance lab

This standalone Swift executable and XCTest suite exercise Telegram's production date grouping, spoiler formatting, image cache, and hashtag album selection without building Telegram or using an account. Production files are relative symlinks, so tests run the implementation shipped by the app. The only package dependency is the repository's `Strings` package, used by the frozen spoiler baseline. No telegram-ios source or dependency is built or changed.

## Running

Run from the repository root on macOS with Xcode's command-line tools:

```sh
tools/perflab/MainAppLab/run.sh test
tools/perflab/MainAppLab/run.sh release-test
tools/perflab/MainAppLab/run.sh tsan
tools/perflab/MainAppLab/run.sh asan
tools/perflab/MainAppLab/run.sh bench > /tmp/mainapp-benchmarks.json
tools/perflab/MainAppLab/run.sh bench --invalid-spoiler
```

The runner puts build products and compiler caches under the temporary directory. Set `MAIN_APP_LAB_WORK` to choose another directory. `bench` builds the release executable; its JSON goes to stdout and build messages go to stderr. `--invalid-spoiler` runs the fixed malformed-range reproduction. The AppKit scope test creates an undisplayed window and actual scroll view, then checks image release and timer shutdown when the scroll view dies.

## Changes and correctness

- **Date grouping:** bounded caches retain at most 16 day intervals and 16 month intervals. Calendar and timezone notifications invalidate both under the same lock as lookups. Actual day intervals fix midnight DST transitions that previously included the following day's first hour. Month caching is limited to Gregorian and ISO calendars. Other calendars retain the old calculation because interval boundaries and the old year/month reconstruction are not interchangeable for all calendars. Existing last-day-of-month IDs are preserved.
- **Spoilers:** a shared immutable mapping replaces a per-call character table. One UTF-16 buffer replaces repeated string concatenation. Returning an NSString-backed string avoids unnecessary UTF-8 conversion in this UTF-16 operation. Valid ranges keep identical output; an overlong range masks the available suffix, while negative, missing, empty, and entirely out-of-bounds ranges leave the string unchanged. Bounds are checked before indexing, including integer-overflow cases.
- **Date formatters:** `makeNewDateFormatter()` returns an independent instance. Gallery filenames and unrelated date labels can no longer overwrite one another's formatter configuration. This correctness fix trades shared formatter reuse for per-call allocation; it is not a formatter performance optimization.
- **Image-cache timers:** removing the final image, closing the final zero-grace scope, or evicting an oversized insertion stops or avoids the sweep timer. Replacing the sole entry does not cancel and recreate a live timer. Cache limits and eviction order are unchanged. The timer tests establish cancellation, not a measured battery-life improvement.
- **Hashtag album selection:** membership sets and ordered album buckets replace repeated full-history searches for multiple selected IDs. An album expands once, selected messages remain first, and siblings keep their original first-occurrence order. The single-ID path preserves the original scanning logic. The internal generic helper is inlined so typed ID/group access does not add overhead to that path. The helper assumes the history contains unique message IDs, as the original history selection did.

## Evidence

[Baseline failures](Results/baseline-failures.txt) record five failing tests with seven failed assertions before production edits, plus a separate spoiler process crash at an invalid UTF-16 index. [Validation](Results/validation.json) records the final test configurations. [Provenance](Results/provenance.json) identifies the baseline Git revision, compiler, architecture, and final production-source hashes.

The suite covers nine calendar identifiers and eight timezones, each with 400 deterministic random timestamps plus Int32 limits and month boundaries. It also covers 23/25-hour days, half-hour DST, midnight DST, a skipped date, timezone/locale invalidation, and concurrent cache access. Spoiler tests compare every valid range of Unicode fixtures and the full UTF-16 mask mapping with the original algorithm. Album tests compare 2,000 randomized selections against the original result with duplicates removed. Image tests exercise count/byte limits, replacement, eviction, removal, scope closure, sweeping, and concurrent bookkeeping. Shared mutable formatter settings have a separate regression and concurrency test.

## Release measurements

These are component timings on this machine, not total Telegram speedups. Each entry is the median of nine samples after warmup, with baseline/candidate order alternated and result checksums compared. Spoilers additionally have exact string and UTF-16 correctness checks. Album benchmarks use synthetic messages with integer IDs and groups; real Postbox messages may have different constants. Both selection implementations compile in the same lab module. The original date and spoiler implementations are frozen in `Sources/Baseline`; only names and comments were adjusted. The short-string fixture contains ASCII, Cyrillic, and emoji variants.

| Scenario | Calls per sample | Before ms | After ms | Before / after |
| --- | ---: | ---: | ---: | ---: |
| day-clustered | 20,000 | 0.333 | 0.316 | 1.05× |
| day-scattered | 1,200 | 1.655 | 1.250 | 1.32× |
| month-clustered | 20,000 | 14.875 | 0.509 | 29.22× |
| month-scattered | 1,200 | 1.038 | 1.528 | 0.68× |
| spoiler-16-utf16 | 3,000 | 28.876 | 0.639 | 45.18× |
| spoiler-256-utf16 | 3,000 | 63.316 | 2.327 | 27.21× |
| spoiler-4096-utf16 | 300 | 55.125 | 3.002 | 18.36× |
| spoiler-short-range-in-long-text | 1,000 | 24.422 | 7.954 | 3.07× |
| selection-2000-ids-1-albums-true | 20 | 0.044 | 0.035 | 1.25× |
| selection-500-ids-50-albums-true | 20 | 0.593 | 0.426 | 1.39× |
| selection-2000-ids-200-albums-true | 20 | 7.123 | 1.797 | 3.96× |
| selection-10000-ids-1000-albums-true | 20 | 147.764 | 9.876 | 14.96× |

All sample values, including selection without album expansion, are in [the raw benchmark report](Results/benchmarks.json). Ratios near 1 are timing noise rather than meaningful wins. Clustered dates span about 33 hours; scattered dates jump across 1,200 distinct dates over roughly 114 years, defeating the 16-entry caches. Scattered month lookup is slower because misses construct reusable calendar intervals and take the cache lock. This is an explicit tradeoff for repeated months in media lists. The short-range spoiler benchmark masks six UTF-16 units inside a long mixed-language string.

## Audit scope and remaining validation

The source review covered chat-history grouping and selection, list diffing and sticky-row lookup, text formatting, image-cache lifetime/eviction, and animation frame queues. The forward list diff already avoids repeated insertion/removal work; the quadratic reversed variant has no call sites in the searched app/packages, so it was left alone. Sticky rows already use cached indices and binary search. Lottie's frame queue is capped at two to four entries, so changing its array into a queue is unlikely to offer a useful win without a real profile.

Image eviction still scans entries under a lock, especially relevant to the larger emoji cache; chat-history neighbor searches and repeated link-regex compilation remain candidates for profiling. They were not changed without evidence of useful gains. Existing edits in ChatListUI, ChatUI, HTMLBubbles, and submodules were preserved.

The independent production files also typecheck for x86_64 macOS 10.13. The lab does not build the full `ChatHistoryModel` dependency graph or exercise a signed-in Telegram UI, server-backed hashtag results, scrolling FPS, GPU work, or total process memory. Full-app smoke checks should cover opening chats/media across a timezone change, spoiler previews, selecting multiple items from one hashtag album, closing media screens, and gallery export while other date labels update. Existing account-backed PerfLab scenarios in `docs/perflab/README.md` can quantify end-to-end effects when a main-app build is available. These tests reduce regression risk; they cannot prove that every app workflow is unaffected.
