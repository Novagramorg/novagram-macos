# TextNode layout reuse

The original cache did not record the selection state passed to measurement. Selected text therefore missed reuse on every request. It also compared the selected-color-transformed string with the untransformed input. Conversely, changed line spacing was absent from the reuse check, and mutable input text was retained as its own comparison value, allowing stale geometry and pixels after mutation.

The candidate stores the original immutable attributed-string snapshot, records the rendered selection and effective line spacing, and compares those inputs before reuse. The public mutable `selected` property remains available; a separate rendered-state flag prevents relabeling old pixels by changing that property. Nil and zero spacing remain equivalent. No global cache is introduced. The previously unused stored background color is removed: drawing has always received its background separately. The renderer and measurement arithmetic are unchanged.

## Reproduce

From the repository root:

```sh
python3 tools/perflab/TextNodeReuseLab/prepare.py
TEXTNODE_BENCHMARK=1 swift test --package-path tools/perflab/TextNodeReuseLab --scratch-path /tmp/TextNodeReuseLab-release -c release
swift test --package-path tools/perflab/TextNodeReuseLab --scratch-path /tmp/TextNodeReuseLab-asan --sanitize address
swift test --package-path tools/perflab/TextNodeReuseLab --scratch-path /tmp/TextNodeReuseLab-tsan --sanitize thread
```

The lab imports actual TGUIKit. Its generator obtains TextNode from commit `058cd5cf5`, renames its types and adds a testable TGUIKit import. That reference uses the unchanged shared glyph-run drawing helper. Generation hashes and a frozen baseline source accompany the evidence. The initial five regression tests failed with eight expected assertions against the unchanged library, then passed after the fix.

## Coverage and limits

The final suite has 11 functional tests and one opt-in benchmark. It covers repeated selection, mutable text and color changes, selected-color changes, equal independent strings, nil/empty input, nil/zero spacing, public selection mutation, every existing geometry reuse key, selection round trips, and releasing replaced layouts.

A matrix compares 60 nonblank bitmap pairs at 1x and 2x against the original renderer. It covers Latin, RTL, emoji and multiline text with truncation, different line limits, cutouts, alignment and spacing. Additional regression tests compare reused results with fresh measurement when inputs change. These are CoreText renderings in an isolated mini-app, not full Telegram screenshots.

Nine paired benchmark batches alternate execution order and perform 1,000 calls each. They distinguish fresh construction from reuse and identical immutable, equal independent immutable, and mutable inputs. Both implementations are initially measured before each case. Raw timings are archived; no timing threshold is used as a correctness assertion. Input objects are prepared outside timing, so the benchmark does not include a caller's attributed-string construction cost.

Layout instance size and direct allocation size remain 128 bytes on the measured host. This does not measure retained CoreText buffers or whole-process memory. Copying mutable source text on a miss is intentional for correctness; it can add work to fresh measurement. The benefit is avoiding repeated CoreText measurement on valid selected cache hits and preventing stale results when inputs change.

No full Telegram build or end-to-end chat scrolling benchmark was performed. Regression-suite results and exact source hashes are recorded in `provenance.json`.

## Recorded release medians

Microseconds per call; these cover only layout requests, not complete rows:

| Input and operation | Original | Candidate |
| --- | ---: | ---: |
| input=equal,selected=false,reuse=false | 10.1362 | 10.2887 |
| input=equal,selected=false,reuse=true | 0.0313 | 0.0345 |
| input=equal,selected=true,reuse=false | 10.9594 | 11.0731 |
| input=equal,selected=true,reuse=true | 11.0060 | 0.0369 |
| input=mutable,selected=false,reuse=false | 10.3061 | 10.3959 |
| input=mutable,selected=false,reuse=true | 0.0425 | 0.0445 |
| input=mutable,selected=true,reuse=false | 10.9802 | 11.2143 |
| input=mutable,selected=true,reuse=true | 10.9003 | 0.0463 |
| input=same,selected=false,reuse=false | 10.1774 | 10.3147 |
| input=same,selected=false,reuse=true | 0.0105 | 0.0129 |
| input=same,selected=true,reuse=false | 10.8255 | 11.0378 |
| input=same,selected=true,reuse=true | 10.9063 | 0.0132 |
