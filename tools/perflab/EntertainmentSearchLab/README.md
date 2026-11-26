# Entertainment search regression lab

This small Swift package tests emoji, sticker and GIF searches without building Telegram. It uses the repository's real SwiftSignalKit and Strings packages. `prepare.py` copies the production keyword and request helpers and extracts the production InputSources search method, emoji search pipeline, sticker inputs/results pipelines, and GIF request closures. It records source hashes in `provenance.json`. Engine, account and view state boundaries use test doubles.

Run from the repository root:

```sh
python3 tools/perflab/EntertainmentSearchLab/prepare.py
swift test --package-path tools/perflab/EntertainmentSearchLab --scratch-path /tmp/EntertainmentSearchLab-debug
swift test -c release --package-path tools/perflab/EntertainmentSearchLab --scratch-path /tmp/EntertainmentSearchLab-release
swift test --sanitize=address --package-path tools/perflab/EntertainmentSearchLab --scratch-path /tmp/EntertainmentSearchLab-asan
swift run -c release --package-path tools/perflab/EntertainmentSearchLab --scratch-path /tmp/EntertainmentSearchLab-release SearchBench 1
swift run -c release --package-path tools/perflab/EntertainmentSearchLab --scratch-path /tmp/EntertainmentSearchLab-release SearchBench 5
swift run -c release --package-path tools/perflab/EntertainmentSearchLab --scratch-path /tmp/EntertainmentSearchLab-release SearchBench 100
```

Run `prepare.py` again after editing production sources. Generated files are ignored and never replace production implementations with handwritten equivalents. Extraction markers fail loudly when surrounding source changes. Compilation checks the extracted closures against the test double APIs, not the entire app's dependencies.

## Regression coverage

- Two-word phrases (`red heart`, `happy birthday`), partial second words, whitespace, case, exact matching and no union of unrelated individual-word results.
- Progressive English fallback, duplicate languages/results, cancellation, prediction preferences and literal emoji bypass.
- Matched emoji passed to sticker search, skin-tone normalization, category API routing, and local packs visible before remote completion.
- New queries cancel previous work during debounce. Duplicate queries and scrolling do not restart active searches; ordinary browsing still responds to scrolling.
- GIF server cursors, overlapping pages, duplicate entries, repeated/cyclic cursors, stale callbacks, cache eviction, canceled searches and completion without a result.
- Emoji variation selectors, skin tones, ZWJ/gender/family distinctions and canonical membership equivalence.

The keyword dictionary fixture models token intersection and prefix matching; it does not exercise Postbox's real database. The production engine's token-intersection lookup remains unchanged.

## Measured results

See [results.json](results.json) for raw benchmark measurements, test counts, toolchain and source hashes. The benchmark scans 10,000 synthetic items for 20 renders, compares the previous array membership operation with the production index, includes index construction, checks matching counts, and reports the median of nine runs.

| Search keys | Array membership | Production index | Speedup |
| --- | ---: | ---: | ---: |
| 1 | 2.774 ms | 0.743 ms | 3.74× |
| 5 | 9.829 ms | 1.492 ms | 6.59× |
| 100 | 150.204 ms | 3.090 ms | 48.61× |

These are filtering microbenchmarks, not end-to-end picker latency or network measurements. The fixture uses repeated single-scalar emoji keys; real packs include multi-scalar sequences, different hit rates and other rendering costs. Unicode sequences have separate correctness tests.

The request integration tests also verify that 1,000 repeated scroll requests produce one engine subscription per GIF page, and 100 scroll updates do not restart an active sticker search.

The main app was not built, and authenticated server responses, visual picker transitions and actual database synchronization were not exercised. Manual app verification should include two-word searches on English and non-English keyboards, switching categories while typing, clearing/reopening search, and scrolling several GIF pages.

## Cold-start regression

The original harness preloaded category state, hiding a circular startup dependency introduced in `36c430447`. The app's state promises start empty: emoji content waits for search, search waits for category state, and category state waits for content. The popover waits for the controller to become ready.

The harness now extracts the production state-promise initializers. Three cold-start tests failed before the fix. Seeding only the category signal breaks the cycle while keeping full content readiness dependent on actual data. All 56 tests pass in debug, release and Address Sanitizer; see [cold-start-results.json](cold-start-results.json). This verifies the startup dependency, not a full-app mouse-hover interaction.

## Search loading and empty states

The loading-state revision contains 65 tests, including loading-to-empty transitions, clearing an in-flight query, GIF completion without results, spacer-only sticker tables, and the actual emoji state equality comparison. The six additional AppKit tests and visual previews live in [EntertainmentSearchViewLab](../EntertainmentSearchViewLab/README.md). The earlier result files above preserve the measurements from their original revisions.

## Named custom emoji search

The suite now contains 83 tests. The controller search pipeline uses the same `emojiSearchContext`, `searchEmojiSets`, and `searchEmojiSetsRemotely` APIs as the iOS keyboard for the Emoji and Stories modes. Tests cover `peppa pig` without Unicode keyword matches, forwarding the whole phrase and matched emoticons, debounce, cancellation of old emoji/pack responses, local results before remote completion, empty remote completion, category routing, context lifetime and subsequent page emissions. Specialized status/effect pickers keep their existing keyword search.

The actual production pack grouping deduplicates collection IDs and files and preserves installation status. The section selector excludes unrelated browsing packs while searching, restores them on clear, and preserves the message-effects pipeline's already-filtered sections. Production state and section equality bodies are tested for same-count replacements. The preparation script also checks that the controller uses this selector and allows remote files when Unicode results are empty; it does not compile the full row-building function.

All 83 tests passed in debug, release, and Address Sanitizer. The six actual AppKit status-view tests passed again. A negative control restored the old keyword-only search and unconditional browsing-pack behavior in generated test copies: both targeted regression tests failed, with eight failed assertions. Production copies were then restored and all tests rerun. See [custom-emoji-search-results.json](custom-emoji-search-results.json) for source hashes and counts.

These results do not prove the authenticated server's result set for `peppa pig`. Check that query in the app, alongside an empty query, category switches, clearing/reopening the picker, and scrolling additional custom emoji pages. The full app was not built.
