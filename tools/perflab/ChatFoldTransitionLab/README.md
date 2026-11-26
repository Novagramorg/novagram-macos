# Collapsible quote transition prototype

This records the tested prototype at commit `72df16a49`, before live eligibility changed. The subsequent integration is documented in [ChatLayerEngineLab](../ChatLayerEngineLab/README.md#foldable-quotes-in-live-message-and-caption-bindings). Reproduce this historical prototype from its recorded commit; its source checks intentionally reject newer production implementations.

The candidate adds an explicit layout transition to message-text and text-node binding. Existing blocks of the same message animate frame changes, quote clipping, background geometry and arrow position. New message identities bind immediately. Collapse defers the text fade mask until the transition ends; a generation check and weak references prevent delayed work from mutating reused content or retaining a removed node. A message-level flag limits geometry-animation cleanup to hosts that have animated. The flag adds stored state; its memory and time costs have not yet been measured.

The first prototype exposed a delayed mask applying to a removed node and a following plain block retaining a position animation across message reuse. Both have regression tests. The initial fixture also looked for the quote mask on the outer layer; native and layer wrappers attach that shared mask to the quote background. The corrected comparison inspects that actual mask. Original failures and the corresponding candidate sources are retained in results.

Six new tests cover native/candidate clipping animation endpoints, duration and timing function, arrow and block geometry animations, exact final rendered pixels in both reveal directions, delayed-mask cancellation on expansion/plain replacement/removal, node lifetime, following-block movement, new message identity, immediate rebinding, and rapid toggling across multiple blocks. These tests compare animation parameters and final raster output; they do not measure presented intermediate frames or full-app scrolling.

The frozen release suite passes 342 functional tests, with 34 optional measurements skipped (376 total). All 402 recorded source/test/manifest files were verified after the run. Existing tests include folded/expanded pixel parity, selection, links, keyboard/accessibility actions and native fallback behavior. No sanitizer or timing run has been performed for this prototype. The tested change is not yet enabled or committed as production code.

## Reproduce

```sh
python3 tools/perflab/ChatFoldTransitionLab/prepare.py /tmp/ChatFoldTransitionCheck
swift test --package-path /tmp/ChatFoldTransitionCheck --scratch-path /tmp/ChatFoldTransitionCheck-build -c release
```

The generator freezes the existing ChatLayerEngineLab, verifies the two original engine sources, installs the archived candidate sources and adds the six tests plus a test-only native-wrapper update function. Other sources and dependencies come from the checkout, so compare compiler inputs before treating later runs as reproductions of the recorded evidence.

## Remaining integration work

Enable supported collapsible quote presentations in the actual message and caption hosts, with callbacks bound to the current item and caption identity. Pass animated updates through the host, preserve current selection/reentrancy/fallback guarantees, and test renderer changes during reflow and rich-content updates. Validate complete binding and construction performance against the original production path, exercise attached-window transitions, then run sanitizers on the final integration. Only after those checks should the live eligibility change.
