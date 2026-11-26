# Passive reaction layers — 2026-10-18

Fixture `/tmp/ReactionPassiveFix2`, frozen by `prepare.py`, then regenerated in place with `generate.py` after each production edit. The test file was copied in after the tag-image change.

- Before: 9 tests, 155 failures (`before-fix-diagnostic.log`).
- After copying the native `edgeAntialiasingMask = 0`: 74 failures, all selected tags (`after-edge-mask-only.log`).
- After the tag background layer (inserted at index 0, geometry flipped like the native NinePathImage layer) and the bitmap-backed production-style tag image: 10 tests, 0 failures in release and Address Sanitizer.
- The bounded oracle applies to the selected tag background only. Its negative controls (flip, hide, fade) must fail at 1x, 2x and 3x.
- Production ChatUI type-check against DerivedData: exit 0 (`chatui-typecheck.log`). TelegramMedia was re-emitted because DerivedData predated 530a24052.

Release medians, microseconds per operation, native / layers (forward run; the reverse run agrees within 2 %):

| Operation | Ordinary chip | Tag chip |
| --- | ---: | ---: |
| Construct, unselected | 24.86 / 13.16 | 18.56 / 13.15 |
| Construct, selected | 30.64 / 14.87 | 23.03 / 14.59 |
| Changing bind | 3.16 / 1.16 | 2.55 / 0.92 |
| Remove + restore text | 7.73 / 1.98 | 7.85 / 2.07 |
| Same bind | 0.50 / 0.55 | 0.50 / 0.29 |
| Attached resize | 1.61 / 1.66 | 1.55 / 1.60 |

NSViews per chip: ordinary 5 → 2, tag 4 → 2. Unattached, unrasterized component timings; no scroll FPS or app memory claim.
