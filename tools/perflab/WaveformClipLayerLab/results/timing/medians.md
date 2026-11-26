Medians are microseconds per operation. Negative savings mean the current variant took longer.

| Workload | Original → current, forward | Original → current, reverse | Less time, forward / reverse |
| --- | ---: | ---: | ---: |
| animated_retarget_100 | 1.754542 → 1.084917 | 1.667041 → 1.043125 | 38.2% / 37.4% |
| animated_retarget_200 | 1.780792 → 1.106208 | 1.759791 → 1.109459 | 37.9% / 37.0% |
| attached_resize_layout_100 | 2.020917 → 2.000166 | 1.946917 → 1.936417 | 1.0% / 0.5% |
| attached_resize_layout_200 | 1.946083 → 1.932249 | 1.983416 → 1.925251 | 0.7% / 2.9% |
| changing_immediate_clip_100 | 0.451958 → 0.148416 | 0.474125 → 0.155250 | 67.2% / 67.3% |
| changing_immediate_clip_200 | 0.454583 → 0.148542 | 0.464333 → 0.146917 | 67.3% / 68.4% |
| construct_100 | 11.574862 → 6.377917 | 11.464724 → 6.274306 | 44.9% / 45.3% |
| construct_200 | 11.990972 → 6.698055 | 11.565277 → 6.469165 | 44.1% / 44.1% |
| construct_configure_100 | 12.433333 → 6.770417 | 12.609305 → 6.741527 | 45.5% / 46.5% |
| construct_configure_200 | 12.642083 → 6.867917 | 12.692640 → 6.806112 | 45.7% / 46.4% |
| same_immediate_clip_100 | 0.021062 → 0.024125 | 0.020667 → 0.024562 | -14.5% / -18.9% |
| same_immediate_clip_200 | 0.018917 → 0.024437 | 0.018667 → 0.024104 | -29.2% / -29.1% |

Each memory process retains 2,000 unattached, unrasterized waveform views after warming both variants. Deltas include allocator/framework storage.

| Process | Footprint before | Footprint after | Footprint increase | Resident increase | Views | Connected root layers |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| original-1 | 9,945,832 B | 23,347,968 B | 13,402,136 B | 13,451,264 B | 4,000 | 4,000 |
| current-1 | 9,994,960 B | 17,924,816 B | 7,929,856 B | 7,995,392 B | 2,000 | 8,000 |
| current-2 | 9,962,240 B | 17,892,096 B | 7,929,856 B | 7,995,392 B | 2,000 | 8,000 |
| original-2 | 9,896,704 B | 23,266,048 B | 13,369,344 B | 13,434,880 B | 4,000 | 4,000 |

The original `layers`/`layers_100`/`layers_200` fields count only the connected root subtree: two baseline versus four candidate layers per waveform before attachment. They do not count the two other layers already retained through the baseline child NSView. Source ownership remains four model layers per waveform; the later counter traverses all view backing layers and deduplicates them. Raw files are unchanged.

Footprint increases are 12.75–12.78 MiB baseline versus 7.5625 MiB candidate. The paired differences are 5.19–5.22 MiB (40.7–40.8% of this fixture’s incremental allocation), approximately 2.66–2.67 KiB per retained waveform. This is not a whole-app memory percentage.

Both timing processes use nine alternating batches and opposite initial order. All six process logs report a passing optional test; all pre/post compiler checks are empty. These are boundary checks, not continuous process monitoring. All 418 frozen compiler-input hashes were rechecked while archiving. The later ownership-count correction is test-only and is not part of this measured snapshot.
