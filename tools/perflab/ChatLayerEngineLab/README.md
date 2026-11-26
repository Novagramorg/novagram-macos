# Chat layer engine lab

This mini-app compares a representative plain-text chat row built with TGUIKit views against the same content built with the production `ChatLayerSceneView`, `ChatLayerTextNode`, and `ChatLayerButtonNode` sources. `prepare.py` copies those files without rewriting them; `provenance.json` records source hashes. TGUIKit is a direct package dependency.

The live app now uses the scene engine for supported plain, linked, static quoted, and foldable quoted `ChatMessageView` text bodies and captions, including supported code blocks. Rich text that still needs additional behavior retains native rendering. The separate full-row prototype has a bubble, author, forwarded label, reply preview, selectable linked body, timestamp, avatar, reaction, and reply action. That prototype is not an instantiation of `ChatRowItem` or the complete production message renderer. The live text-binding harness described at the end of this document compiles the actual production binding methods with stand-in account and row models.

## Run

From the repository root:

```sh
python3 tools/perflab/ChatLayerEngineLab/prepare.py
swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-debug
swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release
swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-asan --sanitize address
swift run --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-debug ChatLayerEngineApp
```

Run the release benchmark separately, with the demo and other builds stopped:

```sh
CHAT_LAYER_BENCHMARK=1 swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --skip-build --filter BenchmarkTests.testRowBenchmarks
python3 tools/perflab/ChatLayerEngineLab/measure-memory.py
```

The native document is on the left and the layer document on the right. Try links, reply/reaction buttons, selection, copy, context menus, Tab/Shift-Tab, and scrolling. The window title identifies activated actions. The app uses placeholder assets and has no account or network dependency.

## Architecture and contracts

One scene view owns a tree of layers and dispatches pointer events through stable node identifiers. Decorative nodes do not enter the pointer target index. The scene provides pointer capture, cancellation, event bubbling, hover paths, keyboard focus, context-menu routing, and accessibility elements. Nodes are reused when rows are rebound.

Use node `frame`, `transform`, `sublayerTransform`, `zIndex`, and `setChildren` APIs for scene geometry. Direct geometry or hierarchy mutations on the exposed backing layer bypass hit-index invalidation. Drawing sublayers remain owned by their node. Hit testing currently uses model-layer geometry; following animated presentation-layer positions is not implemented.

`TextViewLayer` uses the existing TextView drawing implementation. The text node delegates character and selection geometry to `TextViewLayout`. The existing hosted TextView rendering path remains unchanged. Buttons use layer nodes, with an NSView only at the scene root.

## Validation

The initial engine and geometry validation covered 69 functional tests and seven opt-in performance measurements. Later sections record subsequent suites and results:

- 270 exact text bitmap comparisons across scale, language, alignment, selection, and active/inactive window state.
- 48 native-versus-layer selection gesture comparisons.
- 72 cross-row boundary comparisons in both table orders and drag directions, plus right-to-left logical endpoints, multi-paragraph ordering, protected text, focus transfer, reuse, and unchanged-selection invalidation checks.
- 36 exact complete-row bitmap comparisons across widths, scales, and text variants.
- 51,282 hit-target grid comparisons against the native row.
- 112 animated Metal frame comparisons, including overlapping plain, static-quote, collapsed-quote, expanded-quote, and code-header rows. These animate row movement and opacity, not the collapse transition itself. GPU rasterization has small differences: at most 1/255 per channel without color emoji and 3/255 with color emoji. The tests additionally bound differing bytes to 140 and 400 respectively (the plain-row fixture has 583,280 bytes per frame). These GPU checks are bounded comparisons, not exact equality.
- Pointer capture, cancellation, reentrant removal, ordering, transforms, rounded clipping, disabled and hidden ancestors, keyboard navigation, selection/copy, accessibility actions/tree reachability, and removed-node lifetime.

The 39-test combined debug, release, and Address Sanitizer runs, followed by final five-test geometry runs after the lazy-inset check was added, are saved in `results/geometry/`. The preceding cross-row-selection results and row benchmark samples remain in `results/cross-row/`. The original 27-test foundation runs remain in `results/`, together with the separate TGUIKit regression log. The TGUIKit run passed 218 functional tests with two optional tests skipped. UI smoke checks cover action dispatch, link activation, drag selection, a native context menu, and independent scrolling of both documents. A final external accessibility check exposed the scene document, text, and buttons, and activating its Reply element changed the window title to `Layers: Row 1: action`. These checks do not replace testing the real Telegram app.

## Results

Release medians on arm64 macOS 26.4, Apple Swift 6.3.3:

| Operation | Native views | Layer engine | Reduction |
| --- | ---: | ---: | ---: |
| Cold row construction | 310.446 µs | 66.343 µs | 78.6% |
| Attached row rebinding | 32.856 µs | 12.749 µs | 61.2% |
| Hit-target lookup | 0.276 µs | 0.234 µs | 15.2% |

The first engine version regressed hit lookup; caching ordered target bounds removed that regression. Both raw runs are retained in `results/`.

In the initial foundation revision, median incremental physical footprint for 1,500 retained, unrasterized rows was **122.59 MiB native versus 42.59 MiB layered**, a **65.3% reduction**. That is approximately 83.7 KiB versus 29.1 KiB per row in this fixture. This result does not include the premeasured text layouts, image/video resources, or display surfaces.

## Measurement limits and rollout

The prototype uses 15 native NSViews versus one scene NSView. It still owns layers, text layouts, attributed strings, and drawing resources; the view-count reduction is not a total memory reduction estimate.

Benchmarks alternate native/layer order over nine batches. Fixtures are premeasured, so cold construction and rebinding exclude text measurement. The hit benchmark measures target lookup, not complete event dispatch. These results do not measure whole-chat opening time, scroll FPS, retained process memory, or real network/media workloads.

The separate memory probe uses five fresh processes per implementation, alternating their order. Each process prepares 1,500 unique row fixtures, warms both constructors, records `TASK_VM_INFO`, retains 1,500 rows, drains autoreleases, flushes the transaction, and records it again. The layer probe also builds each row's target index. Rows are not attached to a window or rasterized. This measures incremental retained row structures and allocator overhead after layouts exist, not total app memory or displayed surface memory.

Broader migration still needs spoilers, animated quote transitions, inline custom emoji, tooltips, media/native-control integration, and full-app transition and accessibility checks. The current plain-message binding is described below. Preserve native fallbacks until the remaining cases pass. More broadly reusable engine APIs should be extracted as real chat integration demonstrates their requirements.

## Cross-row selection bridge

The scene conforms to the existing `ChatBubbleCustomTextSelection` protocol. Its declarations moved unchanged from `ChatSelectText.swift` into a dependency-light source file so the lab can compile the exact interface. Register body/caption node IDs in reading order using `selectableTextNodeIds`; decorative labels stay out of copied text.

The bridge uses scene coordinates, so table index ordering does not change which text the drag spans. It returns attributed fragments compatible with the existing manager. Multiple selected paragraphs are consolidated to preserve their order and avoid duplicate message headers when that manager reverses rows for copying. Off-row endpoints map to logical string boundaries, preserving right-to-left suffixes. Repeated identical selection updates do not invalidate drawing. Focus transfer preserves externally managed selection; changing the layout, removing its node, changing registration, or clearing the source removes it.

The demo wires window drag handlers to this production bridge and allows selection across the right-hand document, including copying and Escape. Automated document tests verify copied strings without changing the system clipboard. Manual UI verification selected across Latin, Arabic/Hebrew, and CJK rows and cleared all highlights with Escape. The demo does not instantiate the Telegram `SelectManager`; the actual chat integration and its autoscroll/virtualization lifecycle still need end-to-end testing. Rotated/clipped text, folded content, and rich media are not covered by this plain-text adapter.

## Shared production row geometry

`ChatRowGeometry.swift` provides value-only bubble, base-content, and timestamp positioning. `ChatRowGeometry+Item.swift` maps real `ChatRowItem`, `ChatMessageItem`, and `ChatVideoMessageItem` data into those inputs. The current live `ChatRowView` delegates these three calculations to the shared implementation. Its existing caches and virtual content/timestamp methods remain in place, so specialized media/HTML row overrides still participate.

The geometry harness compiles these two production files and extracts the current row method bodies unchanged. Telegram model objects are represented by scalar stand-ins to avoid building the full Telegram dependency graph. `Reference/ChatRowFrames.swift.txt` preserves the original methods from commit `7f127e708`, with trailing whitespace normalized; its provenance records both the original source hash and captured method hash. This is a test of real geometry and wrapper code, not a full Telegram build.

The matrix checks 15,360 combinations and 61,440 exact frame pairs: row widths, incoming/outgoing, list/bubble, overlay, centered thread, comments, video transcription, big emoji, action buttons, and webpage cases. Further tests exercise thread identity, fractional/negative dimensions, content overrides and cache invalidation, and calling the geometry directly without constructing a row view. Accessory geometry is shared as described below; specialized media geometry still requires migration.

The initial extraction added about 5 ns to an uncached three-frame refresh in the synthetic model benchmark. Inlining the value-only functions and adapters removed that overhead. Final release medians were 88.31 ns original versus 87.61 ns shared for refreshes, and 4.99 versus 4.99 ns for cached reads. Treat the small difference as effectively flat for app performance: the purpose of this change is to share exact layout rules without adding row construction work. The initial, inlined, and final measurement versions are retained under `results/geometry/`. A getter-count regression also verifies that incoming rows retain the original lazy behavior and do not evaluate the unused left inset.

To run the opt-in geometry benchmark after a release build:

```sh
CHAT_GEOMETRY_BENCHMARK=1 swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --skip-build --filter GeometryBenchmarkTests.testFrameCalculationBenchmarks
```

## Shared accessory geometry

The live row now uses the same value-only calculations for avatars, captions, replies, topic links, author names, forward names, forward headers, and forward lines. These functions need no NSView. The item adapter preserves conditional evaluation of computed insets, and the wrappers continue to call cached virtual content geometry.

The accessory reference captures the original methods from `642ec2a49`. The harness checks 61,440 state combinations and 491,520 exact position comparisons, including both media orders, all forwarding styles, missing accessories, side actions, incoming/outgoing rows, and fractional sizes. Getter-count tests verify that absent accessories avoid content construction, inactive branches skip computed geometry, and caption layout reads its size once fewer: two reads become one normally, and three become two for inverted media. The real folding text layout computes size by scanning blocks; this change removes one such scan per caption positioning call.

Final release validation passed 44 functional tests with three optional measurements skipped. The final nine functional geometry tests also passed in debug and Address Sanitizer. Logs, production hashes, and raw benchmark samples are saved in `results/accessories/`.

Release medians were 193.02 ns original versus 194.57 ns shared for all eight accessory positions, 89.58 versus 86.28 ns for three refreshed core frames, and 4.80 versus 4.84 ns for cached frames. Treat these scalar-fixture timings as effectively flat; they do not model the real folding-text scan cost or prove a whole-app speedup. This milestone shares layout and removes redundant size reads; it does not yet activate full layer rows in Telegram.

## Real message-text adapter

`ChatLayerMessageTextPresentation` now consumes `ChatMessageItem.textLayout` and the actual `FoldingTextLayout` interface. It preserves block order, measured geometry, and TextViewLayout instances. `ChatLayerMessageTextNode` retains block nodes across updates, removes obsolete nodes, clears selection and pending link presses when message identity changes, and exposes ordered IDs for the existing cross-row selection bridge. It uses no child NSViews.

The adapter explicitly reports streaming, unsupported collapsed blocks, embedded items/custom emoji, spoilers, formatted dates, and generated block backgrounds as requiring native rendering. Foldable quotes require an explicit reveal callback; without one, binding returns false. Static quotes, foldable quotes, and code headers are supported by the later milestones below. Unsupported updates clear stale layer content and return false. These guards cover known unsupported content; they are not a complete production-rollout eligibility policy. Live row integration, rich-block rendering, native controls, tooltips, app menus, and transition behavior remain unfinished. The adapter is not enabled in live chat.

The lab compiles both production adapter files unchanged. Its `InputTextView` target is a small stand-in for FoldingTextLayout's data interface; `prepare.py` extracts the production size getter and ViewLayout unchanged. Static quote testing also extracts the exact native wrapper, as described below. `ChatMessageItem` is represented by a text-layout holder. These substitutions avoid the Telegram dependency graph and do not prove a full application build. The native pixel baseline consists of stacked real TGUIKit TextViews, matching the supported plain-block geometry.

Eight new tests cover 12 exact native/layer bitmap pairs across three scales, Latin/RTL/CJK/color emoji, node retention and release, growth/shrink/empty content, same-object remeasurement, nested selection registration, link activation, cancelled presses after reuse, and explicit native fallback. The full debug, release, and Address Sanitizer suites passed 52 functional tests with four optional measurements skipped. After adding the block-background guard and press-reuse assertion, all eight message tests passed again in each configuration. Evidence and final source hashes are in `results/message-text/`.

The release benchmark includes presentation preparation and feature inspection on every call. Layout measurement is excluded for both implementations. The native baseline is deliberately minimal: a View containing TextViews, without FoldingTextView's listeners, inline media, or wrapper controls. Layer construction includes a scene view, body node, and text nodes. Neither side is attached to a window or rasterized. Nine batches alternate execution order.

| Blocks | Construct native / layers | Same-content rebind native / layers | Changed-content rebind native / layers |
| --- | ---: | ---: | ---: |
| 1 | 27.742 / 17.102 µs | 0.485 / 1.124 µs | 1.324 / 2.265 µs |
| 3 | 69.669 / 26.799 µs | 1.370 / 2.792 µs | 3.162 / 4.866 µs |
| 12 | 252.214 / 71.305 µs | 5.371 / 10.127 µs | 11.386 / 16.197 µs |

Construction is 38–72% faster in this fixture. Rebinding is still slower than the minimal native baseline. Removing repeated geometry assignments, temporary node-array copies, and duplicate attribute scans reduced layer rebinding cost, but did not eliminate that regression. The initial and final samples are both retained. Production integration must resolve preparation/rebinding overhead instead of assuming the whole-row prototype speedup applies to this adapter. These measurements do not establish whole-chat scrolling or total app memory gains.

```sh
CHAT_MESSAGE_TEXT_BENCHMARK=1 swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --skip-build --filter MessageTextBenchmarkTests
```

## Message preparation without bridged attribute dictionaries

The adapter now reads attributed-string runs with Core Foundation and looks up the five relevant keys directly. It preserves the original quote-value type check and the presence semantics of spoiler, custom-emoji, date, and link attributes. The scanner reads current data on every preparation; it does not cache an attributed string's attributes or assume the object is immutable. Keys remain strongly retained NSString objects, and values are inspected while their owning attribute dictionaries are alive.

`Reference/MessageTextPreparation.swift.txt` captures the original value type and preparation implementation from `f8764d2bb`. Its hashes are verified during preparation. The lab compiles it with only the type name changed and compares 1,024 combinations of overlapping attributes, valid/invalid quote values, mutable/immutable strings, Unicode, empty strings, collapsed blocks, and streaming flags. A separate test mutates the same attributed-string object repeatedly, removing links/spoilers and eventually emptying its contents. Node binding also applies text and final block geometry together, avoiding the intermediate frame assignment.

All 54 functional tests passed in debug, release, and Address Sanitizer, with five optional measurements skipped. The release benchmarks were run separately without concurrent builds. Evidence and source hashes are in `results/message-preparation/`.

The cost breakdown compares the captured original preparation and current preparation in the same process, interleaved with binding an already prepared presentation. It does not eliminate preparation from the end-to-end benchmark:

| Blocks | Original preparation | Current preparation | Bind already-prepared text |
| --- | ---: | ---: | ---: |
| 1 | 0.814 µs | 0.195 µs | 0.347 µs |
| 3 | 2.350 µs | 0.479 µs | 0.583 µs |
| 12 | 9.157 µs | 1.732 µs | 1.649 µs |

Preparation is 76–81% faster in these fixtures. End-to-end results, still including preparation on every call, are:

| Blocks | Construct native / layers | Same-content rebind native / layers | Changed-content rebind native / layers |
| --- | ---: | ---: | ---: |
| 1 | 29.949 / 17.031 µs | 0.535 / 0.574 µs | 1.438 / 1.710 µs |
| 3 | 73.948 / 25.940 µs | 1.405 / 1.073 µs | 3.415 / 3.179 µs |
| 12 | 269.697 / 63.195 µs | 5.598 / 3.428 µs | 12.201 / 9.472 µs |

The three- and twelve-block layer cases now rebind faster than the minimal native baseline. Single-block rebinding is still slower: about 0.04 µs extra for unchanged content and 0.27 µs for changed content in this run. The previous milestone's slower measurements remain archived. Full rich-text and live-chat integration remain unfinished, and these numbers do not establish a whole-app speedup.

## Static quoted text and cursor-event safety

The message adapter now supports static quotes and code-style blocks without headers or a reveal control. It preserves native text drawing and measured geometry. A quote-only shape mask matches the native wrapper's clipping; it is reused when bounds stay unchanged and released when a node returns to plain text. Plain nodes do not allocate the mask. At this milestone, expanded foldable quotes still required native rendering. The following milestone adds their background and interactions. Eligibility is recomputed after remeasurement: narrowing a short quote until it becomes foldable requires a reveal callback.

The lab extracts the complete production `WrapperView`, `FoldingTextLayout.ViewLayout`, and mask generator unchanged from `FoldingTextView.swift`. Small account-context, icon-provider, and inline-sticker stand-ins let that code compile without Telegram. Inline-sticker updates do no work in this harness; tested static quotes have no inline media. This is stronger than a hand-written wrapper baseline, but remains a fixture rather than a full application build.

Validation adds 72 exact isolated quote bitmap pairs, 24 exact complete-row bitmap pairs, 12 native/layer selection gesture comparisons, plain/quote node reuse, and fallback checks. Languages include Latin, Arabic/Hebrew, CJK, combining marks, and color emoji at scales 1/2/3. The 1,024 preparation-reference combinations still compare non-quote feature flags and block geometry; quote eligibility intentionally differs from the original implementation and now has separate tests, including clipping metadata checks.

Sixteen additional animated Metal frames exercise quoted rows with overlap and color emoji. The existing tolerances remain unchanged. Quoted frames differed by at most 116 bytes at 1/255 without color emoji and 337 bytes at 3/255 with emoji. Initial GPU tests exposed substantial clipping differences despite exact software bitmap matches. Adding the native-equivalent shape mask fixed those differences. The fixture also preserves the real native wrapper's `masksToBounds` setting rather than overriding it during row binding. The failed pre-mask run is retained as evidence.

The full debug, release, and Address Sanitizer runs passed 60 functional tests with six optional measurements skipped. After the final reflow assertions, that regression passed again in all three configurations. Interactive verification then exposed an AppKit assertion: cursor-update events do not permit reading `NSEvent.clickCount`. Event normalization now reads it only for button events. All 17 scene tests, including the new tracking-event regression, passed in debug, release, and Address Sanitizer. The focused text/message/quote tests also passed after this fix. The suite now contains 61 functional tests; the final cursor change was verified with focused runs rather than another full run.

The rebuilt visible demo passed quote-link activation followed by Reply activation, cross-row quote/plain selection, Escape clearing, and scrolling the layer document independently. The action title remained intact through these checks. Every fifth demo row is quoted. Full live-chat selection-manager integration, folded quotes, headers, media, and transition behavior remain pending.

Release medians from nine alternating batches:

| Static quote operation | Native wrapper | Layer engine | Reduction |
| --- | ---: | ---: | ---: |
| Construction | 32.504 µs | 19.411 µs | 40.3% |
| Changed-content rebinding | 3.505 µs | 2.464 µs | 29.7% |

The native quote wrapper contains two NSViews; the layer implementation uses one scene NSView with no child views. A complete quoted demo row has 16 native NSViews versus one scene view. Benchmarks use premeasured layouts and unattached, unrasterized objects. Layer preparation runs on every call, and construction includes its scene host. Account/media stand-ins omit some native work. These measurements do not establish live-chat frame rate, opening latency, or process-memory savings.

Plain-control samples are retained too. Changed-content rebinding for one block remains slower than the minimal native baseline (1.758 versus 1.446 µs), while three and twelve blocks remain faster (3.171 versus 3.355 µs and 9.984 versus 12.049 µs). Rich-block support must continue to be measured rather than extrapolated from view counts.

Evidence, sanitized crash details, raw samples, and final production hashes are saved in `results/static-quotes/`. Run the optional quote benchmark with the demo and other builds stopped:

```sh
CHAT_QUOTE_BENCHMARK=1 swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --skip-build --filter StaticQuoteBenchmarkTests
```

## Foldable quotes and full-import compatibility

Foldable quotes now use the existing measured arrows and fade image through public `FoldingTextLayout.ViewLayout` properties. A quote-only decoration object owns the background, arrow, and optional text mask; expanded text retains its full drawing bounds while the node uses the visible viewport. Decorations and masks are reused and removed when the node returns to plain text. Each plain block adds only an optional reference for folding metadata, rather than embedding the full rich-layout structure.

`FoldingTextQuoteLayer` shares the native wrapper's painter. It lives in the already-discovered `FoldingTextView.swift` source so Xcode does not need to discover a new package file mid-session. The lab captures the original wrapper from `0dfe6ec5e`, verifies its hash, and verifies that the shared painter differs only in declaration visibility/name and indentation. Both the current native wrapper and layer renderer are compared with that captured implementation. Account and inline-media stand-ins remain the same limitation as above.

Binding requires `revealBlockAtIndex` for foldable content. The callback receives the block index, allowing the real row model to own expansion and remeasurement. The demo rebuilds the fixture and repositions following rows on a toggle; it does not implement the production animated collapse transition. Link activation, selection drags, selection clearing, cancelled presses, disabled nodes, and message reuse suppress unwanted toggles. Return/Space and accessibility press can activate the callback. Cross-row selection clearing preserves the native suppression behavior for the next click; a failing regression was captured before this fix.

The added rendering matrix checks 72 folded/expanded native-to-layer bitmap pairs and 72 captured-to-current native pairs across scales, widths, languages, quote colors, and code-style blocks. Another 12 pairs cover selected folded/expanded text. The 32 additional GPU comparisons use the existing channel and byte-count tolerances. They initially failed because background ordering and background-mask compositing differed from the native wrapper. Matching both fixed the failures without increasing tolerances. At this milestone, rich code headers remained native-required; the next milestone adds their interactions.

A real Xcode build exposed an import-dependent compiler error that the smaller harness had missed: Quartz/ImageKit adds `isSelectable` to NSObject, conflicting with the new layer property. `TextViewLayer` now calls that flag `isTextSelectable`; the TextView API is unchanged. A dedicated test imports Quartz, reproduced the ambiguity before the rename, and passes afterward. Source-file discovery and property-name fixes are included in this milestone; no full Telegram build is claimed by these lab runs.

Full debug, release, and Address Sanitizer runs passed 68 functional tests with seven optional measurements skipped. Seven focused production TGUIKit tests also passed. After the final cross-row click-suppression regression and selected-pixel test were added, 15 fold/cross-row/import tests passed in all three configurations. After reducing repeated binding work, the 17 affected fold/message/preparation/import tests passed in all three configurations. The suite now has 69 functional tests. The standalone renderer lab also compiles after the API rename and passes its copied-layer regression.

Plain bindings skip repeat callback configuration and use a prepared reveal-required flag instead of rescanning blocks. Fold callbacks are retained by stable block index and read the owner's current reveal action. The final measurements below retain preparation on every call and include the scene host in layer construction.


| Operation | Captured native wrapper | Layer engine | Reduction |
| --- | ---: | ---: | ---: |
| Foldable quote construction | 37.359 µs | 23.464 µs | 37.2% |
| Folded/expanded rebinding | 5.602 µs | 3.990 µs | 28.8% |
| Static quote construction | 32.940 µs | 21.115 µs | 35.9% |
| Static quote rebinding | 3.439 µs | 2.403 µs | 30.1% |

The native fold fixture has two NSViews, compared with one scene host and no child views. The same nine-batch, premeasured, unattached/unrasterized limits apply. These results measure component work, not whole-app frame time or memory.

Plain binding work improved after removing repeated callback updates: unchanged twelve-block binding fell from 4.491 to 3.969 µs in the two retained runs. It still exceeds the prior milestone's 3.514 µs layer result. Final changed-content native/layer controls were 1.418/1.717 µs for one block, 3.318/3.270 µs for three blocks, and 12.144/10.168 µs for twelve blocks. The one-block layer case remains slower than the minimal native baseline; adding rich-block support has not eliminated all preparation/binding overhead.

Manual verification in the rebuilt demo passed native/layer expansion, following-row repositioning, link activation, selection across an expanded quote and the next RTL row, a first click that clears selection without collapsing, a second click that collapses, and Return to expand the focused quote. The renderer remains inactive in Telegram's live chat. Real model/selection-manager integration, code-header actions, animated collapse transitions, inline media, spoilers, and app-specific interaction/transition behavior remain pending.

All logs, both failing regression reproductions, GPU mask evidence, raw benchmark batches, final production hashes, and manual observations are in `results/foldable-quotes/`.

## Code headers, copy ranges, and quote link hit-testing

Code-block headers now have retained `ChatLayerButtonNode` children. The existing painter still draws the header; the node supplies pointer capture, cancellation, Return/Space activation, a reachable accessibility button, and the copy action. Rebinding retains the button and callback when the quote index is unchanged. Changing messages cancels a pending press; removing headers detaches their nodes. Header presses do not initiate the demo's cross-row text selection. Header support adds no NSViews or stored header collections to plain text nodes. The main app's full layer renderer remains inactive.

`TextViewLayout.blockQuoteText(startingWith:)` is also used by the current native TextView. It traverses quote-attribute ranges and extracts plain text directly, preserving the old forward scan's presence semantics across adjacent different quote values. It validates ranges without overflowing. The first implementation used ordinary effective ranges; per-character styling fragmented those ranges and caused a small regression. Longest-effective-range traversal removes that Swift-level fragmentation cost. There is no cache to become stale when attributed text changes.

A new interaction regression exposed an existing native bug: link hit-testing omitted the text's horizontal inset inside quotes. The shared link method now follows the renderer's Core Text pen offset, line inset, right cutout, and quoted RTL adjustment. This fixes native and layer hits without changing drawing. The original failing sanitizer test output is retained in `link-regression-asan.log`.

Validation adds 18,688 comparisons against the original copy algorithm, including UTF-16 boundaries, empty ranges, adjacent different quote values, unrelated styling, mutable attributes, and invalid ranges. Header tests cover independent multi-block copying, links, selection, disabled state, cancellation, message reuse, resize, removal, nonselectable text, keyboard actions, and the accessibility tree. There are 36 exact native/header bitmap comparisons and 48 additional animated Metal comparisons with the unchanged existing tolerances. Seven TGUIKit hit-testing tests pass, including 54 new combinations of quotes, alignment, cutouts, and LTR/RTL text.

The initial full debug suite passed 74 functional tests with eight optional benchmarks skipped. The full release suite after the link fix passed 75 functional tests with eight skipped. The final longest-range change subsequently passed all five header regressions in release, including the 18,688 copy comparisons. The final Address Sanitizer run passed all 37 selected text, quote, header, and cross-row-selection tests. Validation logs and production hashes are saved in `results/code-headers/`.

Final release medians, nine alternating batches, microseconds per operation:

| Operation | Original/native | Current/layers | Reduction |
| --- | ---: | ---: | ---: |
| Copy 32 UTF-16 units, uniform attributes | 0.735 | 0.172 | 76.6% |
| Copy 32 UTF-16 units, per-unit styling | 0.707 | 0.230 | 67.5% |
| Copy 4,096 UTF-16 units, uniform attributes | 89.235 | 0.406 | 99.5% |
| Copy 4,096 UTF-16 units, per-unit styling | 91.165 | 13.795 | 84.9% |
| Copy 32,768 UTF-16 units, uniform attributes | 746.305 | 1.275 | 99.8% |
| Copy 32,768 UTF-16 units, per-unit styling | 738.269 | 108.405 | 85.3% |
| Code-header construction | 33.628 | 26.309 | 21.8% |
| Changed-content code-header rebinding | 3.601 | 3.095 | 14.1% |

Copy timings exclude pasteboard and confirmation UI. Header construction/rebinding uses premeasured, unattached, unrasterized fixtures. The captured native wrapper does not implement the new layer button's keyboard/accessibility behavior. These measurements do not establish whole-app scroll FPS, opening latency, or retained memory.

A separate plain-message check measured construction at 17.037/25.989/63.322 µs for 1/3/12 blocks, unchanged rebinding at 0.625/1.278/4.122 µs, and changed rebinding at 1.758/3.362/10.227 µs. Single-block rebinding remains slower than the minimal native baseline (0.532 µs unchanged and 1.444 µs changed). The prior fold milestone's twelve-block unchanged binding was 3.969 µs; this run is slightly higher. Both limitations remain visible in the raw results rather than being presented as universal speedups.

The release mini-app smoke check verified native and layer header activation, the layer accessibility button, a visible link inside the code block, and selection across the code block into the following CJK row. Demo copy callbacks report through the window title; automated tests assert actual callback payloads. The app was closed afterward. `manual-smoke.json` records the binary hash and observations.


## Live selection manager, offscreen rows, and quote attribute identity

The main app's existing selection manager now preserves encounter order across native and custom-rendered messages. Previously it concatenated the two renderer groups before copying, which reordered mixed selections. The real selection loop now saves custom fragments as rows leave the visible region, just as it already did for native text. Restored snapshots keep attributed text and rich-message classification without retaining or clearing a reused row view. Rich-media clipboard attachments still require their live source view; this milestone does not claim full offscreen media serialization.

New-row registration avoids repeated full-array searches during drag updates, and clearing custom sources uses identity-set deduplication. Copying checks the final UTF-16 units directly instead of bridging the entire growing output to a Swift String after every fragment. CRLF behavior, headers, ellipses, attributes, and native fragment order remain covered against the captured implementation. Invalid and stale ranges are checked without integer overflow before substring extraction.

The harness compiles the actual SelectManager storage/copy prefix and actual runSelector method, alongside captured originals from 4e7e0facb. SwiftSignalKit Atomic, TextView, and the layer scene are real dependencies. Account state, row metadata, rich-row classification, and table virtualization are explicit stand-ins in SelectionDependencies.swift. This tests the production selection loop but not full Telegram scrolling, event routing, pasteboard serialization, or account integration.

Coverage includes 512 mixed-renderer/fragment/header comparisons, 128 selection-loop combinations across drag directions, table directions and partial endpoints, repeated offscreen restoration, shrinking selections, invalid/mutated UTF-16 ranges, source lifetimes, reentrant clearing, and ordered deduplication of 512 sources. Captured-original tests demonstrate both mixed copy ordering and lost offscreen custom text before the fixes.

The expanded GPU checks exposed a separate production bug: TextViewBlockQuoteData equality omitted folding/header state, and equal values inherited different identity hashes. Foundation could coalesce attributes with different rendering state. Equality now includes folding and header identity, with a matching hash. Two TGUIKit regressions cover the equality contract, 1,024 retained attributed strings, run boundaries, and measured folding/header state. GPU tests also assert the model's folding/mask state before pixel comparison; no tolerances were relaxed.

Release benchmark medians, nine alternating batches, microseconds per operation:

| Operation | Original | Current | Reduction |
| --- | ---: | ---: | ---: |
| Copy 16 rows | 431.116 | 314.464 | 27.1% |
| Copy 128 rows | 10,084.985 | 2,486.778 | 75.3% |
| Copy 512 rows | 143,410.875 | 10,576.707 | 92.6% |
| Native selection update, 128 rows | 420.337 | 90.481 | 78.5% |
| Native selection update, 512 rows | 7,408.325 | 763.662 | 89.7% |
| Custom selection update, 128 rows | 499.572 | 177.560 | 64.5% |
| Custom selection update, 512 rows | 8,875.841 | 2,419.496 | 72.7% |

The benchmark uses precreated attributed strings containing Latin, emoji, Arabic and CJK. An update clears and re-adds the selection; it excludes table layout, pointer processing, rendering, and pasteboard writes. It does not establish scroll FPS. One-row native/custom updates cost approximately 0.12/0.17 microseconds more because of ordering bookkeeping. One-row copying was essentially unchanged (19.460 to 18.944 microseconds). Raw batches include all 1/16/128/512-row cases.

The final release and Address Sanitizer suites each passed 86 functional tests, with nine optional benchmarks skipped. The two dedicated TGUIKit quote-attribute tests also passed. Evidence and production hashes are retained in results/selection-manager/. The full layer row renderer remains inactive in Telegram; its live row binding, rich-media behavior and transitions remain work in progress.


## Native text blocks: register playback observers only for inline media

This change affects the existing FoldingTextView used by chat message bodies, media captions, audio transcription, and gallery captions. Previously every plain or quoted block allocated an AnimatableContentObserver and its forwarding target and subscribed to scroll, geometry and window notifications, even with no inline media. The callback passed an empty collection to the playback helper. Those blocks now allocate neither object and register no playback listeners. Reusing a media-bearing block for plain text releases its observer and unregisters immediately.

The inline-media updater also returns before reading text attributes when both the new embedded-item list and existing layer dictionary are empty. Existing layers must still be removed when content becomes plain. Quote wrappers refresh registration after each content update so media added to an already-attached view receives notifications immediately. The plain-block caller already refreshes registration after updating content. No public API, text measurement, drawing, or selection algorithm changes.

The new FoldingBlocksHarness target compiles the actual FoldingInlineStickers, PlainTextBlock and WrapperView declarations, plus a captured baseline from 51214687b. The key collection and playback eligibility loop are copied from production with visibility-only changes and source hashes. It uses real TGUIKit TextView, AnimatableContentObserver, AppKit windows, scroll views, NotificationCenter, and measured text. Account objects and inline media layers are lightweight stand-ins; media decoding, fetching, timers and animation rendering are not modeled. Plain-block lifecycle forwarding follows FoldingTextView's existing calls; this harness does not compile the complete parent FoldingTextView.

Five regression tests cover media appearing after attachment, plain/quoted text, emoji/avatar replacement and removal, unsupported embedded items, repeated registration, reparenting, detachment, destruction, key-window changes, clipping visibility, lite mode, and allocation/release of the optional observer. The initial tests reproduce unwanted empty playback callbacks in the captured source. A test checks notifications immediately after content replacement, before any extra lifecycle update. Existing rendering parity checks remain unchanged.

The full release and final Address Sanitizer suites each passed 91 functional tests with ten optional benchmarks skipped. After strengthening immediate-registration assertions, all five lifecycle tests passed again in release. Benchmark timings use nine alternating batches; notifications are scoped to real scroll views. The playback entry is instrumented to count invocations, and the media layer stand-ins implement the actual eligibility loop. These are component timings, not whole-app scrolling FPS or a resident-memory measurement.

Final release medians, microseconds per operation:

| Operation | Original | Current | Reduction |
| --- | ---: | ---: | ---: |
| Plain block construction | 21.176 | 19.877 | 6.1% |
| Quoted block construction | 35.582 | 34.213 | 3.8% |
| Plain block rebinding | 1.382 | 0.715 | 48.2% |
| Quoted block rebinding | 3.299 | 2.333 | 29.3% |
| Scroll notification, 40 plain blocks | 3.726 | 0.127 | 96.6% |
| Scroll notification, 40 quoted blocks | 4.364 | 0.126 | 97.1% |
| Scroll notification, 40 plain blocks, 25% with media | 3.878 | 1.058 | 72.7% |
| Scroll notification, 40 quoted blocks, 25% with media | 4.417 | 1.242 | 71.9% |

With 150 media-free blocks, notifications fell from approximately 15–17 microseconds to 0.13 microseconds. The registered callback count falls from 40 to zero for 40 media-free blocks, and from 40 to ten when a quarter contain media. Construction and rebinding with inline media are effectively unchanged: the final run ranges from 0.5% slower to 1.6% faster. Those small differences should be treated as noise. The repeated run and all batches are retained in results/folding-playback/ along with regression logs and production hashes.

Run the opt-in measurements after compiling release and stopping other builds:

```sh
FOLDING_PLAYBACK_BENCHMARK=1 swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --skip-build --filter FoldingPlaybackBenchmarkTests
```


## Full native FoldingTextView reuse, actions, and streaming ownership

The harness now compiles the complete production FoldingTextView.swift, including its layout, block splitting, parent view, block views, streaming calculations, event handlers, and ordering logic. A second copy from d02da2792 supplies the captured baseline. The only extraction changes are external-import removal, public-visibility removal, and prefixing baseline FoldingText type names with Legacy. TGUIKit measurement, rendering, controls, notifications, transitions, and display-link animator are real. Account and inline-media dependencies remain stand-ins, and the loading-dots player stores animation inputs without decoding or playing Lottie data. This is full component coverage, not a Telegram app build.

Normal updates now check the existing child-view prefix before allocating ordering arrays. Changed hierarchies use identity-set membership instead of searching every block for every child, while newly constructed views assign their block array directly without building an unused set. Extra non-block subviews retain their relative order after the text blocks.

Block event handlers are installed once when a block is created or replaced. The selection-suppression flag resets on each update as before. Handlers resolve their current block through the weak owning view and validate the source control's identity; they read the latest reveal callback. Removed and replaced controls explicitly clear their handlers, including while AppKit temporarily keeps a detached wrapper alive. This eliminates repeat handler and captured-state allocations during rebinding. No public API changes.

Tests also exposed existing lifecycle bugs. A newly created text block could ignore textSelectable=false; changing userInteractionEnabled did not reach existing blocks. Both settings now propagate consistently. Ending streaming previously checked only the optional method argument and could leave the view's own loading dots attached and retained. Owned dots now detach on completion, and transfers clear the old owner's reference and replace the target's previous dots. Passing dots alongside non-streaming content also clears their former owner.

Eleven new functional tests include 42 exact pixel comparisons over 1x/2x/3x scales, two widths, mixed Unicode, selected text, plain/quoted replacement, growth, shrinkage, empty content, and externally reordered extra subviews. Additional assertions cover stable view identities, folding toggles, selection preservation/suppression, interaction flags, callback replacement, reentrant updates, stale actions on removed controls, weak owner lifetimes, loading-view release, and streaming handoffs. Captured-baseline assertions demonstrate retained loading dots and actions firing on removed blocks before these fixes.

The final full release and Address Sanitizer suites each passed 102 functional tests with eleven optional benchmarks skipped. Raw logs, baselines, source/stand-in hashes and intermediate/final measurements are retained in results/native-folding-view/.

Release medians, nine alternating batches, microseconds per complete native view update (premeasured, unattached and unrasterized):

| Rebinding case | Original | Current | Reduction |
| --- | ---: | ---: | ---: |
| One plain block | 1.753 | 1.385 | 21.0% |
| One quoted block | 3.287 | 2.903 | 11.7% |
| Three plain blocks | 4.320 | 3.588 | 16.9% |
| Three mixed blocks | 8.069 | 7.239 | 10.3% |
| Twelve plain blocks | 16.215 | 13.576 | 16.3% |
| Twelve mixed blocks | 27.150 | 24.309 | 10.5% |
| 128 plain blocks | 161.252 | 132.069 | 18.1% |
| 128 mixed blocks | 286.747 | 254.752 | 11.2% |

The repeat run is recorded separately. Construction remains close to the baseline, with small regressions in some cases (up to roughly 2% in the first final run, and 2.7% for the 128-block mixed case in the repeat). This milestone improves rebinding and fixes state/ownership bugs; it does not establish faster initial row construction, lower whole-app resident memory, or higher scrolling FPS. Intermediate runs are retained to show why ordering alone was insufficient and why the first handler implementation was replaced.

At this milestone, ChatMessageView still replaced its whole FoldingTextView when the message text changed. The following milestone adds the interaction-state checks needed to reuse that container. The app's full layer-based row renderer also remains inactive. The native fixes and benchmarks here are groundwork for that integration, and improve current caption/body rebinding independently.

```sh
FOLDING_VIEW_BENCHMARK=1 swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --skip-build --filter FoldingViewBenchmarkTests
```


## Reusing the live chat text container

ChatMessageView now reuses an idle FoldingTextView when non-animated content changes. Compatible plain/quote blocks keep their TextViews and action handlers; structural changes still add, remove, or replace individual blocks. The text frame is updated immediately, including its origin above/below webpage content. The existing same-message/same-text path retains selection. Identical text belonging to a different message clears selection without changing the old layout snapshot; the previous binding code accidentally transferred that selection.

Reuse cancels pending link-preview timers, active preview disposables, pending menu signals and highlights, and resets selection gestures and cached code-header hit rectangles. Active presses, locked selection, spoiler/shimmer transitions, active frame/quote-mask animations, onscreen menus, different accounts, streaming updates and animated replacements keep the replacement path. Streaming dots still transfer ownership as before. Reveal/streaming callbacks use the current item through their weak row owner and no longer need to be reassigned for every same-text update.

Looping inline emoji retain their compatible layers. Content changes that contain one-shot emoji or embedded avatars recreate the block's media layers while retaining its text views: one-shot playback must restart, and avatar data can change without a peer ID change. This safeguard covers both the outgoing and incoming content.

TextView highlighting also had an independent race: a previous three-second timeout removed whichever highlight happened to be current. The timeout now weakly captures and removes only its own layer. A regression test failed before the fix and passes afterward. TextView destruction now disposes its active link preview as well as its menu subscription.

The harness extracts the exact production ChatMessageView.updateText method and compares it with the captured original binding branch from 0c4e27215. Both use the current complete FoldingTextView implementation, isolating the binding strategy. ChatMessageItem, AccountContext and media dependencies are stand-ins; the real TGUIKit TextView, native AppKit views and production block/media reconciliation are compiled. This is not a complete Telegram build or a media-decoding benchmark.

Eleven chat binding tests cover compatible view identity, changed frame origins, same/different message selection, account and interaction fallbacks, animated/streaming replacement, loading-dot transfer, current-item callbacks, papercut removal, weak lifetimes, and looping/one-shot/avatar/spoiler transitions. There are 46 exact rendered-pixel comparisons across three scales, two widths, Unicode text, growth/shrinkage, plain/quoted replacement and empty content, plus folded/expanded quote transitions. A dedicated mask-animation check validates the guard even when frame animations are absent: the quote mask may belong to its decoration layer, so reuse checks the owned mask directly. Seven focused TextView reuse tests cover the highlight race, selection snapshots, active mouse gestures/animations, pending menus and pending/active link previews. Together with existing TextView drawing tests, the focused TGUIKit run passes 24 tests. The full release and Address Sanitizer mini-app suites each pass 114 functional tests with 12 optional benchmarks skipped. The focused 24-test TGUIKit suite also passes under Address Sanitizer.

Release medians from the final run, nine alternating batches, microseconds per changed-content binding:

| Case | Replacement | Reuse | Reduction |
| --- | ---: | ---: | ---: |
| 1 plain blocks | 33.949 | 2.551 | 92.5% |
| 1 quoted blocks | 47.735 | 4.899 | 89.7% |
| 3 plain blocks | 78.902 | 5.450 | 93.1% |
| 3 mixed blocks | 109.427 | 10.563 | 90.3% |
| 12 plain blocks | 279.726 | 17.990 | 93.6% |
| 12 mixed blocks | 362.411 | 32.434 | 91.1% |
| 128 plain blocks | 2727.449 | 173.155 | 93.7% |
| 128 mixed blocks | 3732.681 | 331.910 | 91.1% |

The earlier isolated run retained in benchmark-first.json shows the same reduction range. The test alternates two premeasured messages of matching block structure, includes container attachment/removal and autorelease teardown, and runs without concurrent build/test processes. It excludes text measurement, rasterization, real media decoding and window attachment. These results establish less allocation/teardown work for eligible updates, not faster first-time row creation, a whole-app RAM reduction, or a scrolling FPS gain. Compatible text-view identities are retained and obsolete objects are released; resident-memory bytes have not been measured.

Evidence and source hashes are in results/chat-text-reuse/. The full layer-based renderer remains inactive; this change improves the native path used by the app today.

```sh
python3 tools/perflab/ChatLayerEngineLab/prepare.py
CHAT_TEXT_REUSE_BENCHMARK=1 swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --skip-build --filter ChatTextReuseBenchmarkTests
```


## Shared immutable layer actions

CALayer.disableActions() is called by View, Control and TextView initialization across the app. A default TextView reached it three times, rebuilding the same ten-key Swift dictionary each time. Stack sampling of production TextView construction showed dictionary allocation, Swift/Foundation bridging and dictionary equality work on this path.

The Swift entry point now calls a typed ObjcUtils helper. It initializes one immutable NSDictionary with dispatch_once, assigns it through CALayer.actions, and still calls removeAllAnimations on every invocation. The exact action keys and NSNull suppression values are unchanged. There is no KVC in production and no change to the public Swift API. Per-layer action overrides remain independent through copy-on-write. ObjcUtils was already a TGUIKit dependency; its product is now also explicitly declared for the benchmark test target that calls the native helper directly.

Alternatives measured in the same release binary include the original literal, a cached Swift dictionary, a Foundation dictionary bridged back to Swift, KVC assignment, and the typed native helper. Every variant uses a separate CALayer: Core Animation retains an equal existing dictionary, so alternating different implementations on the same layer would retain the first implementation's storage and distort the comparison. The valid isolated results are in construction-before.json. The cached Swift form still pays bridging costs; the native helper avoids those costs and permits pointer equality on repeated calls.

Median release times in microseconds, nine alternating-order batches. The after column is the repeat run:

| Operation | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| Layer helper | 2.657 | 0.076 | 97.1% |
| View construction | 6.186 | 5.448 | 11.9% |
| Control construction | 10.011 | 5.895 | 41.1% |
| TextView construction | 18.264 | 10.704 | 41.4% |
| TextView construction + initial binding | 19.652 | 12.096 | 38.5% |

The complete production FoldingTextView construction workload also improves:

| Content | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| 1 plain blocks | 30.985 | 23.315 | 24.8% |
| 1 quoted blocks | 44.540 | 37.039 | 16.8% |
| 3 plain blocks | 75.103 | 54.937 | 26.9% |
| 3 mixed blocks | 102.960 | 81.479 | 20.9% |
| 12 plain blocks | 264.143 | 185.707 | 29.7% |
| 12 mixed blocks | 348.456 | 267.881 | 23.1% |
| 128 plain blocks | 2673.448 | 1856.608 | 30.6% |
| 128 mixed blocks | 3505.887 | 2700.172 | 23.0% |

These construction workloads include autorelease teardown, use premeasured text, and are unattached and unrasterized. The folding comparison uses the current native FoldingTextView on both sides of the helper change (the second series in each existing benchmark result), not the older captured FoldingTextView reference. Timings were taken without concurrent build/test workloads. They establish lower construction/allocation cost, not a whole-app FPS increase. Full Telegram was not built.

Four isolated footprint runs alternate the original/native/native/original implementation, retaining 20,000 CALayers per process. The original path adds about 19.64 MB of physical footprint; the native path adds 8.42 MB. The difference is about 11.21 MB, or 561 bytes per layer in this fixture. This is not a measurement of whole-app memory savings. Tests independently verify that different layers share the immutable backing dictionary and that mutating one layer's actions does not affect another.

Five focused action tests cover exact keys/suppression, cancellation of existing animations, restoration of per-layer overrides, immutable storage sharing and independent mutations, subsequent explicit animations, and initialization on independent background layers. The storage-sharing assertions fail with the original helper and pass with the native implementation. The complete TGUIKit release and Address Sanitizer suites each pass 245 functional tests, with five opt-in benchmarks/profiling tests skipped. The chat mini-app release and Address Sanitizer suites each pass 114 functional tests, with 12 optional benchmarks skipped, including its existing native/layer pixel comparisons and lifecycle tests.

Complete before/after five-second stack samples are retained as gzip-compressed text, along with raw benchmark batches, footprint readings, test logs, the original Swift helper, and working-tree source hashes in results/layer-actions/. Large compiler logs are also gzip-compressed; their plain-text companions retain build completion and all test output. The original helper is from 8508a0686. To reproduce the before build, keep the benchmark/native helper available but restore the captured Swift helper body in a separate checkout; restore the current body for the after build. The production helper and its suppression behavior are compiled in both component and chat tests.

```sh
VIEW_CONSTRUCTION_BENCHMARK=1 swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release -c release --filter ViewConstructionTests/testConstructionCosts
LAYER_ACTIONS_MEMORY_MODE=legacy swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release -c release --skip-build --filter ViewConstructionTests/testRetainedActionStorage
LAYER_ACTIONS_MEMORY_MODE=native swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release -c release --skip-build --filter ViewConstructionTests/testRetainedActionStorage
```


## Deferred text media containers and immediate quote updates

Ordinary TextViews now create their embedded-media CALayer only when a caller requests it or attaches media. Layout, scale updates, spoiler visibility and mask updates no longer create an unused container. Once created, the public container keeps its identity for the view lifetime. Deferred masks snapshot their contents, frame, gravity and original copy scale at assignment time, preserving the previous behavior even if the source mask changes before media arrives. Late attachment preserves highlight/blur stacking and uses the current view bounds and backing scale. This removes one unused CALayer per ordinary text view; it does not remove an NSView.

FoldingTextView also creates its quote-mask CABasicAnimation only for an animated transition. Previously immediate updates constructed and discarded the animation. Animated transitions still take the original path.

Release medians in microseconds, using the second native-view series in the folding benchmark. The baseline is the committed final measurement from b9b0b9023 in results/layer-actions/; the after column is the repeat run. Baseline timings were not rerun for this batch.

| Operation | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| Construct one plain block | 23.315 | 22.563 | 3.2% |
| Construct one quote block | 37.039 | 33.993 | 8.2% |
| Construct three mixed blocks | 81.479 | 77.430 | 5.0% |
| Construct twelve mixed blocks | 267.881 | 251.406 | 6.2% |
| Rebind one quote block | 2.937 | 1.859 | 36.7% |
| Rebind three mixed blocks | 6.700 | 4.551 | 32.1% |
| Rebind twelve mixed blocks | 23.058 | 16.145 | 30.0% |
| Rebind 128 mixed blocks | 238.750 | 162.761 | 31.8% |

The first after run also reduced quote/mixed rebinding by 30–35%. Standalone TextView construction measured 10.704 → 10.122 microseconds (5.4%), and construction plus initial binding 12.096 → 11.485 (5.1%). Unchanged View/Control construction was about 2% faster in that run, so the small construction differences include measurement drift. These are premeasured, unattached, unrasterized component workloads including autorelease teardown, not whole-app FPS measurements.

Four isolated processes retain 10,000 TextViews each, comparing deferred containers against explicitly forcing eager containers in the new implementation. Physical-footprint increases were 48.58/48.61 MB with eager containers and 43.66/44.56 MB with deferred containers: about 4–5 MB less per 10,000 views in this fixture. Both modes include the new bookkeeping fields. This is not an old-binary comparison or a whole-app memory measurement.

Five functional tests cover absent-container updates, deferred mask snapshots, persistent container identity, late media scale, highlight/blur stacking, and exact pixels across nine scenarios at three scales. Separate captures from the actual before/after implementations match in all 27 cases with zero differing bytes, including Unicode, masking, selection, spoilers, highlight and blur transitions. Raw captures and dimensions are retained in pixels.tar.gz. Existing tests explicitly materialize the public container when testing its hierarchy.

The earlier Quartz ambiguity fix remains in place: TextViewLayer exposes isTextSelectable, while the non-CALayer text node retains its isSelectable API. The regression suite imports Quartz/ImageKit and tests both APIs. The focused import/folding run passes eight tests and compiles the exported FoldingTextQuoteLayer through the mini-app's InputTextView module.

The complete release and Address Sanitizer suites each pass 250 TGUIKit functional tests (seven opt-in tests skipped) and 114 chat mini-app functional tests (twelve opt-in tests skipped). Full Telegram was not built. The harness uses the production text and quote implementations with the documented media/context stand-ins. Results, original baseline measurements, source hashes and test logs are retained in results/text-container/.

```sh
TEXT_CONTAINER_CAPTURE_DIRECTORY=/tmp/text-container-capture swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release -c release --filter TextViewEmbeddedContainerTests/testCaptureRendering
TEXT_CONTAINER_MEMORY_MODE=lazy swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release -c release --skip-build --filter ViewConstructionTests/testRetainedTextContainers
TEXT_CONTAINER_MEMORY_MODE=eager swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release -c release --skip-build --filter ViewConstructionTests/testRetainedTextContainers
```


## Persistent chat-row interaction registration

ChatRowView used to remove and re-add its interaction observer on every binding. Both operations scan the observer list; removal also constructs a temporary list, and addition allocates a new weak wrapper. Rebinding N registered rows therefore performed quadratic observer work even when every row stayed in the same chat.

Rows now keep a weak reference to the interaction they actually observe. Rebinding within that interaction keeps the registration; changing interactions, receiving an invalid item, detaching from a window and destruction still unregister. Window attachment registers, and binding while detached retains the original behavior of registering until a subsequent detach callback. Repeated window callbacks no longer rescan an unchanged registration. This adds a weak field and a Boolean per row while eliminating temporary lists and weak-wrapper churn on unchanged bindings; retained whole-app memory was not measured.

Early binding originally suppressed interaction notifications by removing the observer. The retained registration now suppresses them through a preparation flag. Registration restores delivery even when a nested bind or window attachment occurs during preparation. Two extra regressions caught incorrect flag restoration in the initial candidate and pass with the final helper. The actual source is extracted for set(item:), notify, isEqual, viewDidMoveToWindow, deinit and the registration helper; both implementations use the real TGUIKit InterfaceObserver and AppKit NSView/window attachment. Rendering callbacks and Telegram item/state models are stand-ins. This measures observer work, not a complete ChatRowView render.

Nine functional tests cover repeated binding and duplicate prevention, changed chats, invalid items, detached binding, real window attachment/detachment, notification timing in superclass/preparation/fill phases, nested binding, attachment during preparation, weak lifetime cleanup and a 400-step mixed lifecycle comparison. The comparison probe sees 1,000 equality calls across 500 original rebindings and zero with the candidate. Every row still receives exactly one notification using its current message identity. Existing row notifications only update their own selection/layout; retaining registration also keeps their original registration order instead of moving a rebound row to the end of the observer list.

Release medians, microseconds per row rebind, nine alternating batches of 4,000 operations. Each row alternates between two prebuilt message items. The after implementation is compiled beside the captured 6a45ed29f methods in the same executable. The following is the repeat run:

| Registered rows | Before, same chat | After, same chat | Reduction |
| --- | ---: | ---: | ---: |
| 1 | 0.135 | 0.037 | 72.9% |
| 30 | 1.412 | 0.037 | 97.4% |
| 100 | 4.620 | 0.038 | 99.2% |
| 500 | 22.143 | 0.044 | 99.8% |

The first final run measured 4.108 → 0.039 microseconds at 100 rows and 20.783 → 0.043 at 500. Multiplying the repeat component measurements by the row count gives about 0.46 ms less observer work for a 100-row update and 11 ms for a 500-row update; these are extrapolations, not measured whole-screen latency or scrolling FPS.

Actual chat switching still scans both interaction lists. In the repeat control it measured 0.179 → 0.220 microseconds at one row, 0.794 → 0.910 at 30, 2.328 → 2.595 at 100 and 10.632 → 13.715 at 500. The first run also showed switching overhead, ranging from 0.03 to 2.12 microseconds per row. The retained-membership bookkeeping trades this cost for removing scans on ordinary updates within a chat. Both raw runs are retained rather than reporting only the favorable path.

The full release and Address Sanitizer mini-app suites each pass 123 functional tests, with 13 optional tests skipped. Full Telegram was not built. The production file passes Swift parsing, and the mini-app compiles the changed methods against the actual observer implementation. Source hashes, original reference methods, the initially failing reentrancy test log, final logs and raw timing batches are retained with observer-provenance.json and results/chat-observers/.

```sh
python3 tools/perflab/ChatLayerEngineLab/prepare.py
swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --filter ObserverTests
CHAT_OBSERVER_BENCHMARK=1 swift test --skip-build --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --filter ObserverTests/testRebindBenchmark
```


## Reuse native media-caption views

The live ChatRowView.fillCaption path now reserves unchanged captions before reusing idle text containers for edits or recycled media rows. Unchanged captions retain their selection and identity across album reordering. Changed content uses the existing FoldingTextView.updateForReusedContent checks and reset path; active presses, locked selection, animations, streaming and account changes retain view replacement. Animated replacements also keep the existing transition path. Unused captions are removed after reconciliation, and reused views receive their current caption frames.

Caption identity now includes message ID and account context as well as the short stable ID and text. Previously the same short ID/text pair could keep selection and a reveal callback bound to an old message, or reuse media across accounts. Tests reproduce the stale callback with the captured original. Callbacks now weakly read the current caption identity. Loading-state changes replace the small immutable caption wrapper while retaining the text view, keeping its public shim value current. This avoids changing the public immutable id/shim properties.

The harness extracts the complete production CaptionView and fillCaption declarations. The baseline is captured from 2e1e4125c and verified against Git. Both implementations use the current complete production FoldingTextView and real TGUIKit/AppKit. Telegram row/account/media models and caption placement are stand-ins. This is a native-caption component benchmark, not a full media-row or app build, and the separate layer-row engine remains inactive.

Release medians in microseconds per complete caption set, nine alternating batches of 300 updates with autorelease teardown. The table uses the isolated repeat run; quoted fixtures contain three mixed text/quote blocks per caption.

| Operation | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| Edit one plain caption | 27.420 | 3.340 | 87.8% |
| Edit one quoted caption | 84.207 | 9.947 | 88.2% |
| Edit three quoted captions | 250.583 | 29.564 | 88.2% |
| Edit ten quoted captions | 829.417 | 99.137 | 88.0% |
| Recycle one plain caption | 27.107 | 3.073 | 88.7% |
| Recycle ten quoted captions | 821.457 | 92.563 | 88.7% |
| Unchanged ten plain captions | 27.333 | 20.753 | 24.1% |
| Reorder ten quoted captions | 77.607 | 61.163 | 21.2% |

Across all repeat cases, edited/recycled caption updates improve about 88–89%, while unchanged updates and reordering improve 12–24% by avoiding repeated matching passes. Cold construction controls range from 0.6% faster to 3.6% slower. The first run has similar update gains; unrelated tests were observed during its build setup, so the repeat run is the primary evidence. Measurements are premeasured, unattached and unrasterized; they do not establish whole-app FPS or resident-memory savings. View identity tests verify that compatible updates avoid rebuilding the FoldingTextView and its text views.

Eleven functional caption tests cover edited/recycled identities and frames, reservation of unchanged album siblings, reorder callbacks, selection preservation/reset without changing old layout snapshots, account isolation, loading metadata, active/animated/streaming fallbacks, current-item callbacks, release of removed objects, ineligible sibling/account candidates, looping and one-shot emoji, spoiler visibility, and folded/expanded quotes. Twenty-four original/current PNG pairs are byte-identical across three scales, Unicode text, growth/shrink/removal, plain and quoted captions and reordering. Four further folded/expanded snapshot comparisons also have zero differing pixels. Nonempty comparisons assert nonblank text so empty renders cannot pass parity checks.

The full release and Address Sanitizer mini-app suites each pass 134 functional tests, with 14 optional tests skipped. The production file passes Swift parsing. Full Telegram was not built, and media decoding/network playback remains outside the stand-in harness. Raw captures, source provenance, both timing runs and validation logs are retained in results/caption-reuse/.

```sh
python3 tools/perflab/ChatLayerEngineLab/prepare.py
CAPTION_CAPTURE_DIRECTORY=/tmp/chat-caption-captures swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --filter CaptionReuseTests
CAPTION_REUSE_BENCHMARK=1 swift test --skip-build --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --filter CaptionReuseBenchmarkTests
```

## Search-result highlights in layer text

The layer text node and message-text adapter now support the temporary highlight used when jumping to a search result. The message API accepts the current FoldingTextLayout so it can translate a validated global UTF-16 range into block-local ranges without retaining another complete message layout. It checks that the supplied blocks are still the ones bound to the node before acting. Invalid explicit ranges follow the native substring-search fallback.

Highlights use the same TextViewLayout.generateBlock implementation, 0.5 opacity, three-second lifetime, and animated removal as TextView. They are layers rather than views or interactive nodes. Quote highlights share the quote's outer clipping. The collapsed text fade is intentionally not applied to the highlight: native TextView highlights remain solid while the text fades. The initial candidate incorrectly masked both; six exact pixel failures caught this, and the diagnostic log and image pair are retained under `results/highlights/`.

Replacing a highlight removes its predecessor immediately. Expiry checks layer identity so an older timer cannot remove a newer request. Message reuse, removal, or native fallback clears stale highlights through the existing reset/detachment paths. Active highlights retain an immutable attributed-text snapshot and measured size; changed text, attributes, or measured geometry invalidates them, including mutation of the same TextViewLayout object. Unchanged bindings keep the active highlight. Pending timers weakly reference the node and image layer.

The test harness extracts the actual FoldingTextView.highlight method for native block-range routing and uses actual TGUIKit TextView rendering. Its existing FoldingTextLayout stand-in now supplies attributed text and block ranges; quote wrappers and ViewLayout still come from production source. Nine new functional tests include 97 exact native/layer bitmap comparisons: 54 plain Unicode/range cases, 12 multi-block cases, 30 static/folded/expanded quote cases, and one separated-block range case. They also check unchanged selection, absence of extra interaction targets, replacement and missing matches, changed message identity, wrong-layout rejection, detachment, mutable text and geometry changes, timer replacement races, and weak lifetimes. The scene remains a single NSView.

An opt-in benchmark compiles the complete pre-highlight text node from `0d986d65f` under a reference name, then compares ordinary construction/binding and repeated updates without an active highlight. It also measures each node object's native malloc allocation. Each run uses nine paired alternating batches after warmup; a second run reverses the initial ordering. These measurements cover a text node, not a complete row, live scrolling, or the full application.

```sh
python3 tools/perflab/ChatLayerEngineLab/prepare.py
swift test --package-path tools/perflab/ChatLayerEngineLab -c release
swift test --package-path tools/perflab/ChatLayerEngineLab --sanitize address
swift test --package-path tools/perflab/ChatLayerEngineLab --sanitize thread --filter HighlightTests
CHAT_HIGHLIGHT_BENCHMARK=1 swift test --package-path tools/perflab/ChatLayerEngineLab -c release --filter HighlightBenchmarkTests
CHAT_HIGHLIGHT_BENCHMARK=1 CHAT_HIGHLIGHT_REVERSE=1 swift test --package-path tools/perflab/ChatLayerEngineLab -c release --filter HighlightBenchmarkTests
```

Save `/tmp/chat-highlight-benchmark.json` before each repeat. Use sequential builds and separate scratch paths. This closes a renderer capability gap; the engine is still not enabled in live ChatMessageView. Wiring real search navigation into the engine remains part of live-row integration.

Final highlight validation passed: 143 functional engine/lifecycle tests in release and Address Sanitizer (158 total, 15 opt-in tests skipped), all nine new tests under Thread Sanitizer, and both inactive-path benchmark orders. No sanitizer errors were reported. The two changed production files parsed successfully and match their compiled copies byte for byte; all 269 recorded inputs remained unchanged through final verification.

| Inactive path | Before, first / repeat | After, first / repeat |
|---|---:|---:|
| Construct and bind one text node | 2.129 / 2.184 µs | 2.169 / 2.119 µs |
| Update an existing text node | 0.2110 / 0.2110 µs | 0.2110 / 0.2120 µs |
| Node object's malloc allocation | 512 bytes | 512 bytes |

Construction varied slightly in opposite directions across the two orders; no speedup is claimed. The optional highlight reference fits within the same allocation bucket on this arm64 macOS 26.4 run. Active highlights allocate their image/state only when requested. This does not establish unchanged whole-row or whole-app memory. Final native and layer example PNGs are byte-identical and are preserved alongside the logs and hashes.

## Asynchronous menus for layer text

The text node now routes right-click and Control-click through the app's `ContextMenu` / `AppMenu` path. It supports the current text layout's asynchronous menu-items and top-window signals, link-specific copy labels and resolved URLs, attributed-text copying, node copy hooks, and translation actions. Copy actions capture their original selection and callbacks so reusing the node cannot redirect an older menu action to a replacement message. Nonselectable decorative labels remain outside hit testing; an explicit custom menu can opt nonselectable text into pointer handling.

Menu state is allocated on the first request. A versioned request owns its subscription and an immutable text snapshot while pending. Rebinding, interaction reset, removal from the scene, or moving the scene to another window cancels pending work. Delayed delivery also validates visibility, enabled state, copy permission, layout identity and text contents. Completion and cancellation release snapshots and subscriptions. Reentrant factories, subscription startup/disposal and menu-close callbacks cannot replace or cancel a newer request accidentally. Pending requests record the owning window identity and use the existing window notification to detect changes, avoiding another traversal of every node on row attachment. Key-window changes within the same window preserve a valid request.

`TextMenuTests` adds 29 functional tests. These include 12 comparisons with real native TextView menus across Latin, RTL and linked text, existing selections, default copying and custom actions. The tests cover delayed main-queue results, mutable layouts, weak lifetimes, protected content, right-click and Control-click routing, translation window ownership, detach/hide behavior, and older menu close actions. They intercept the final native popup call; they exercise the actual request, AppMenu routing and actions without opening an interactive menu during tests. Full custom-popup visual behavior and live ChatMessageView integration are not validated by this harness.

The first expanded checks caught pending requests surviving scene window removal and delayed menus on hidden rows. The first full run also caught decorative labels becoming hit targets after enabling menus too broadly. These failures are preserved in `results/text-menus/lifecycle-regression.log` and `hit-testing-regression.log.gz`. The candidate now requires explicit menu actions before making nonselectable plain labels interactive. Native parity test events also needed conversion to the same local coordinate in each renderer.

An opt-in benchmark compares the complete text node from `a98fe5c6d` against the candidate, without an active menu. Both runs use nine paired alternating batches; the repeat reverses the initial order. Construction medians were 2.145 → 2.086 µs and 2.069 → 1.993 µs. Rebinding was 0.230 → 0.225 µs and 0.197 → 0.199 µs. These small differences do not establish a speedup. Native allocation of the node object remained 512 bytes; this excludes any active menu, image data, layout or whole-row allocations. No additional NSView is created by the text-menu path.

```sh
CHAT_TEXT_MENU_BENCHMARK=1 swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --filter TextMenuBenchmarkTests
CHAT_TEXT_MENU_BENCHMARK=1 CHAT_TEXT_MENU_REVERSE=1 swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --filter TextMenuBenchmarkTests
```

Save `/tmp/chat-text-menu-benchmark.json` between runs. This closes another interaction gap in the layer engine; it does not enable the engine in production chat rows or measure live scrolling.

Final menu validation passes 172 functional tests in release and Address Sanitizer (188 total, 16 opt-in benchmarks skipped), and all 29 menu tests under Thread Sanitizer. The production source parses and matches the compiled copy byte for byte. All 272 recorded inputs remained unchanged through final verification. Raw logs, benchmark reports, the captured baseline, the production diff and validation metadata are in `results/text-menus/`.

## Reentrant text-node binding

A menu subscription's disposal, a code-header state callback, selection notification or link-hover callback can synchronously bind another message. Previously, the outer text-node update continued after that callback and overwrote the newer layout, frame, accessibility value or selection. Link exit also invoked its callback before clearing the old hover range, allowing nested updates to emit the same exit again. Link-type resolution or hover entry could bind another layout and then let the old cursor update continue.

The node now versions update/reset operations and checks that version after callbacks. Newer bindings retain their text, geometry and selection, including rebinding the same layout object with a different frame. Hover exit clears its state before calling out. Cursor handling checks the binding version and current hovered range after link resolution and hover callbacks. Selectability changes and detachment also stop cleanup when cancellation binds newer content. Boolean fields are grouped together; despite the additional generation counter, the measured native node allocation stays at 512 bytes.

Eleven regression tests reproduce these callback failures against the complete captured node from `7e69ec48e`: the final baseline run fails all 11 tests with 17 assertions, and the candidate passes. A twelfth test checks that detachment cleanup preserves a new binding and selection created during cancellation. The fixture dispatches a single pointer event for callback-cursor checks and uses a unique cursor supplied by the callback. This matters because normal scene routing can legitimately emit entry followed by movement, and system cursor images are not a reliable identity test in the headless harness. The baseline is compiled only into the lab's generated directory for the negative run; `prepare.py` restores the unchanged production source before candidate validation.

The inactive-path benchmark compares the full previous node with the candidate using nine alternating paired batches and a second run in reverse order. Construction medians are 1.945 → 1.932 µs and 1.952 → 1.958 µs. Rebinding medians are 0.197 → 0.195 µs and 0.184 → 0.186 µs. The differences change direction between runs and do not establish a speedup or a meaningful regression. Node allocation is 512 → 512 bytes in both runs. These are text-node measurements, not complete-row memory or live scrolling measurements.

```sh
CHAT_REENTRANCY_BENCHMARK=1 swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --filter TextReentrancyBenchmarkTests
CHAT_REENTRANCY_BENCHMARK=1 CHAT_REENTRANCY_REVERSE=1 swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --filter TextReentrancyBenchmarkTests
```

Save `/tmp/chat-reentrancy-benchmark.json` between runs. Evidence is in `results/text-reentrancy/`. This validates the text node's callback handling; the layer engine is still not enabled in live ChatMessageView.

Final reentrancy validation passes 184 functional tests in release and Address Sanitizer (201 total, 17 opt-in benchmarks skipped). Thread Sanitizer passes all 41 menu and reentrancy tests. The production file parses and matches its compiled copy byte for byte; all 275 recorded inputs remained unchanged through final verification.

## Message-level binding and block removal

Text-node guards alone did not protect a multi-block message. A callback from cancelling one block could bind a newer message, after which the outer message update overwrote sibling layouts, frames, selection or the child list. Removing a block could also trigger cancellation while the old hierarchy mutation was still in progress. Eight new adapter tests reproduce these failures against `8f78986bf`; all eight fail with 52 assertions on the captured baseline.

The message adapter now versions its binding operations. Removed blocks reset before hierarchy mutation, and the adapter checks for a newer binding after callbacks. Retained blocks reset within the binding loop only when needed. Newly constructed blocks skip a redundant reset. A precomputed reset boundary replaces repeated per-block conditions. The adapter publishes the attached block list and current message identity before invoking block update callbacks, and stops an older binding when a callback supersedes it. `update` returns false for a superseded request as well as for unsupported content; a future live-row caller must validate its own current binding before choosing a native fallback.

The regression tests exercise retained and removed block menus, growing/shrinking messages, supported/native fallback transitions in both directions, same-message hover exit, selection notifications, code-header callbacks and selectability changes. They check every resulting block's layout and frame, parent and scene ownership, actual layer parent, scene lookup and subsequent selection preservation for the newest message identity. The final implementation passes these tests and the existing rendering, hit testing, folding and selection suite.

Three complete adapter variants are compiled for the benchmark: the previous implementation, an initial candidate that resets every retained block in a separate pass, and the final candidate. The initial candidate also passed the eight targeted regressions. The final candidate keeps retained resets in the normal loop to avoid an additional traversal during message reuse. A common generic timing loop runs every variant, with mode selection outside the measured loop. Each run uses nine rotated paired batches, and the repeat reverses their order. No other Swift build was active when the final benchmarks started. Text measurement is outside the timed region; this is prepared-message binding and layer construction, not full-row rendering or scrolling.

| Operation / blocks | Baseline → candidate, first (µs) | Baseline → candidate, repeat (µs) |
| --- | ---: | ---: |
| Construct / 1 | 3.745 → 3.672 | 3.863 → 3.921 |
| Update / 1 | 0.330 → 0.339 | 0.364 → 0.392 |
| Reuse / 1 | 0.344 → 0.354 | 0.376 → 0.385 |
| Construct / 3 | 9.597 → 9.610 | 9.692 → 9.443 |
| Update / 3 | 0.637 → 0.643 | 0.635 → 0.639 |
| Reuse / 3 | 0.702 → 0.699 | 0.714 → 0.718 |
| Construct / 12 | 35.745 → 35.331 | 35.635 → 35.818 |
| Update / 12 | 1.991 → 1.956 | 2.033 → 1.944 |
| Reuse / 12 | 2.243 → 2.188 | 2.289 → 2.232 |

Single-block updates/reuse have roughly 9–28 ns of overhead in these runs. Twelve-block update/reuse timings are slightly lower; construction results vary. These results do not establish an overall app speedup. The message-node object's native allocation remains 384 bytes for all three variants, excluding its children and text/media data. Complete per-batch results include the initial candidate. Historical `before-boundary-*` reports used the earlier benchmark with per-iteration mode branches; final reports use the common generic loop.

```sh
CHAT_MESSAGE_BINDING_BENCHMARK=1 swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --filter MessageBindingBenchmarkTests
CHAT_MESSAGE_BINDING_BENCHMARK=1 CHAT_MESSAGE_BINDING_REVERSE=1 swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --filter MessageBindingBenchmarkTests
```

Save `/tmp/chat-message-binding-benchmark.json` between runs. Evidence, the original and initial-candidate sources, and the production diff are in `results/message-binding/`. This validates the message adapter; the layer engine remains inactive in live ChatMessageView.

Final message-binding validation passes 192 functional tests in release and Address Sanitizer (210 total, 18 opt-in benchmarks skipped), plus 49 callback/menu tests under Thread Sanitizer. The production source parses and matches its compiled copy byte for byte; all 280 recorded inputs remained unchanged through final verification.

## Embedded text selection in ordinary chat rows

The live ChatSelectText drag loop and double-click focus restoration now use ChatTextSelectionSource. ChatRowView provides its existing native view array without creating another mapped array. A row can override textSelectionSources with native captions, layer text, and native webpage text in their original order. The native range calculation, clipping-parent geometry, cursor alignment, selection headers, and copy ordering are preserved. Layer fragments use the existing SelectManager bubble storage with a weak reference to their scene. The scene must register those nodes in selectableTextNodeIds so clearing cross-row selection reaches each node once.

The new seven-test suite exercises 1,024 comparisons against the captured pre-change selection loop, using nested layer origins, three fragments per row, mixed renderers, both table orders and drag directions, clipped blocks, author headers, attributed text, emoji, combining marks, and RTL text. It also covers repeated offscreen restoration and shrinking, focus restoration to a later embedded node, hidden/disabled/protected/removed nodes, callback rebinding, and scene release. The captured loop omits an embedded layer body in an otherwise ordinary row; the shared loop includes it between its native fragments. The first full run exposed an incorrect test expectation that a single-row drag selected all fragments; the baseline demonstration now spans complete middle-row fragments, and the production selection rules remain unchanged. That diagnostic log is retained as initial-release.log.

Release benchmark medians in microseconds per drag update (three fragments per row):

| Rows | Original native | Shared native | One layer fragment per row | All layer fragments |
| --- | ---: | ---: | ---: | ---: |
| 1, first / repeat | 3.239 / 3.212 | 3.351 / 3.313 | 4.121 / 4.270 | 5.421 / 5.277 |
| 16, first / repeat | 85.172 / 89.003 | 87.679 / 89.282 | 86.738 / 88.499 | 130.734 / 132.795 |
| 64, first / repeat | 805.151 / 822.277 | 811.790 / 823.002 | 594.423 / 601.696 | 1071.995 / 1091.573 |

The native path adds about 0.10–0.11 microseconds for one row. All-layer selection is costlier in this fixture, especially with many separate fragments; this bridge does not establish a selection speedup. It enables mixed rendering while preserving native selection behavior. These timings include range calculation, geometry conversion, and selection-manager updates; they exclude rendering, event dispatch, and full-app scrolling. Both implementations use the current SelectManager, with nine rotating batches and reversed order in the repeat run.

Run the focused checks and optional benchmark with:

```sh
python3 tools/perflab/ChatLayerEngineLab/prepare.py
swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --filter EmbeddedTextSelectionTests
CHAT_EMBEDDED_SELECTION_BENCHMARK=1 swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --filter EmbeddedSelectionBenchmarkTests
```

Evidence is in results/embedded-selection. The complete suite passes 199 functional tests in release and Address Sanitizer (218 total, 19 optional benchmarks skipped). This compiles the production selection source unchanged and the actual live runSelector method with a stand-in table, row, and account model. It does not compile or exercise the full Telegram app. Ordinary ChatMessageView bodies still use native FoldingTextView; connecting their rendering and send-animation baseline is the next integration step.

Final embedded-selection verification also passes 34 focused tests under Thread Sanitizer. All 286 recorded inputs remained unchanged through validation, the shared source matches its compiled copy byte for byte, and the live selector method is compiled unchanged. The three changed production files pass Swift syntax parsing.


## Live plain-message text integration

ChatMessageView now binds supported plain text to ChatLayerMessageTextView. Its message body is the scene root, avoiding an extra node and backing layer. Single-block text uses one NSView instead of FoldingTextView plus TextView. Three and twelve plain blocks use one view instead of four and thirteen. These counts exclude the surrounding ChatRowView and its other controls.

The live row routes selection, search highlighting, click geometry, layout transitions, and the send animation's first text baseline to the current renderer. The existing native binding remains for links, quotes/folding, custom emoji, spoilers, formatted dates, block backgrounds, streaming, and unsupported/empty content. A selected or animating native view stays native until it can migrate safely. Eligibility is checked from current layout and attributed-text data, including in-place attribute mutations; it is not cached by layout identity.

Same-message layout replacement preserves explicit selections and active plain-text selection gestures when the text and geometry remain compatible. Message/account changes cancel old interactions. Binding versions prevent callbacks from a disappearing renderer from overwriting a newer row binding. The host retains its old frame during animated updates so the row's layout transition can animate it. Its layer does not clip ordinary glyph overhang, matching FoldingTextView; the first rendering tests found clipped Arabic descenders before this was corrected.

The sixteen live-binding tests compile the production updateText, updateNativeText, firstTextBaseline, selectableTextViews, and textSelectionSources methods. They cover native/layer transitions, mutable attributes, account changes, explicit and external selections, active drag continuation, callback and pending-menu cancellation, animated frame updates, source ordering with native captions/webpage text through the actual shared selector, baseline conversion, a click-geometry grid, and twelve exact native-versus-layer bitmap pairs across scales, languages, emoji, and block counts. The scene and host sources are copied unchanged. The plain-text preparation method and its attribute helpers compile directly against the real native FoldingTextLayout in the harness. An earlier adapter converted that layout through a stand-in object and distorted timings; initial-benchmark results are retained only as diagnostics and are not the final comparison.

Final release benchmark medians, in microseconds per binding; each cell shows first / reversed-order repeat:

| Operation | Blocks | Previous native implementation | Live layer implementation |
| --- | ---: | ---: | ---: |
| Construction | 1 | 27.619 / 27.436 | 21.996 / 22.021 |
| Construction | 3 | 51.602 / 50.991 | 31.053 / 31.680 |
| Construction | 12 | 153.243 / 151.236 | 72.284 / 72.130 |
| Same-message update | 1 | 1.720 / 1.775 | 1.657 / 1.693 |
| Same-message update | 3 | 4.280 / 4.238 | 3.934 / 3.960 |
| Same-message update | 12 | 15.477 / 14.736 | 14.398 / 13.774 |
| Different-message reuse | 1 | 2.503 / 2.524 | 2.541 / 2.518 |
| Different-message reuse | 3 | 5.195 / 5.183 | 5.071 / 5.071 |
| Different-message reuse | 12 | 17.103 / 16.910 | 15.491 / 16.382 |

Single-block construction improves about 20%; three-block construction improves 38–40%; twelve-block construction improves 52–53%. Single-block reuse is essentially unchanged in these runs (38 ns slower in the first, 6 ns faster in the repeat). Quote fallback remains native and has an eligibility-check cost: one-block same-message updates increase from 2.533 / 2.297 to 2.660 / 2.453 microseconds, and reuse increases from 4.102 / 3.984 to 4.426 / 4.167 microseconds. All quote and plain samples are retained; no claim of a universal speedup is made.

For 3,000 retained single-block text rows, median incremental physical footprint is 32,342,016 bytes native versus 28,000,256 bytes layered (30.84 versus 26.70 MiB), a 13.4% reduction. This uses five fresh processes per implementation, alternating order, with unique layouts measured before the memory baseline and both constructors warmed. Layer hit indexes are initialized. Rows are retained but unattached and unrasterized. The measurement includes the harness row object and text renderer, excludes other ChatRowView controls, and does not measure whole-app memory, text measurement, media, backing-store memory, chat opening, or scroll FPS. Earlier before-owned-root samples show the smaller gain before removing the redundant scene root.

Run the live checks and optional measurements with:

```sh
python3 tools/perflab/ChatLayerEngineLab/prepare.py
swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --filter LiveChatTextBindingTests
CHAT_LIVE_TEXT_BENCHMARK=1 swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --filter LiveChatTextBenchmarkTests.testLiveTextBindingCosts
CHAT_LIVE_TEXT_MEMORY=native swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --filter LiveChatTextBenchmarkTests.testRetainedLiveTextMemory
CHAT_LIVE_TEXT_MEMORY=layers swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --filter LiveChatTextBenchmarkTests.testRetainedLiveTextMemory
```

Evidence is in results/live-text. The full Telegram app has not been built or exercised in this pass. The live binding methods are tested with real TGUIKit, native FoldingTextView, and layer rendering, but account/media dependencies and the enclosing chat row are stand-ins. Baseline conversion is validated; the complete send-flight animation in an actual chat remains an app-level check. Rich-text behavior and the remaining row controls still require migration before full layer-based ChatRowView support.

Final live-text validation passes 215 functional tests in release and Address Sanitizer (236 total, 21 optional benchmarks skipped), plus 109 focused tests under Thread Sanitizer. All 295 recorded inputs remained unchanged. The five engine/host sources match their compiled copies byte for byte, the actual live binding/selection/baseline methods and plain-text preparation compile unchanged, and all seven changed production files pass Swift syntax parsing.

## Live linked-message text integration

ChatMessageView now uses the layer renderer for simple text containing links as well as plain text. Quotes/folding, embedded emoji, spoilers, formatted dates, streaming, block backgrounds, and unsupported content retain the native path. The preparation method is named simpleText and detects links during its existing attribute scan.

ChatLayerTextLinkState supplies native tooltip geometry, decoded/truncated tooltip text, delayed link previews, and a snapshot of pressed link text. It is allocated only when a node needs tooltip, preview, or link-press state. Preview timers and subscriptions cancel on replacement, hiding, disabling, detachment, window changes, and pointer exit. Same-URL occurrences retain the native preview behavior. Cancellation clears ownership before calling external disposables, and generation checks protect reentrant replacement. A changed URL cannot activate from an older mouse press, including in-place attributed-string changes. Link clicks also register the native modal-morph source using the link rectangle converted to the host view.

TGUIKit exposes its existing measured tooltip rectangles read-only. The layer host uses these exact rectangles rather than repeating CoreText measurement. Tooltip registration caches the source rectangles and scene geometry generation; unchanged updates skip coordinate conversion and AppKit registration. Movement, ancestor transforms, and remeasurement invalidate the cache. External removeAllToolTips stays respected during pointer movement and ordinary layout; the next explicit text update restores managed tooltips, matching the native update contract.

Four live-binding tests cover plain/link/quote transitions, mutable link attributes, message reuse with active previews/presses, baselines, and 24 exact native-versus-layer bitmap comparisons (48 rendered images) across two scales, one/three blocks, selected/unselected text, Arabic, Latin, and emoji. Fourteen lower-level link tests compare native hover timing and cancellation, value links, same/different URLs, reentrant previews, subscription release, tooltip geometry/removal, stationary-pointer movement, and stale presses. The pre-existing text, menu, selection, and rendering suites remain enabled.

Final linked-text benchmark medians in microseconds per binding, first / reversed-order repeat:

| Operation | Blocks | Previous native | Live layers |
| --- | ---: | ---: | ---: |
| Construction | 1 | 30.609 / 30.522 | 25.903 / 25.852 |
| Construction | 3 | 60.932 / 60.519 | 37.661 / 38.462 |
| Construction | 12 | 184.439 / 184.258 | 88.728 / 94.529 |
| Same-message update | 1 | 1.768 / 1.786 | 1.868 / 1.908 |
| Same-message update | 3 | 4.307 / 4.813 | 4.551 / 4.683 |
| Same-message update | 12 | 14.795 / 18.754 | 16.356 / 20.179 |
| Different-message reuse | 1 | 2.481 / 2.518 | 2.853 / 2.861 |
| Different-message reuse | 3 | 5.243 / 5.341 | 5.881 / 6.059 |
| Different-message reuse | 12 | 17.152 / 17.312 | 19.625 / 19.306 |

Construction improves about 15% for one block, 36–38% for three, and 49–52% for twelve. Reuse is not universally faster: linked single-block reuse costs another 0.34–0.37 microseconds (14–15%), and twelve-block reuse costs another 1.99–2.47 microseconds (12–14%). Same-message updates have smaller overhead in these fixtures. Plain-text construction remains about 19% faster for one block in the first final run. All plain and quote-fallback samples are retained alongside linked samples. Initial results before tooltip geometry caching and the inactive-preview fast path are diagnostic only.

The mini-app compiles the live binding methods, the real native FoldingTextView, and unchanged copies of the production layer engine. Account/media dependencies and the enclosing row are stand-ins. These measurements exclude text measurement, media, full chat opening and scrolling, and do not establish whole-app frame-rate improvements. The app-level link-preview menu placement and modal-morph animation still need verification in an actual chat.

Evidence is in results/linked-text. Run the existing LiveChatTextBenchmarkTests for all three content variants. Set CHAT_LIVE_TEXT_LINKED=1 together with CHAT_LIVE_TEXT_MEMORY=native or layers to measure retained linked-text rows in a fresh process.

Five fresh processes per content/renderer combination, with alternating native/layer order, measure the following median incremental physical footprint for 3,000 retained rows:

| Content | Previous native | Live layers | Reduction |
| --- | ---: | ---: | ---: |
| Plain | 32,276,480 bytes | 28,000,256 bytes | 13.2% |
| Linked, with tooltips | 33,734,656 bytes | 30,212,096 bytes | 10.4% |

Layouts are unique and premeasured before the baseline; both constructors are warmed. The fixture retains the row object, renderer, and initialized hit index, without attaching/rasterizing the rows. This excludes the other ChatRowView controls, media, text-measurement allocations, and backing stores. Linked fixtures exercise actual AppKit tooltip registration. Raw per-process values and logs are retained rather than treating a single allocator sample as definitive.

Final validation passes 233 functional tests in release and Address Sanitizer (254 total, 21 optional measurements skipped), 131 focused tests under Thread Sanitizer, and 371 native TGUIKit tests (389 total, 18 optional measurements skipped). All 374 recorded inputs remained unchanged, five production engine sources match their compiled copies byte for byte, nine live binding/preparation declarations compile unchanged, and seven changed production files pass Swift syntax parsing. No full-app build or interactive chat validation was performed.


## Shared row host and forwarded headers

The existing ChatRowView row container now uses a deferred ChatLayerRowView. The first live consumer is the passive forwarded-message header: its TextView is replaced by a ChatLayerTextNode without adding another NSView. Sender names, forwarded-name links, badges, replies and media controls remain native. The host allocates scene state only when content is added, releases empty state after the final removal animation, and preserves explicitly owned body roots. Native children remain in the accessibility tree and keep their normal mouse routing. Interactive overlapping native/layer children still need explicit routing before broader migration.

Visible scenes retain their inVisibleRect tracking area across layout/resize. Unattached scenes allocate no tracking area. Tests cover reactivation, observer cleanup, input cancellation callbacks that create new content, removal followed by immediate reuse, animated geometry and root lifetimes. The header root draws above native backing layers. The bitmap helper now sorts layers by depth for CALayer.render and restores their original order afterward; an independent overlapping-color test validates this snapshot behavior. Eighteen exact native/header bitmap pairs cover two scales, three languages/text variants and three colors with native backgrounds.

A separate native badge bug is fixed: reuse from an interactive admin badge to a passive badge clears the previous click handler, pressed state, scale-on-click and interaction flag. The regression fixture compiles the actual old/current binding blocks, demonstrates the stale action in the old implementation and verifies restoration for a later interactive author.

Release median microseconds, native / current, nine alternating batches per run:

| Operation | First run | Reverse-order repeat |
| --- | ---: | ---: |
| Construct without header | 15.016 / 15.093 | 15.046 / 15.160 |
| Construct with header | 27.378 / 23.056 | 26.957 / 22.862 |
| Update existing header | 1.019 / 0.715 | 1.091 / 0.735 |
| Toggle header | 5.866 / 4.078 | 5.892 / 4.128 |
| Bind absent header | 0.0718 / 0.0752 | 0.0734 / 0.0755 |

Header construction improves 15–16%, updates 30–33%, and toggling about 30%. Empty-host construction increases 0.5–0.8%; an absent-header bind adds 2–4 ns. The host instance grows from 912 to 928 bytes. Five fresh processes per implementation and presence state retain 5,000 rows after unique layouts are prepared: median incremental physical footprint is 52,330,544 bytes native versus 45,367,344 bytes layered with headers (13.3% lower). Without headers it is 28,999,704 versus 29,179,928 bytes (0.6% higher). This fixture includes an outer row and its existing container, not the complete chat row, media, text measurement, rasterization or display surfaces. These are not whole-app memory or scrolling measurements.

The header harness extracts the production fillForwardHeader and placement code, checks the actual row-container initializer, and compares against commit 778589c29. It uses scalar item/account stand-ins. Final release and Address Sanitizer each pass 247 functional tests (270 total, 23 optional measurements skipped); focused Thread Sanitizer passes 145. All 381 frozen inputs remained unchanged; the three engine source copies match byte for byte, the extracted binding code matches the staged source, and all four changed production sources pass Swift syntax parsing. The full Telegram app has not been built or manually exercised in this pass.

Evidence is in results/shared-header. Files in before-cleanup are diagnostic runs before empty-state release and tracking-area reuse. The final benchmark and memory files are in the directory root. Run CHAT_HEADER_BENCHMARK=1 with RowHeaderBenchmarkTests, optionally CHAT_HEADER_REVERSE=1 for the reverse-order repeat; use CHAT_HEADER_MEMORY=native or layers and CHAT_HEADER_PRESENT=0 or 1 for fresh-process memory probes. Preserve each /tmp/chat-header result before the next process.


## Deferred scene cleanup during callbacks

A regression test against 489ec8d18 reproduced a process trap when a hover callback released an empty deferred scene. The older dispatcher continued reading its force-unwrapped state after the callback returned. Dispatch operations now retain the current state identity and stop when a callback releases or replaces it. Event coordinate conversion no longer creates a root while handling a detached node. Focus, input validation, window callbacks, layout hover updates and context-menu dispatch apply the same lifetime checks. An event consumed by a removed scene cannot capture a new scene or bubble into its controls.

Ten regression tests cover hover release, down callbacks with and without replacement, focus-loss cleanup, custom hit regions, window deactivation, layout-driven hover exits, removing the final child, invalid capture cancellation, preservation of replacement hover state, and discarding a menu returned by a released scene. Existing input, selection and rendering tests remain enabled. Final release and debug Address Sanitizer each pass 257 functional tests (280 total, 23 optional measurements skipped); 73 focused debug Thread Sanitizer tests pass. All 382 compiler inputs stayed unchanged, the copied scene source matches production byte for byte, and Swift syntax parsing passes.

A fresh nine-batch alternating header benchmark retains the gains: native/current construction with a header is 25.825/21.607 µs, updates are 0.984/0.660 µs, and toggling is 5.497/3.824 µs. Empty-host construction is 14.386/14.289 µs and absent-header binding is 0.0700/0.0734 µs. These compare native and current fixtures in this run; they do not isolate the cost of the new lifetime checks or measure full-app scrolling. No object fields were added. Full-app interaction and memory measurements remain outstanding.

Evidence, including the baseline crash log, before/after source snapshots, passing logs and raw measurements, is in results/deferred-dispatch. Interactive sender-name and forwarded-name migration still requires native/layer click priority, full-label tooltip support, and row shake-animation integration.


## Live sender-name layers

ChatRowView now renders ordinary sender names with ChatLayerTextNode in its existing ChatLayerRowView. The separate native bubble accessory remains for messages without a bubble, and badges retain their existing controls. One TextView is removed from each ordinary sender-name row. The production binding, placement, background update and complete shake method are extracted into the sender harness; only account/model and unrelated accessory types are stand-ins.

The row host gives a layer link priority over the bubble background while preserving native foreground controls, native cursors and accessibility hit targets. A full-label tooltip uses the text node's lazy link state, so other text nodes gain no stored field. Names preserve value/string link dispatch, preview cancellation, tooltip replacement, and native context-menu fallback. A binding generation prevents a preview disposal callback's newer name/tooltip from being overwritten by the older request. Animated removal releases empty scene state after the final visual layer disappears.

Sender text temporarily joins the actual bubble layer during shake, then returns to the scene. Layout converts coordinates while borrowed; removal/rebinding cannot resurrect the old node. The initial separate-pivot implementation failed transformed bitmap comparison because the native backing-layer geometry changed during synchronization. Sharing the native animation container passes four transformed comparisons at two scales and two angles. Snapshot tests can now keep an existing window attached while inspecting animations. Eighteen ordinary sender bitmap pairs match exactly across two scales, three languages/text variants and three backgrounds.

Release median microseconds, native / current, nine alternating batches per run:

| Operation | First run | Reverse-order repeat |
| --- | ---: | ---: |
| Construct without sender | 38.968 / 39.298 | 39.225 / 39.884 |
| Construct with linked sender | 49.710 / 47.045 | 50.288 / 47.337 |
| Update sender | 1.236 / 1.000 | 1.208 / 1.010 |
| Remove/recreate sender | 5.619 / 4.264 | 5.573 / 4.266 |
| Bind absent sender | 0.2125 / 0.2112 | 0.2193 / 0.2178 |

The fixture includes the outer row, existing container, bubble and content views. Sender construction improves 5–6%, updates 16–19%, and toggling 23–24%; empty-row construction costs another 0.8–1.7%. Five fresh processes per mode/presence retain 5,000 rows with unique premeasured layouts. Median incremental physical footprint with names is 97,435,720 bytes native versus 91,177,032 bytes layered (6.4% lower). Empty fixtures measure 75,366,448 versus 75,350,064 bytes, effectively unchanged within process/allocator variation. Rows are unattached and unrasterized; account/media work, text measurement, backing surfaces and the remaining controls are excluded. Raw benchmark keys retain the header fixture's presence naming but these files instantiate SenderBindingRow.

The general text-binding benchmark still shows construction gains: one plain block measures 28.300/22.914 µs and one linked block 31.567/26.734 µs. Reuse remains a tradeoff: corresponding one-block reuse measures 2.513/2.660 µs and 2.617/2.882 µs. These compare native/current implementations, not an isolated before/after measurement of this patch, and do not establish a whole-app speedup.

Evidence is in results/sender-name, including the initial failing shake diagnostics, final source snapshots, raw timing/memory samples and sanitizer logs. The full Telegram app has not been built or manually exercised in this pass; real chat preview placement and complete scrolling/transition behavior still need app-level verification.

Final sender validation passes 266 functional tests in release and debug Address Sanitizer (291 total, 25 optional measurements skipped), plus 80 focused debug Thread Sanitizer tests. Nine new functional tests cover sender binding, native control/cursor/accessibility priority, tooltip geometry/lifetime, preview disposal reentrancy, fade cleanup, shake geometry, transformed rendering and reuse during animation. All 386 frozen inputs remained unchanged; four engine copies match production, the staged binding/placement/colors/shake code matches the compiled fixture, and all five changed production sources pass Swift syntax parsing.


## Shared row pointer routing and stable hover

ChatLayerRowView now checks the existing layer hit index before traversing native child views. A point outside all visible layer target bounds skips native traversal; a possible target still gives native foreground controls priority and runs precise layer hit testing afterward. Custom hit regions remain eligible outside their rectangular bounds and run once, after native hit testing. Rounded clipping and transforms remain part of the precise lookup. No additional object fields or retained caches are introduced.

Stable hover compares the existing ancestry with the current target without constructing another path array. Cursor lookup stops at the first cursor instead of building a filtered array. A generation check also fixes a reproduced reentrancy bug: when a custom hit-region callback cleared hover, the old dispatcher could publish a stale hover path, then send an exit without an enter.

Ten new functional tests cover native traversal counts, 34,880 before/current grid comparisons, native-control priority, offset coordinates, transformed and rounded targets, custom hit regions, cursor inheritance, reparenting, capture/event traces, and native callbacks that remove, move, hide, disable or replace the current target. A scene replacement test deliberately repeats the old geometry version to catch stale identity reuse. The first candidate cached the exact target across native callbacks and lost replacement hits; a subsequent double-lookup candidate fixed correctness but added roughly 23% to direct-name lookup in diagnostic measurements. The final bounds filter retains one precise lookup. Diagnostic attempts are kept separately from final evidence.

The routing reference captures the complete scene from 8be40ed65 with type renaming, plus the old row hitNode, hitTest and cursor methods. Unused text-tooltip and selection dependencies are stand-ins. The benchmark uses generic interactive nodes and real native Views, including 24 sibling controls and a background; it excludes text rendering, media, layout measurement, rasterization and full ChatRowView construction. These results cannot establish whole-app scrolling speed or memory savings.

Run CHAT_ROUTING_BENCHMARK=1 with RowRoutingTests.testRoutingBenchmarks in release, optionally CHAT_ROUTING_REVERSE=1. Each run measures nine alternating batches of 10,000 operations after warming both implementations. Preserve /tmp/chat-routing-benchmark.json before the next run. Evidence is in results/row-routing; initial-candidate and double-lookup contain superseded experiments.

Final release medians in microseconds per operation, previous / current:

| Operation | First run | Reverse-order repeat |
| --- | ---: | ---: |
| Direct target lookup | 0.9345 / 0.9768 | 0.8821 / 0.9332 |
| Lookup over body without a layer target | 0.6903 / 0.0266 | 0.6324 / 0.0273 |
| Lookup outside row | 0.0394 / 0.0146 | 0.0358 / 0.0154 |
| Pointer movement over target | 3.6805 / 3.4008 | 3.5249 / 3.2711 |
| Pointer movement over body | 2.2855 / 0.9712 | 2.1439 / 0.9051 |
| Pointer movement outside row | 0.3815 / 0.3142 | 0.3767 / 0.3077 |

Body misses avoid 25 native hit-test calls in the counted fixture and improve about 96%. Pointer movement improves 57–58% over the body, 7–8% over the target and 18% outside the row. Direct target lookup costs an additional 0.04–0.05 µs (4.5–5.8%) because of the preliminary bounds check; full movement over that target still improves through stable-hover allocation avoidance. No other Swift/Xcode compiler or test processes were observed immediately before or after either final run. The syntax-overlap directory retains an earlier measurement excluded because a separate syntax-only parse briefly overlapped its driver. Diagnostic double-lookup runs also overlapped an unrelated build. These are local microbenchmarks, not isolated hardware measurements or full-app scrolling results.

Final release and debug Address Sanitizer each pass 276 functional tests (302 total, 26 optional measurements skipped). Focused debug Thread Sanitizer passes 78 functional tests (79 total, one optional benchmark skipped). All 388 recorded compiler inputs remained unchanged; both changed engine files match their compiled copies and pass Swift syntax parsing. The full Telegram app has not been built or interactively validated in this pass.


## Live forwarded-name layers

ChatRowView now renders ordinary forwarded names in the existing ChatLayerRowView, removing one TextView per forwarded-name row. The native no-bubble accessory and avatar remain. The avatar keeps native hit priority and draws above the opaque text background. Sender/header nodes survive independent forwarded-name removal. Layer names share the existing bubble animation container during shake and return to their original geometry afterward.

The hidden-sender tooltip uses a rectangle in the host's coordinates. During shake, conversion uses the native bubble view to preserve flipped coordinates. A generic TGUIKit dismissal function removes only a tooltip anchored to the specified view, preserving the old label-removal behavior without retaining a permanent tooltip-anchor NSView. Preview disposal can synchronously bind a newer row; the forwarded binding reports supersession so the older caller stops before deleting the newer avatar or creating a stale accessory. Initial failing rebind and shake-tooltip logs are retained.

The harness extracts the production fillForward, layout placement, background assignment, tooltip method and complete shake method. The previous row host is captured from e2ae34ce8 with only its class renamed, so the comparison includes the new host's stored fields. Account/message models, the avatar's peer-loading behavior, unrelated row controls and the no-bubble accessory are stand-ins; the avatar fixture is a real native Control with a colored circular backing layer. Tooltip-anchor assertions capture the production call arguments, and a separate test exercises actual TGUIKit tooltip creation and dismissal.

Ten new functional tests cover binding/reuse, avatar actions, text links and pressed-link cancellation, callback reentrancy, hidden-name tooltip coordinates and ownership, sender/header coexistence, animated removal, shake cleanup and transformed rendering. Thirty-six static bitmap pairs match exactly across two scales, three language/length variants, three backgrounds and avatar presence. Four shake comparisons with an avatar match within two channel values, using the same tolerance as the existing sender shake tests.

Release medians in microseconds, previous native / current layers. The short linked labels are premeasured before timing. Construction includes the fixture's outer row, existing container, bubble and content views; other operations bind only the forwarded-name portion.

| Operation | First run | Reverse-order repeat |
| --- | ---: | ---: |
| Construct empty, avatar False | 41.5475 / 41.2073 | 38.2069 / 38.1767 |
| Construct forwarded name, avatar False | 51.7396 / 46.7864 | 48.8405 / 45.5878 |
| Update forwarded name, avatar False | 1.2200 / 1.0212 | 1.1263 / 0.9332 |
| Remove/recreate forwarded name, avatar False | 5.7376 / 4.3717 | 5.2142 / 3.9479 |
| Bind absent name, avatar False | 0.1924 / 0.1935 | 0.1883 / 0.1937 |
| Construct empty, avatar True | 38.6065 / 38.9296 | 37.9716 / 38.2737 |
| Construct forwarded name, avatar True | 69.4979 / 66.6902 | 69.7757 / 66.6601 |
| Update forwarded name, avatar True | 1.3686 / 1.1175 | 1.2924 / 1.0847 |
| Remove/recreate forwarded name, avatar True | 16.6136 / 16.3431 | 15.1827 / 15.0509 |
| Bind absent name, avatar True | 0.1912 / 0.1920 | 0.1906 / 0.1972 |

Construction improves 7–10% without an avatar and 4–5% with one. Existing-name binding improves 16–18%. Remove/recreate improves about 24% without an avatar and 1–2% with one, where native avatar construction dominates. Empty construction varies from 0.8% faster to 0.8% slower; absent-name binding adds roughly 1–7 ns. The host instance grows from 952 to 968 bytes, while the outer fixture shrinks from 1064 to 1056 bytes, a net eight stored bytes per row. These measurements exclude text measurement, media loading, rasterization, backing surfaces and complete chat rows; they do not establish whole-app scrolling gains.

Run CHAT_FORWARD_BENCHMARK=1 with ForwardNameBenchmarkTests.testForwardBindingCosts; optionally set CHAT_FORWARD_REVERSE=1 and CHAT_FORWARD_PHOTO=1. Fresh-process memory probes use ForwardNameBenchmarkTests.testRetainedSenderMemory with CHAT_FORWARD_MEMORY=native or layers, CHAT_FORWARD_PRESENT=0 or 1 and CHAT_FORWARD_PHOTO=0 or 1. Preserve /tmp/chat-forward results between processes. Evidence is in results/forward-name.

Five fresh processes per implementation/presence/avatar combination retain 5,000 rows with unique premeasured layouts; constructors are warmed before the baseline. Median incremental physical footprint:

| Fixture | Native | Layers | Reduction |
| --- | ---: | ---: | ---: |
| Empty | 75,677,744 bytes | 73,007,152 bytes | 3.5% |
| Forwarded name | 97,468,488 bytes | 91,357,280 bytes | 6.3% |
| Forwarded name with avatar | 118,063,176 bytes | 114,081,840 bytes | 3.4% |

Rows are unattached and unrasterized; footprint excludes media fetching, premeasured layouts, the remaining chat controls and backing surfaces. The empty fixture also shows an allocator-dependent footprint difference despite the eight-byte increase in stored instance size; do not infer the same result for real empty chat rows. Some memory probes overlapped unrelated builds, recorded in measurement-commands.json; they measure each process's own physical footprint, not timing. No other build/test process was observed before or after the four timing runs.

Final release and debug Address Sanitizer each pass 286 functional tests (314 total, 28 optional measurements skipped); focused debug Thread Sanitizer passes 95 (96 total, one optional benchmark skipped). Native TGUIKit passes 371 functional tests (389 total, 18 optional measurements skipped). All 393 frozen inputs remained unchanged. The production host matches its compiled copy, the captured baseline host matches except for its class name, and the staged binding/layout/colors/shake/tooltip code matches the compiled fixture. All four changed production files pass Swift syntax parsing. The full Telegram app has not been built or interactively validated in this pass. Preexisting row avatar-menu and ChatRowItem feature edits are excluded from this commit.

## Live media-caption layers

ChatRowView now uses the existing ChatLayerMessageTextView for plain and linked captions. A simple one-block caption uses one native host instead of a FoldingTextView plus TextView. Multiple plain blocks share that host. Unsupported rich captions retain FoldingTextView, including quotes, spoilers, embedded emoji, formatted dates and streaming. Search highlights in media and album rows now dispatch through the caption wrapper. Caption selection sources preserve caption/block order, then fact-check text; ChatMessageView adds body and webpage text. Invoice, poll and todo rows preserve their explicit native selection overrides.

Caption identity is updated in place, avoiding wrapper and reveal-handler replacement when loading or message identity changes. Unchanged ordered captions retain their result array, and idle single captions have a direct reuse path. Reordering still reserves unchanged siblings before recycling other hosts. Renderer eligibility is scanned on every binding, including mutable attributed strings. Native selection and active content animations delay migration. When a layer caption becomes native while sharing its layout, selection is captured before old-host cleanup and restored afterward. A lazily allocated binding state queues synchronous reentrant updates; the latest pending caption set wins after cleanup. Empty rows allocate no state object, but the base row gains one optional reference field.

The harness compiles the actual caption wrapper, binding, click, selection and highlight methods plus the actual specialized-row selection overrides. Native reuse is frozen at df4acbdc0; older replacement controls remain at 2e1e4125c. It uses real TGUIKit and full native FoldingTextView. Account/media data, the enclosing row, placement model and fact-check wrapper are stand-ins. The merged selection API now has an optional TelegramCore.RichText payload; a lab-only TelegramCore shim supplies its plain value type so existing production selection files remain unchanged. This lab does not validate rich-message payload serialization or the full Telegram dependency graph.

Sixteen new functional tests cover same-caption selection and loading changes; cross-message/account reuse; mixed native/layer albums; ordered reservation; mutable-layout renderer changes; active animation; link presses and cancellation; pending menus; synchronous layer and native cleanup reentrancy; release of hosts/accounts; fact-check/body/webpage ordering; specialized overrides; and search highlights. Eighteen static bitmap pairs match exactly across three scales, mixed rich/plain captions and order changes, with three additional exact search-highlight pairs. A click-coordinate grid compares each caption against native rendering. Eight cross-row copy comparisons cover both table orders and drag directions through plain captions, quoted captions, message text and webpage text.

Release medians below are microseconds per operation, native reuse / layer captions. Layouts are premeasured. Construction includes the fixture outer row, row container and content view. Each operation alternates implementations over nine batches. The first implementation's rebinding regression is retained in benchmark-initial.json; removing duplicate identity stores and bypassing matching/result-array reconstruction reduces that overhead.

| Operation | First final run | Repeat |
| --- | ---: | ---: |
| construct captions 1 rich false | 35.051 / 32.929 | 35.037 / 32.629 |
| construct captions 1 rich true | 43.457 / 44.773 | 43.376 / 44.779 |
| construct captions 3 rich false | 69.700 / 60.086 | 71.428 / 62.370 |
| construct captions 3 rich true | 98.520 / 100.683 | 100.160 / 101.124 |
| construct captions 10 rich false | 192.966 / 159.041 | 192.365 / 162.799 |
| construct captions 10 rich true | 285.107 / 281.075 | 288.010 / 291.137 |
| recycle captions 1 rich false | 3.120 / 3.129 | 3.144 / 3.089 |
| recycle captions 1 rich true | 4.667 / 4.510 | 4.732 / 4.677 |
| recycle captions 3 rich false | 8.731 / 9.280 | 9.218 / 9.459 |
| recycle captions 3 rich true | 13.663 / 14.043 | 13.905 / 14.159 |
| recycle captions 10 rich false | 29.576 / 29.475 | 31.094 / 30.135 |
| recycle captions 10 rich true | 46.444 / 47.915 | 47.323 / 49.316 |
| same captions 1 rich false | 2.126 / 2.243 | 2.151 / 2.187 |
| same captions 1 rich true | 2.894 / 2.896 | 2.906 / 2.874 |
| same captions 3 rich false | 5.797 / 6.102 | 6.025 / 6.455 |
| same captions 3 rich true | 8.015 / 8.314 | 8.090 / 8.366 |
| same captions 10 rich false | 19.013 / 20.640 | 20.092 / 20.680 |
| same captions 10 rich true | 25.618 / 26.319 | 26.158 / 27.304 |

Plain-caption construction improves 6–18% in these fixtures. Single-caption recycling is approximately flat; updates of the same caption add about 0.04–0.12 microseconds. Larger sets are mixed: same-caption updates add roughly 0.3–1.6 microseconds, while recycling ranges from a small gain to a small regression. Native rich-caption construction and binding are generally within about 4% of the previous path. These results support a construction/memory improvement, not a universal rebinding speedup.

Five fresh processes per implementation retain 3,000 rows with unique premeasured single captions, alternating native/layer order. Median incremental physical footprint is 50,528,280 bytes native versus 46,170,136 bytes layered, an 8.6% reduction. Rows are unattached and unrasterized; this excludes premeasured layouts, media resources, drawing surfaces and the rest of the real chat row. View counts including the fixture row/container/content are 5 versus 4 for one plain caption, 9 versus 6 for three and 23 versus 13 for ten. These are not whole-app memory or scrolling measurements.

To reproduce after preparing and building the release lab:

```sh
CHAT_CAPTION_LAYER_BENCHMARK=1 swift test --package-path tools/perflab/ChatLayerEngineLab --scratch-path /tmp/ChatLayerEngineLab-release -c release --skip-build --filter LayerCaptionBenchmarkTests.testBindingCosts
python3 tools/perflab/ChatLayerEngineLab/measure-caption-memory.py
```

Evidence is in results/layer-captions. The full Telegram app has not been built or interactively validated in this pass. Unrelated working-tree changes are excluded from the implementation commit.

Final release and debug Address Sanitizer each pass 302 functional tests (332 total, 30 opt-in measurements skipped). Focused debug Thread Sanitizer passes 132 (133 total, one optional benchmark skipped). All seven changed production files pass Swift syntax parsing. All 333 captured source/generator inputs stayed unchanged across the final runs. An unrelated modal-animation dependency changed during the first sanitizer run; release and Address Sanitizer were rebuilt and rerun against the final captured inputs before Thread Sanitizer. Timing/memory samples predate that unrelated dependency update; caption/engine sources are identical. Staged caption and selection method bodies match the tested working-tree methods, and preexisting avatar-menu/media/grouped-row changes remain excluded.


## Static quotes in live message and caption bindings

Static block quotes and code blocks now use the existing layer host through the production message/caption binding path. A supported text body retains one native host, including mixed plain and quoted blocks. Collapsible quotes that need a reveal action, streaming, spoilers, custom emoji, formatted dates, and unsupported backgrounds keep their native rendering paths. Malformed quote attributes also remain native. Reflow can move a short collapsible quote between renderers as its measured line count changes.

The new `LiveStaticQuoteTests` exercises actual production binding/preparation methods with the existing account and enclosing-row fixtures. It adds 54 exact bitmap pairs at multiple scales, including Arabic, emoji, selected quotes, code headers, and links. It also covers cross-row attributed copying in both drag/table directions, current-message link and code-copy dispatch, accessibility text, selection cleanup, width-driven fallback, and native reentry. Existing native-lifecycle tests now use explicitly unsupported attributes or genuinely collapsible quotes so their original cancellation, selection, animation, and reentrancy coverage remains active.

The release run passed 313 tests, with 30 opt-in tests skipped. Raw results, source hashes, and paired measurements are in `results/live-static-quotes/`. The final suite used an immutable copy of TGUIKit because unrelated work was modifying that package during the session. The snapshot helper reproduces the generated production and fixture sources without changing the main checkout:

```sh
python3 tools/perflab/ChatLayerEngineLab/prepare-isolated.py /tmp/ChatStaticQuoteValidation
swift test --package-path /tmp/ChatStaticQuoteValidation --scratch-path /tmp/ChatStaticQuoteValidation-build -c release
CHAT_LIVE_TEXT_BENCHMARK=1 swift test --package-path /tmp/ChatStaticQuoteValidation --scratch-path /tmp/ChatStaticQuoteValidation-build -c release --skip-build --filter LiveChatTextBenchmarkTests/testLiveTextBindingCosts
CHAT_LIVE_TEXT_BENCHMARK=1 CHAT_LIVE_TEXT_REVERSE=1 swift test --package-path /tmp/ChatStaticQuoteValidation --scratch-path /tmp/ChatStaticQuoteValidation-build -c release --skip-build --filter LiveChatTextBenchmarkTests/testLiveTextBindingCosts
CHAT_LIVE_TEXT_MEMORY=native CHAT_LIVE_TEXT_QUOTED=1 CHAT_LIVE_TEXT_BLOCKS=3 swift test --package-path /tmp/ChatStaticQuoteValidation --scratch-path /tmp/ChatStaticQuoteValidation-build -c release --skip-build --filter LiveChatTextBenchmarkTests/testRetainedLiveTextMemory
CHAT_LIVE_TEXT_MEMORY=layers CHAT_LIVE_TEXT_QUOTED=1 CHAT_LIVE_TEXT_BLOCKS=3 swift test --package-path /tmp/ChatStaticQuoteValidation --scratch-path /tmp/ChatStaticQuoteValidation-build -c release --skip-build --filter LiveChatTextBenchmarkTests/testRetainedLiveTextMemory
```

Timing results use nine paired batches and a second run with reversed ordering. No competing compiler process was observed before measurement. They measure row binding with premeasured layouts and unattached native views, excluding layout measurement, window drawing, media decoding, and scrolling FPS.

| Quoted text blocks | Construction, native → layers | Construction time reduction | Rebind time reduction | Native views including outer fixture row |
| --- | --- | --- | --- | --- |
| 1 | 44.6–44.9 → 26.2–27.2 µs | 40–41% | 22–25% | 4 → 2 |
| 3 | 82.6–84.4 → 38.3–39.4 µs | 53–54% | 32–33% | 7 → 2 |
| 12 | 250.6–264.4 → 93.7–96.0 µs | 63–64% | 35–36% | 20 → 2 |

Four fresh-process memory probes in native/layers/layers/native order retained 3,000 distinct premeasured three-block quoted rows. Incremental process footprint was 28,945–29,049 bytes per native row versus 14,593–14,609 bytes per layer row, about 50% lower. This includes allocator/runtime effects and excludes the already allocated layouts; it is not a measurement of total Telegram memory. No complete app build or app-wide FPS measurement was performed for this pass.


An additional attached-window variant (`CHAT_LIVE_TEXT_ATTACHED=1`) includes installing each new row in an AppKit window and completing layout after construction/rebinding. Both ordering runs passed. For three-block quoted rows, construction fell from 128.7–132.5 µs to 57.3–60.3 µs (55–56% less time), and rebinding from 16.9–19.0 µs to 7.0–7.9 µs (58% less). One-block construction improved 35–36%, and twelve-block construction 71–72%. These remain CPU binding/layout measurements; they do not measure presented frames or scrolling FPS. Attached-window results are stored separately from the unattached samples.

The complete regression suite also passed under Address Sanitizer (leak detection disabled) and Thread Sanitizer: 313 tests passed and 30 optional tests skipped in each run. ASAN preceded the final opt-in attached-window benchmark addition; production and functional-test sources were identical, and separate compiler-input manifests preserve that distinction. All 532 final compiler inputs were verified unchanged after validation.


## Quote metadata scans and last-line checks

`TextViewLayout.hasBlockQuotes`, `blockCollapsable`, and `lastLineIsQuote` now use a bounded Core Foundation lookup. They inspect the final value or skip the trailing span without the attribute, preserving the prior last-nonempty-value semantics. Last-line queries use the existing measured range without creating an attributed substring. Invalid stale line ranges after text replacement return no quote. The implementation has no per-layout cache, so mutable attributes and `NSTextStorage` updates remain visible immediately.

The public `containsAttribute` helper is unchanged. An initial experiment demonstrated that reversing its traversal would return a different object for 1,560 of 6,144 equal-value cases; the specialized internal getters expose only type checks and immutable quote properties. That rejected experiment is retained in `results/quote-scans/`.

Chat presentation preparation now derives quote presence from the attribute scan it already performs. The full preparation path tracks the last nonempty quote value's type, including malformed values after valid quotes. The fast path still rejects unsupported attributes. This removes a second Foundation enumeration from each prepared block.

Seven new functional tests cover 1,024 mixed-attribute layouts for each preparation path, 1,024 quote-layout cases, mutable storage, equal-valued objects, malformed trailing values, multilingual and UTF-16 ranges, line boundaries, and stale ranges after replacement. The pre-change preparation source is captured from `53c13d6a8` in `Reference/quote-scan-preparation.swift.txt`. The reference getter for the last line uses public `TextViewLine.range`; all three production constructor sites assign that same range to the private field used by the prior getter.

The complete release runs passed 320 chat-engine tests (31 optional tests skipped) and 392 TGUIKit tests (18 optional tests skipped). The isolated generator reproduced all 67 generated/fixture Swift sources and 66 test files exactly. Raw outputs and 538 verified source/dependency input hashes are in `results/quote-scans/`.

```sh
python3 tools/perflab/ChatLayerEngineLab/prepare-isolated.py /tmp/QuoteScanValidation
swift test --package-path /tmp/QuoteScanValidation --scratch-path /tmp/QuoteScanValidation-build -c release
swift test --package-path /tmp/QuoteScanValidation/TGUIKit --scratch-path /tmp/QuoteScanTGUIKit-build -c release
CHAT_QUOTE_SCAN_BENCHMARK=1 swift test --package-path /tmp/QuoteScanValidation --scratch-path /tmp/QuoteScanValidation-build -c release --skip-build --filter TextQuoteScanBenchmarkTests/testLookupAndBindingCosts
CHAT_QUOTE_SCAN_BENCHMARK=1 CHAT_QUOTE_SCAN_REVERSE=1 swift test --package-path /tmp/QuoteScanValidation --scratch-path /tmp/QuoteScanValidation-build -c release --skip-build --filter TextQuoteScanBenchmarkTests/testLookupAndBindingCosts
```

Final timing runs used nine paired batches, repeated with reversed ordering, after checking that competing compiler processes had ended. An intervening pair recorded during an unrelated Xcode build is retained separately as `contended-*.json.gz` and excluded from the reported results.

| Operation | Before → after | Time reduction across both final runs |
| --- | --- | --- |
| Single-run text: quote absence | 148–151 → 93 ns | 37–38% |
| Single-run text: whole quoted block | 146–148 → 35–37 ns | 75–76% |
| Single-run text: last-line quote absence | 241–246 → 91–93 ns | 62% |
| Three-block preparation, plain | 944–961 → 558–567 ns | 40–42% |
| Three-block preparation, quoted | 961 → 516–563 ns | 41–46% |
| Attached three-block plain row rebinding | 6.25–6.28 → 5.77–5.80 µs | 7.7% |
| Attached three-block quoted row rebinding | 7.37–7.53 → 6.89 µs | 6.5–8.5% |

Across the 1/3/12-block matrix, preparation used 33–48% less time and complete attached-window rebinding used 4–11% less time. Rebinding includes completed layout and uses the same current layer renderer in both cases, changing only preparation, so these are incremental improvements over the preceding layer migration. The 128-run no-quote stress case was approximately unchanged to modestly faster. No final case regressed by more than 3% in either ordering run. Larger gains for densely fragmented quote metadata are stress-case results, not a whole-app estimate.

The measurements use premeasured layouts and fixture account/row models with actual AppKit and TGUIKit. They do not measure full-app FPS, total memory, or media decoding. This pass eliminates substring work and redundant scans without adding an instance cache; it makes no retained-memory claim.

The final chat-engine suite also passed under Address Sanitizer (leak detection disabled) and Thread Sanitizer: 320 tests passed and 31 optional tests skipped in each run. All 538 recorded source/dependency inputs were verified unchanged after these runs. The separate full TGUIKit run was release-only.

## Reusing collapsed-quote fade bitmaps

Collapsed `FoldingTextLayout.ViewLayout.updated` regenerated its fade bitmap on every measurement, including unchanged geometry and identical masks in independent messages. The production implementation now shares immutable images through a private, synchronized FIFO cache in `FoldingTextView.swift`. Keys preserve exact width, height, fade origin and backing scale. Drawing-context settings changes clear the cache. The cache retains at most 32 images and 2 MiB of bitmap data, excluding its small bookkeeping allocations and images still owned by rows after eviction. Oversized images bypass retention. Rasterization runs outside the lock; concurrent duplicate requests converge on the retained image when possible.

The renderer's drawing operations are unchanged. Its explicit scale parameter captures the requested scale for both the key and bitmap. There are no per-row bookkeeping fields, public APIs, new source-membership requirements or changes to quote reveal/selection behavior. Plain text and revealed quotes do not request these masks.

`Reference/quote-mask-layout.swift.txt.gz` captures the original mask function and complete folding-layout class from `ec428cb48`. The lab renames that class and gives the original renderer an explicit scale argument for comparisons. Production cache member visibility is relaxed only in the generated test module to verify retention bounds. All other candidate method bodies are extracted from production.

Seven new functional tests cover 225 exact geometry/scale bitmap comparisons, 600 concurrent generation/eviction requests, exact fractional keys, count and byte limits, oversized bypass, color-space/bitmap-format invalidation, 100 independent rows sharing an immutable mask, and full layout measurement/reveal/reflow comparisons across two backing scales, three font sizes, ordinary quotes and code headers. The reflow test also externally remeasures the mutable text layout and replaces its attributed string, preventing reuse based on stale prior line metrics. Existing chat-engine tests continue to cover rendering and interactions.

Paired release measurements alternate implementations over nine batches, then repeat with reversed initial ordering. Complete measurement includes text layout; construction includes attributed text and folding-layout creation. The fixture uses long, collapsible quotes with mixed Latin, Arabic and emoji text. Timings are microseconds per operation:

| Workload | Original | Cached masks | Less time |
| --- | ---: | ---: | ---: |
| Construct and measure one block | 236.8–237.7 | 213.0–216.4 | 9–10% |
| Construct and measure three blocks | 713.1–714.2 | 639.9–640.4 | 10% |
| Construct and measure twelve blocks | 2927.6–2988.7 | 2602.9–2666.8 | 11% |
| Re-measure three blocks, fixed width | 677.4–691.0 | 600.1–604.3 | 11–13% |
| Re-measure twelve blocks, eight widths | 2724.6–2865.1 | 2407.4–2534.3 | 12% |

Across all 1/3/12-block and 1/8/128-width measurement cases, elapsed time falls 10–13.5%. Different requested text widths can still yield identical mask geometry. The separate mask-only 128-geometry cycling workload intentionally exceeds the cache and takes 1.3–2.4% longer (roughly 0.3–0.6 µs per miss); one/eight repeated geometries avoid more than 99% of mask-generation time. These are component CPU measurements, not whole-app scrolling FPS.

The 100-row sharing test counts unique live bitmap allocations and their `bytesPerRow × height`, not total process memory. It retains 100 distinct original masks versus one shared candidate mask; the JSON in `results/quote-masks/` records the exact storage. The cache can retain up to 2 MiB after rows disappear, trading bounded idle storage for reuse.

Final release, Address Sanitizer (leak detection disabled) and Thread Sanitizer runs each pass 327 functional tests, with 32 optional measurements skipped. The final isolated generator reproduces 68 fixture/generated Swift sources and 68 test files exactly; all 542 recorded source/dependency inputs remain unchanged. The timing and final-validation TGUIKit snapshots match. Raw batches, complete compressed logs, input hashes and storage counts are retained in `results/quote-masks/`. No full application build, total-process memory measurement or app FPS measurement was performed.

## Code-header icon reuse

`FoldingTextQuoteLayer.draw` previously allocated and tinted a copy-icon bitmap every time it painted a code header. A private shared cache now reuses those immutable results across native quote wrappers and chat-layer quote decorations. It adds no per-layer fields or public API. Each draw still resolves the current hook image; bitmap identity, logical size, immutable `CGColor`, scale and drawing-context settings distinguish entries. Each entry retains its source bitmap so a released object's address cannot be mistaken for a later image. Dynamic colors bypass reuse, and changing drawing settings clears the cache.

The cache retains at most 16 entries. An entry is retained only when the source and output `bytesPerRow × height` sum is at most 16 KiB; output bitmap storage is therefore bounded by 256 KiB, in addition to retained source objects and bookkeeping. Oversized images are drawn without retention. Rasterization happens outside the lock. The miss renderer executes the same constant-tint, vertical-flip operations as `NSImage.precomposed`, using the already resolved bitmap and color to avoid repeating that work.

An asset-only mini-app compiles just `Icon_CopyCode.imageset`. The app's Xcode-generated `NSImage(resource:)` initializer delegates to `Bundle.image(forResource:)`; it does not use the newer `DeveloperToolsSupport.ImageResource` initializer. The initial measurement accidentally used that newer SDK initializer. Its historical timing/probe files remain in `results/quote-icons/`, and the corrected measurements below are in `results/quote-icons/app-loader/`. The generated initializer excerpt and source hash are retained there.

The corrected probe initializes AppKit as the test application does, then uses the generated initializer's underlying expression. One hundred loads produce 100 `NSImage` identities but one `CGImage` identity on this machine, with a logical 16×16 image and a 32×32 bitmap. A separate test confirms that registering a same-named placeholder before the first lookup does not replace the bundled asset. Reproduce the identity check with `python3 probe-copy-icon.py /tmp/copy-icon-resource.json`; it requires local Xcode tools and does not build Telegram.

Nine new functional tests cover exact tint pixels across sizes/scales/colors, equal colors and distinct color spaces, source replacement and resized images, dynamic appearances, drawing-format invalidation, eviction and oversized bypass, source-lifetime pixel checks with temporary images released between operations, 600 concurrent requests, and complete quote-decoration pixels. Twenty-seven complete painter pairs include both ordinary/code quotes, changing source icons and the actual bundled copy-icon asset at 1×/2×/3×. The original painter is preserved byte-for-byte in `Reference/quote-icon-painter.swift.txt.gz`; the original full painter comparison remains enforced after substituting only the cache call. The reference uses the same unchanged ordinary-quote bitmap as production, with its initializer checked against the captured original. The first full-suite run exposed differing lazy initialization scales in two separate reference/production globals; a deterministic prewarm reproduces that fixture mismatch outside the changed code-header path. Sharing the unchanged asset removes the mismatch without changing production drawing, and the prewarm remains in the regression test. Cache member visibility is relaxed in the generated test module solely to check retention invariants.

Corrected release timings use the actual app asset and the Xcode-generated loader's `Bundle.image(forResource:)` implementation. Nine paired batches alternate baseline/candidate, followed by another run with reversed initial order. The contexts are cleared for each draw; the composed workload draws both quote decorations and a real `TextViewLayer` containing five lines of code. Timings are microseconds per operation:

| Workload | Original | Reused tint | Less time |
| --- | ---: | ---: | ---: |
| One code quote's decorations | 246.4–251.7 | 223.2–227.5 | 9–10% |
| Three code quotes' decorations | 744.2–769.8 | 671.7–686.4 | 10–11% |
| Twelve code quotes' decorations | 3001.0–3062.7 | 2733.5–2762.1 | 9–10% |
| Five-line code text plus decorations | 239.7–240.4 | 215.5–216.0 | 10% |
| Resource loading plus one repeated tint | 50.5–51.6 | 32.9–33.1 | 35–36% |

Ordinary quote painting is within about 1.1% of the baseline across both orderings. Cycling through 32 colors intentionally exceeds the cache and costs about 0.4% more, roughly 0.2 µs. An initial `NSColor`-key version regressed substantially in that case; immutable `CGColor` hashing and eliminating a second bitmap lookup remove almost all of the miss penalty. Rejected/intermediate synthetic-icon measurements and the previous SDK-loader measurements remain archived and are not used for the corrected performance claims.

These are CPU drawing measurements, not presented-frame timings, full chat scrolling FPS or total app memory measurements. The actual asset-loader path still accounts for much of the remaining cost; sharing arbitrary mutable `NSImage` wrappers requires a separate mutation/representation audit before changing that path across the app.

Before the loader correction, release, Address Sanitizer (leak detection disabled) and Thread Sanitizer each passed 336 functional tests, with 33 optional measurements skipped. The isolated generator reproduces 70 fixture/generated Swift sources and 70 test files exactly, and all 549 recorded source/dependency inputs remain unchanged. The final validation snapshot includes an unrelated concurrent `TableView.swift` change made after timing; the quote renderer, text drawing, image drawing and all other TGUIKit sources match the timing snapshot. The benchmarks do not instantiate a table. Raw batches, source snapshots, complete compressed logs and input hashes are retained in `results/quote-icons/`.

The loader correction adds a tenth icon test: 54 exact tint comparisons across repeated fresh resource loads, three scales, light/dark appearances and three colors, plus 18 complete painter comparisons. The corrected frozen release suite passes 337 functional tests with 33 optional measurements skipped. All 549 recorded inputs are verified; only the two icon test files and the isolated package path differ from the prior tested snapshot. Production quote code is unchanged, so the earlier sanitizer results remain the evidence for that code; sanitizers were not rerun for this test-only correction. Concurrent widget work changed `TableView.swift`, `TableRowResizeAnchor.swift` and its test in the live checkout after the frozen snapshot. The measured workload does not instantiate a table; this run does not validate those unrelated edits.

An exploratory breakdown using the verified app loader measures 3.95 µs for resource construction versus 0.14 µs for an independent copy, but 31.59 versus 26.88 µs when each also extracts its bitmap. Reusing a retained image or wrapping its bitmap measures 3.07/2.40 µs; neither is a drop-in replacement for the current mutable, multi-representation image interface. Three scale comparisons and eight mutation checks pass for the copied copy-code asset, but that is not coverage of every asset type. The inventory contains 39 PDF and 12 SVG representations, including four sets preserving vectors. These exploratory measurements motivate broader testing, not a production cache change. Sources, results and the inventory are saved as `app-loader/exploration-asset-loading.*` and `asset-inventory.json`.

## Foldable quotes in live message and caption bindings

Supported collapsible quotes now use the existing layer text host in actual message and caption binding methods. A reveal callback is required before a folded presentation can bind. Message callbacks read the current row item; caption callbacks read the retained caption wrapper's current message identity. Removal clears the old action. Width changes can add or remove folding decorations without replacing the text host. Streaming, spoilers, embedded custom emoji, formatted dates, malformed quote attributes and unsupported block backgrounds retain native rendering.

Same-message animated updates carry the native 0.2-second ease-out transition through block frames, quote clipping and arrow movement. New identities bind immediately. Delayed collapse masks use weak references and a generation check, so removal, reentry, expansion or replacement cannot apply a stale mask. Geometry cleanup runs only after a message host has animated. Plain message hosts allocate their reveal callback only when folding requires one. Switching a selected message to native rendering preserves compatible selection, including when both renderers share the same mutable layout.

Integration testing found two additional issues in the earlier layer prototype. Changing the display scale marked bitmap-backed masks for display, replacing their contents with an empty backing store. Decorations now preserve their authored scale, matching native wrappers; text rendering still follows the host's backing scale. The arrow also used a centered anchor instead of the native top-left anchor, shifting its animation by half its size. Endpoint comparisons now enforce the native anchor and motion.

The mini-app adds twelve live-binding tests and six transition tests. The live tests include 96 exact bitmap pairs across message bodies, captions, code headers, selection, scale changes and attached-window transitions; current-item and reordered-caption dispatch; cancelled presses; synchronous reentry; rich-content fallback; cross-row attributed copying in both drag/table directions; and accessibility reveal actions. Transition tests compare native clipping and arrow animation endpoints, duration and timing function, final pixels, delayed-work cancellation and object lifetime. They do not measure intermediate presented-frame timing.

Final release, Address Sanitizer and Thread Sanitizer runs each pass 354 functional tests, with 36 optional measurements skipped and no failures. Address Sanitizer leak detection is disabled. All 604 captured compiler inputs and 183 production files match their recorded hashes; fresh fixture generation reproduces all 454 Swift source and manifest files. Logs, source comparisons, input hashes and validation details are archived in `results/live-folding/`. This validates the extracted bindings and engine, not a complete app build.

The harness retains the complete production FoldingTextView and extracts the actual message/caption binding and outer text-layout methods. Account, enclosing-row and media dependencies remain stand-ins. Its two copies of FoldingTextLayout.ViewLayout are bridged field-for-field only in the harness; tests verify the preserved text identity, size, reveal state and bitmap identities. Duplicate native/reference quote painters share the same immutable quote icon as the engine, matching the real app's single module-level icon. Without this sharing, fixture initialization at different scales creates false bitmap differences. The original initializer is verified before substitution. Painter bodies are unchanged.

A separate baseline module reconstructs 48 captured engine and native-binding source files from before this migration. It uses the same TGUIKit and account/media fixtures as the candidate; only module names and the shared immutable test asset are adapted. Release measurements alternate original/layer order over nine batches, then repeat in a fresh process with reversed initial ordering. Layouts are premeasured; these timings include row construction or complete binding, not text measurement, media loading or rasterization.

| Folded message workload | Original µs | Layers µs | Less time |
| --- | ---: | ---: | ---: |
| Construct, one block | 34.57–34.75 | 24.03–24.07 | 30.5–30.7% |
| Construct, three blocks | 65.10–69.27 | 36.85–39.60 | 42.8–43.4% |
| Construct, twelve blocks | 200.51–205.84 | 96.08–103.16 | 49.9–52.1% |
| Bind same content, one block | 2.44–2.48 | 1.44–1.45 | 40.9–41.8% |
| Bind same content, three blocks | 5.25–5.34 | 2.72–2.74 | 48.2–48.7% |
| Bind same content, twelve blocks | 16.32–16.42 | 7.99–8.12 | 50.3–51.3% |

Recycling folded messages improves 40.5–48.2%; expanded-quote construction improves 30.8–53.8%. Folded caption construction improves 22–49.4%, and repeated folded caption binding improves 34.2–49.7%. The three/twelve-block fixtures alternate quoted and plain blocks. Their complete fixture view counts fall from 7/20 to 2; the single-block fixture falls from 4 to 2. Both counts include the enclosing test row.

Plain/static controls remain in the report. Construction is mixed and mostly close; static single-block construction adds 0.34–0.52 µs (1.8–2.6%). Some repeated/recycled text controls add small fractions of a microsecond. Plain caption updates add 0.04–0.20 µs (2.7–5.6%). These are real costs of the current integration, not a universal rebinding speedup. Full per-workload samples and medians are in `results/live-folding/`.

Four fresh-process probes in original/layers/layers/original order retain 2,000 independently premeasured three-block folded rows. Incremental physical footprint is 31,326–31,359 bytes per original row versus 17,588–17,596 bytes per layer row, approximately 44% lower. Both layout sets and reserved result-array capacity exist before measurement. Rows are unattached and unrasterized; allocator/runtime effects are included, while layout storage, media, GPU surfaces and complete app rows are excluded. The message node's runtime instance size grows from 368 to 376 bytes for transition state. These measurements do not establish total Telegram memory, opening latency or scroll FPS.

Reproduction:

```sh
python3 tools/perflab/ChatLayerEngineLab/prepare-isolated.py /tmp/ChatFoldLiveCheck
swift test --package-path /tmp/ChatFoldLiveCheck --scratch-path /tmp/ChatFoldLiveCheck-build -c release
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/ChatFoldLiveCheck --scratch-path /tmp/ChatFoldLiveCheck-asan --sanitize address
swift test --package-path /tmp/ChatFoldLiveCheck --scratch-path /tmp/ChatFoldLiveCheck-tsan --sanitize thread
CHAT_FOLD_BENCHMARK=1 swift test --package-path /tmp/ChatFoldLiveCheck --scratch-path /tmp/ChatFoldLiveCheck-build -c release --skip-build --filter LiveFoldingBenchmarkTests.testCompleteBindingAndConstructionCosts
CHAT_FOLD_BENCHMARK=1 CHAT_FOLD_REVERSE=1 swift test --package-path /tmp/ChatFoldLiveCheck --scratch-path /tmp/ChatFoldLiveCheck-build -c release --skip-build --filter LiveFoldingBenchmarkTests.testCompleteBindingAndConstructionCosts
CHAT_FOLD_MEMORY=original swift test --package-path /tmp/ChatFoldLiveCheck --scratch-path /tmp/ChatFoldLiveCheck-build -c release --skip-build --filter LiveFoldingBenchmarkTests.testRetainedFoldedRowMemory
CHAT_FOLD_MEMORY=layers swift test --package-path /tmp/ChatFoldLiveCheck --scratch-path /tmp/ChatFoldLiveCheck-build -c release --skip-build --filter LiveFoldingBenchmarkTests.testRetainedFoldedRowMemory
```

Run builds and measurements sequentially. Save each `/tmp/chat-fold-binding-benchmark.json` before the next timing run overwrites it. Memory probes write `/tmp/chat-fold-memory-original.json` or `/tmp/chat-fold-memory-layers.json`; repeat them in opposite order. Compiler checks before and after both recorded timing runs found no competing compiler processes. The full app was not built or manually exercised in this pass.

## Reusing rendered quote backgrounds

`FoldingTextQuoteLayer` now preserves its existing rendered contents when an assignment has the same drawing inputs. Both native folding wrappers and layer message/caption hosts use this painter. The snapshot copies frame, component colors and code style from mutable quote objects; identity alone is insufficient. It also records bounds, contents scale, system scale and graphics settings. Headers and dynamic/pattern colors retain unconditional redraws. Explicit invalidation remains pending, and cleared contents force a new display. The snapshot is established by actual layer display, not by offscreen calls to `draw(in:)`.

A regression test exposed an ordering problem in the first candidate: callers assign quotes before updating the background frame. Equivalent assignment followed by changed bounds or scale could preserve stale pixels. Bounds and scale observers now invalidate independently. The regression covers frame size, bounds origin and scale, comparing cached output to the captured original painter. Additional tests cover mutable fields, array order/removal, reuse, equivalent fresh objects, display settings, direct drawing, headers, dynamic colors, copied layers, attached-window reparenting and animation completion. Live body/caption binding tests verify the reuse path and width reflow. Fifty-four style/scale bitmap comparisons are exact, in addition to mutation and lifecycle comparisons.

The release benchmark alternates variants over nine batches and repeats in a fresh process with reversed initial order. Each operation assigns premeasured quotes, optionally followed by synchronous layer rasterization. The following are background-layer costs, not complete message rendering or scroll-frame timings:

| Repeated background assignment + display | Original µs | Cached µs |
| --- | ---: | ---: |
| One quote | 62.08–62.33 | 0.143–0.150 |
| Three quotes | 182.10–186.86 | 0.226–0.234 |
| Twelve quotes | 725.94–728.75 | 0.610–0.614 |

Changed-content redraw costs remain within roughly 1% in these runs. Construction varies from 1.7% faster to 1.8% slower. Headers still redraw and show no material improvement. Assignment without a subsequent display becomes more expensive: one quote adds 0.10–0.11 µs, three add 0.18–0.19 µs, and twelve add 0.54–0.55 µs. This trades a small comparison cost for avoiding unchanged raster work across display cycles; Core Animation already coalesces repeated invalidations within a cycle.

The layer's runtime instance size increases from 96 to 192 bytes, plus a value snapshot array for cacheable quotes. It retains no additional bitmap, quote object or header text object. This is a CPU optimization with a small storage cost, not a measured memory reduction. Raw batches, medians, compiler pre/post checks and validation logs are stored in `results/quote-redraw/`. Compiler checks found no competing compiler before or after either timing process; they are not continuous monitoring.

Release, Address Sanitizer and Thread Sanitizer each pass 365 functional tests, with 37 optional tests skipped and no failures. Address Sanitizer leak detection is disabled. The 607 captured compiler inputs remain unchanged; the two lifecycle tests were added after timing, and all measured libraries, benchmarks and dependencies are identical. The production quote painter matches the tested snapshot. Separate formatted-date and waveform changes developed concurrently are outside this validation.

To run the focused coverage after preparing an isolated lab:

```sh
swift test --package-path /tmp/QuoteRedrawCheck -c release --filter 'QuoteRedrawTests|QuoteRedrawLifecycleTests|LiveFoldingQuoteTests.testLiveBodyAndCaptionRebindingPreserveQuoteBackgroundContents'
QUOTE_REDRAW_BENCHMARK=1 swift test --package-path /tmp/QuoteRedrawCheck -c release --skip-build --filter QuoteRedrawBenchmarkTests
QUOTE_REDRAW_BENCHMARK=1 QUOTE_REDRAW_REVERSE=1 swift test --package-path /tmp/QuoteRedrawCheck -c release --skip-build --filter QuoteRedrawBenchmarkTests
```

Save `/tmp/quote-redraw-benchmark.json` between timing runs. Build and measure sequentially. This pass does not establish full-app build success, whole-app memory savings or scroll FPS.

## Formatted dates and native emoji reuse

Supported formatted dates now remain in the layer renderer for message bodies and captions. Preparation preserves typed date metadata; malformed date values and other unsupported content retain the native fallback. Date hit testing, cursor behavior, menu priority, double/triple clicks, dragging, selection, cancellation and recycling are checked against native behavior. A nonselectable plain suffix still bubbles to its parent. Menu requests carry an identity/version token across cancellation and date callbacks, so synchronous replacement text menus and nested date menus supersede the outer request. Sender and forward-name bindings declare that they contain no dates, avoiding an unnecessary attribute scan. Menu state is allocated on activation rather than on each binding.

The same validation snapshot includes a separate native `FoldingInlineStickers` reuse correction. An explicit emoji tint must not be compared with the layer's base text color. Reuse now checks both values, including the distinction between no explicit tint and an explicit tint equal to the base color. The regression logs record 32 assertion failures in the first three tests against the original implementation, and 20 failures in the four-test explicit-color-collision reproduction. These are assertion counts, not counts of failing test cases. The final four tests cover repeated plain/quoted bindings, replacement on tint/base-color/file-ID/geometry changes, ownership, and removal of old layers.

### Validation and scope

Release, Address Sanitizer and Thread Sanitizer each pass 386 functional tests: 424 tests total, 38 optional measurements skipped, and no failures. Address Sanitizer leak detection is disabled. The added coverage comprises 13 date interaction tests, four live date binding tests and four emoji reuse tests. Twelve new date body bitmap pairs match exactly across scales and quote configurations. The suite also contains older Metal comparisons with their own tolerances; this is not a claim that every comparison in the suite is byte-exact.

The functional and timing snapshots each record 611 compiler inputs. Their non-baseline candidate sources and TGUIKit sources are byte-identical; the timing fixture changes the baseline modules, benchmark metadata label and package path. Four formatted-date production files and the native emoji reuse source match the archived validation hashes. The later TextView spoiler-reentry fix and separate `ChatLayerInlineEmoji` owner are outside this evidence. Implementation changes were included in commit `99d5a5d53`.

The lab compiles extracted production binding and engine code with real TGUIKit/AppKit. Account/media models and surrounding rows are fixtures. Emoji reuse uses a media-layer stand-in: it verifies constructor inputs and reuse/lifetime decisions, not real Lottie playback, network fetching, asynchronous cancellation or decoding. There is no full-app build or interactive chat validation in this pass.

### Immediate-pre-date comparison

Final timings use 49 captured engine/native-binding files from `QuoteRedrawVerified`, immediately before the formatted-date migration. Only module names are changed in those baseline files; original and renamed hashes are archived in `results/formatted-dates/timing/baseline-provenance.json`. This replaces the earlier exploratory pre-live-folding baseline. The checked-in generic generator and benchmark metadata still refer to that older baseline, so regenerating the generic lab alone does not reproduce these final numbers. Use the archived timing fixture below.

Both variants receive equivalent, independently owned attributed strings, layouts and typed date objects. Layouts are measured before timing. Each of 36 workloads has 20 warmup iterations and nine alternating batches: 150 operations per construction batch or 400 per repeated/recycled binding batch. A fresh second process reverses the initial order. The rows are unattached and unrasterized. Timings include complete extracted body/caption construction or binding; they exclude text measurement, media work, rasterization, full-app row content, scrolling and chat-opening latency.

Medians below are microseconds per operation, baseline → current. Full raw batches and all plain controls are in `results/formatted-dates/timing/{forward,reverse}.json` and `medians.md`.

| Workload | Forward | Reverse | Less time, forward / reverse |
| --- | ---: | ---: | ---: |
| Construct date body, 1 block | 21.792 → 17.972 | 20.943 → 17.951 | 17.5% / 14.3% |
| Construct date body, 3 blocks | 41.581 → 26.608 | 39.066 → 25.678 | 36.0% / 34.3% |
| Construct date body, 12 blocks | 115.533 → 63.412 | 116.261 → 65.036 | 45.1% / 44.1% |
| Construct date caption, 1 block | 36.519 → 33.095 | 33.998 → 30.974 | 9.4% / 8.9% |
| Construct date caption, 3 blocks | 52.786 → 39.659 | 52.418 → 40.601 | 24.9% / 22.5% |
| Construct date caption, 12 blocks | 128.878 → 76.436 | 129.809 → 78.871 | 40.7% / 39.2% |
| Same date body, 12 blocks | 15.410 → 8.217 | 15.137 → 8.243 | 46.7% / 45.5% |
| Same date caption, 12 blocks | 15.383 → 11.390 | 15.267 → 11.300 | 26.0% / 26.0% |
| Recycle date body, 12 blocks | 16.522 → 14.991 | 16.634 → 14.724 | 9.3% / 11.5% |
| Recycle date caption, 1 block | 3.036 → 3.079 | 2.871 → 2.944 | -1.4% / -2.5% |

Repeated date-body binding takes 38–47% less time across block counts; repeated date-caption binding takes 16–26% less. Recycling gains are smaller: body binding improves 4–12%, while single-block caption recycling adds 0.04–0.07 µs. This is not a universal binding speedup.

Plain controls preserve the existing layer renderer on both sides. Their construction results range from 3.6% less time to 5.3% more; the latter is the single-block body in the reversed run, adding 0.94 µs. Plain repeated/recycled binding stays within about 2.2% in these runs. Small regressions remain visible in the raw results instead of being excluded from the comparison.

For 1/3/12 date blocks, fixture view counts fall from 3/5/14 to 2 for bodies and 5/7/16 to 4 for captions, including their enclosing fixture views. Plain view counts stay at 2 and 4 respectively. The runtime instance size of each text node grows from 480 to 488 bytes; message nodes stay at 376 bytes. These counts and runtime sizes do not measure total retained process memory, allocator overhead or backing-store cost. No whole-app memory percentage or frame-rate gain is inferred.

Compiler checks found no `swift-frontend`, `xcodebuild` or `clang` before or after either timing process. They were not continuous monitoring. Other agents authored sources/fixtures and performed targeted reads without running builds during timing.

### Reproduce the archived snapshots

The archives contain the generated fixture sources and their TGUIKit snapshot. Some small local package dependencies remain external; their exact files are recorded in each `compiler-inputs.json`. The following preparation verifies every archived input and external dependency before changing only the two package paths. It fails rather than silently testing changed dependencies. Run it from the repository root with a fresh destination; it does not invoke a build.

```sh
python3 - <<'PY'
from pathlib import Path
import hashlib, json, tarfile
repo = Path.cwd().resolve()
recorded_repo = Path('/Users/renoir/projects/Telegram/telegrammacos')
evidence = repo / 'tools/perflab/ChatLayerEngineLab/results/formatted-dates'
for kind, original, destination in [
    ('validation', '/private/tmp/FormattedDateCheck', '/tmp/FormattedDateReplay'),
    ('timing', '/private/tmp/FormattedDateTiming', '/tmp/FormattedDateTimingReplay')
]:
    output = Path(destination)
    output.mkdir()
    with tarfile.open(evidence / kind / 'fixture-sources.tar.gz') as archive:
        archive.extractall(output, filter='data')
    for name, digest in json.loads((evidence / kind / 'compiler-inputs.json').read_text()).items():
        source = Path(name)
        path = output / source.relative_to(original) if source.is_relative_to(original) else repo / source.relative_to(recorded_repo)
        assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, str(path)
    for manifest in [output / 'Package.swift', output / 'TGUIKit/Package.swift']:
        manifest.write_text(manifest.read_text().replace(original, str(output.resolve())).replace(str(recorded_repo), str(repo)))
PY
swift test --package-path /tmp/FormattedDateReplay --scratch-path /tmp/FormattedDateReplay-release -c release
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/FormattedDateReplay --scratch-path /tmp/FormattedDateReplay-asan --sanitize address
swift test --package-path /tmp/FormattedDateReplay --scratch-path /tmp/FormattedDateReplay-tsan --sanitize thread
swift test --package-path /tmp/FormattedDateTimingReplay --scratch-path /tmp/FormattedDateTimingReplay-release -c release --filter FormattedDateBenchmarkTests
CHAT_FORMATTED_DATE_BENCHMARK=1 CHAT_FORMATTED_DATE_OUTPUT=/tmp/formatted-date-forward.json swift test --package-path /tmp/FormattedDateTimingReplay --scratch-path /tmp/FormattedDateTimingReplay-release -c release --skip-build --filter FormattedDateBenchmarkTests
CHAT_FORMATTED_DATE_BENCHMARK=1 CHAT_FORMATTED_DATE_REVERSE=1 CHAT_FORMATTED_DATE_OUTPUT=/tmp/formatted-date-reverse.json swift test --package-path /tmp/FormattedDateTimingReplay --scratch-path /tmp/FormattedDateTimingReplay-release -c release --skip-build --filter FormattedDateBenchmarkTests
```

Use a Python version supporting `tarfile`'s `data` extraction filter. Run all builds and measurements sequentially. The first timing-fixture invocation compiles the optional benchmark and skips measurement; the next two invocations measure in separate processes. The archived preparation script also records how the immediate-pre-date baseline was assembled, but depends on the original temporary directories; the source archives above remove that dependency.

## Inline custom emoji integration

`LiveInlineEmojiTests` exercises the exact production message-text host and the extracted body/caption binding and animation-update methods. Only ordinary looped `.attribute` emoji are eligible. Quotes containing emoji, folding mixtures, spoilers, streaming, avatars, non-looping policies, unsupported sources and unmatched raw custom-emoji metadata retain the native renderer. Existing text-only quotes and formatted dates retain their current paths.

The host owns helpers only for blocks containing media and one shared visibility observer. Coverage includes body/caption placement at 1×/2×/3×, duplicate occurrences, tint/account replacement, selection and copied attributes, caption reordering, immediate removal cleanup, scroll/key/lite/hidden visibility, observer detachment and synchronous constructor reentry. The new TelegramContext, InputView and InlineStickerLayer modules are explicit account/media stand-ins; the deterministic bitmap layer does not fetch, decode, or play real Lottie media. The older native folding fixtures retain their separate fake media type as unsupported-content controls. Account contexts in the current folding-view harness bridge to the new account module; archived baseline fixtures stay unchanged.

The actual media constructor uses fetch mode `.always`, can initialize resources synchronously before playback is disabled, and releases subscriptions on layer deinitialization. Visibility flags do not prove request cancellation. These tests exercise ownership/placement/observer contracts, not real media service behavior. The helper passes a real-dependency API typecheck, and the full fixture release/sanitizer regressions pass as recorded below. A full application build and live media playback validation remain outstanding. No performance gain is claimed until measured.

Preparation records the production, stand-in, integration-test and generator hashes in `inline-emoji-integration-provenance.json`; previously recorded helper-only results predate this integration.

### Live inline emoji validation

The frozen live body/caption candidate passes 434 tests (396 functional, 38 optional skips) in each of release, Address Sanitizer and Thread Sanitizer. Address Sanitizer leak detection is disabled. All 618 compiler inputs were reverified after the runs. Evidence, exact generated sources, production snapshots, repair provenance and diagnostic logs are in `results/live-inline-emoji`.

Ten new integration tests cover native placement at three scales with LTR/RTL text, source/color/account reuse, occurrence identity, selection/copy metadata, caption reordering, observer visibility and reentrant construction. The tests exposed abandoned media on a fresh body host when synchronous construction reentered the row binding; cleanup now releases that unpublished host while preserving the newest active host. Earlier failures also included a test traversal that missed AppKit's disconnected backing layers; the corrected fixture traverses both view and layer ownership without duplicate counting.

The fixtures use static media stand-ins. This validates UI ownership, metadata, geometry and visibility decisions; it does not prove real Lottie decode, asynchronous fetch completion or player restart behavior. No whole-app build or performance gain is established by these correctness runs. A separate immediate-baseline binding lab supplies the rendering preflight and performance comparison.
