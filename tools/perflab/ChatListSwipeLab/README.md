# Chat-list navigation swipe lab

Every navigation swipe update previously scanned all loaded chat-list rows and called the full ChatListRowView.set(item:) method on each existing chat row. The progress value only controls content and compact-badge opacity. The full binding path also visits text, avatar, media, activity, badge and layout work that does not depend on that value.

The controller now uses TGUIKit's existing available-row enumeration. Rows update the two opacity values directly while their split layout matches the bound item. A changed split layout retains the full binding path. Normal data/theme updates still call set(item:). No cache or per-row state was added. Available-row enumeration uses its existing small temporary array of item/view pairs; that allocation is included in the traversal benchmark.

A newly created compact badge now starts at the current gesture opacity, including its fade target. Previously it started fully opaque midway through a gesture. A progress callback that rebinds the view cannot overwrite the new binding's opacity.

## Harness and boundaries

prepare.py extracts the exact progress method, initial content-opacity block, compact-badge binding block, trailing layout invalidations, controller swipe method and progress getter from production. The reference comes from commit 590fd8894. Both variants compile together against the real TGUIKit package. AppKit windows, CALayer opacity/animations and TableView enumeration are real.

Telegram account and row models, badge content, controller navigation layout and the unrelated portions of the full row binding are adapters. The binding counter proves entry into set(item:), not how much CPU its omitted portions use. Rendering comparisons use colored content and badge fixtures, not complete Telegram chat-list cells. No full ChatListUI/Telegram build, account/network test, retained-memory measurement or end-to-end FPS claim is made.

The tests cover progress and nil progress, cancellation and completion, hidden/visible content, missing badges and live-item suppression, new badge creation, animation targets, row replacement, reentrant progress callbacks, split-layout fallback, missing/non-chat items, explicit layout requests, controller eligibility, scrolling/removal, stale-index fallback and model-layer pixel parity at 1x/2x. Hidden windows initialize backing-layer geometry before capture. Sixteen capture comparisons require both byte identity and nonempty output.

## Measurements

A native table with eight existing row views performs 200 traversals per batch. Eleven paired batches alternate baseline/candidate order. The measured callback only increments a counter. Times exclude row binding and drawing.

| Loaded rows | Full scan median | Existing-row median |
| ---: | ---: | ---: |
| 100 | 3.42 µs | 0.61 µs |
| 1,000 | 35.97 µs | 0.64 µs |
| 10,000 | 351.23 µs | 0.66 µs |

The ordinary gesture regression sends 121 updates. The reference invokes 121 additional full row bindings and badge display requests; the candidate invokes zero. The controller test verifies the same property for its existing rows and verifies final/cancelled opacity values. This eliminates repeated work but does not quantify whole-app memory or gesture latency.

## Running

```sh
python3 tools/perflab/ChatListSwipeLab/prepare.py
swift test --package-path tools/perflab/ChatListSwipeLab --scratch-path /tmp/ChatListSwipeLab-release -c release
swift test --package-path tools/perflab/ChatListSwipeLab --scratch-path /tmp/ChatListSwipeLab-asan --sanitize address
swift test --package-path tools/perflab/ChatListSwipeLab --scratch-path /tmp/ChatListSwipeLab-tsan --sanitize thread
SWIPE_BENCHMARK=1 swift test --package-path tools/perflab/ChatListSwipeLab --scratch-path /tmp/ChatListSwipeLab-release -c release --filter TableSwipeTests.testAvailableRowEnumerationBenchmark
```

Run these sequentially. The benchmark writes /tmp/chat-swipe-enumeration.json. The generated Swift file is intentionally ignored. Use prepare.py --baseline to compile the old code as both variants and reproduce the expected failing regression assertions; run prepare.py again afterward to restore the current variant.

## Validation recorded for this change

All 14 functional tests passed in release, Address Sanitizer and Thread Sanitizer configurations (15 total; one opt-in benchmark skipped). Thread Sanitizer reported no races. The expanded baseline run produced 13 expected assertion failures and zero unexpected failures. Both complete production files also passed the Swift parser; the extracted methods were typechecked by the standalone package build.

The benchmark passed separately. Source hashes, generated source snapshots, baseline production snapshots, raw paired samples and test logs are recorded in provenance.json and results/. These tests establish the behaviors above within the adapter boundaries; they do not replace a full application UI test.
