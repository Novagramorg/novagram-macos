# Rejected forwarded-header view migration

This experiment is intentionally excluded from production. It replaced the forwarded-message header TextView with the shared text layer, added a lazily created accessibility element, propagated scale changes, and preserved double-click reply exclusion over the header. It removed one view and its embedded-container layer. The row integration and wrapper rename are recorded in `production.patch.txt`; the new production file is preserved separately.

Sixteen functional tests ran with one failure (and one optional benchmark skipped). Ordinary header rendering, accessibility values/frames/parents, event forwarding, lifecycle checks, 1,800 hit-test points, and movement/removal GPU frames passed. The overlapping-sibling test failed: 490 pixels differ at zero tolerance when an existing sibling should remain behind the header. AppKit puts manual layers before its view backing layers when committing the tree. Inserting the header above/below its recorded neighbor from `layout()` did not survive that reordering. Setting the header above every sibling would change the opposite overlap case, so that was not accepted.

The shipped renderer foundation and chat metadata optimization remain in commit `b99c48ba7`. This fixture records why blanket TextView-to-layer substitution is unsafe in a mixed AppKit view/layer hierarchy. A subsequent migration must preserve native stacking as well as accessibility and event behavior. The actual header remains a TextView.

## Reproduce the expected failure

```sh
python3 tools/perflab/TextViewLayerLab/experiments/ForwardHeader/prepare.py /tmp/TextViewLayerHeaderRejected
swift test --package-path /tmp/TextViewLayerHeaderRejected/TextViewLayerLab --scratch-path /tmp/TextViewLayerHeaderRejected-build
```

The preparation script first builds the normal lab copy, then injects the experimental container, preserved old header methods and extra tests. No production files are modified. Swift fixtures have `.txt` suffixes so ordinary lab runs do not compile them. This is a deliberately failing experiment, not a production regression suite.

`rejected-debug.log` records the entire comparison run. `rejected-stacking.log` includes native layer order and the differing-pixel count. The 16 saved GPU images are paired old/new captures for movement and fade-out, held at deterministic animation offsets. They prove the animation raster pairs matched; they do not resolve the sibling-order failure or measure wall-clock animation pacing.
