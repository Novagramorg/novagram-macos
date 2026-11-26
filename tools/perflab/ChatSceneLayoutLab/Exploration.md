# Candidate selection

A rounded-clip hit-test fast path was considered first. The source audit found that production ChatLayerNode clipping is enabled by quote clipping, whose rounded mask uses a separate layer rather than the node cornerRadius. The prototype row also sets cornerRadius without enabling clipsChildren. Optimizing CGPath construction in allowsHit would therefore mainly benefit synthetic clipped-node fixtures. That candidate was not applied or benchmarked.

This lab instead examines unconditional index invalidation in ChatLayerSceneView.layout. All documented node geometry APIs invalidate the index already. The candidate retains it when the root frame is unchanged, while still processing tooltip synchronization, hover and link-preview movement on every layout.
