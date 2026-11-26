# Bubble backdrop hosting (parked)

`bubble-hosting.patch` hosts `ChatMessageBubbleBackdrop`'s background, border and mask in the row's layer (text rows only) the same way the date/status layer is hosted. It is parked because the parity lab never reached byte equality:

- First runs: 19/24 hosted rows differed by at most 2/255 in the bubble's two vertical edge columns.
- Cause found with the lab's layer dump (`-PerfLabParityDumpRow`): the native backing layer of the non-flipped backdrop view inside the flipped row is `isGeometryFlipped`, and AppKit samples the mask's 9-slice `contentsCenter` with y mirrored. Hosting with the same flip and a mirrored `contentsCenter.y` (`ChatBubbleSliceLayer.mirrorsCenterVertically`) matches for captures taken 0.7 s after binding (0 differences in 19 rows).
- Captured 1.2 s after binding, the hosted bubble's edge column drifts by 1/255 again while every model and presentation property (frames, flip, contentsCenter, scale, filters, no animations) is identical to native. The drift is time dependent on the hosted side only, which points at WindowServer re-rasterizing/caching static masked layers differently from AppKit backing layers. Not shipped: the gate is byte equality.

Patch also contains the handoff's untested AvatarLayer tracking change; ignore that part when reapplying.
