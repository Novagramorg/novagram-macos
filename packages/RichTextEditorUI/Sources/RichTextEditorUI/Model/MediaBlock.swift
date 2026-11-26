#if canImport(AppKit)
import Foundation
import RichTextEditorCore

/// The category of an embedded media attachment. `file`/`audio`/`map`/`video` are hosted as app-injected
/// interactive views (the chat content nodes, via `registerMediaBlockViewProvider`); `image` is drawn
/// directly as a full-bleed bitmap by the canvas (resolved from `mediaID` via the image provider).
@available(macOS 12, *)
enum MediaKind: String, Equatable {
    case file
    case audio
    case map
    case image
    case video
}

/// Where a full-bleed image sits horizontally within the content strip (image kind only).
@available(macOS 12, *)
enum ImageAlignment: String, Equatable {
    case left
    case center
    case right
}

/// A macOS-only embedded-media block (file / audio / map / image). NOT part of the shared
/// `RichTextEditorCore` `Block` enum — adding cases there would break iOS (exhaustive switches +
/// bidirectional `Codable`). Stores only an opaque `mediaID`: the host resolves it to a real media
/// view for hosted kinds, and the canvas resolves it to an `NSImage` (via the image provider) for
/// `.image`. `naturalSize`/`alignment` are image-only; `height` caches the last size a hosted view
/// reported so the box settles to the right height.
@available(macOS 12, *)
struct MediaBlock: Equatable {
    var id: BlockID
    var kind: MediaKind
    /// Opaque content key — the host media-view key, or the image asset key for `.image`.
    var mediaID: String
    var displayWidth: CGFloat?
    var height: CGFloat?
    /// Image-only: intrinsic pixel size, drives aspect-preserved display sizing. Ignored for hosted kinds.
    var naturalSize: Size2D
    /// Image-only: horizontal placement of the full-bleed bitmap. Ignored for hosted kinds.
    var alignment: ImageAlignment
    /// Editable caption below the media, stored as formatted runs.
    var caption: [TextRun]
    /// Telegram-style spoiler: the medium is hidden behind an animated "dust" overlay until tapped.
    var spoiler: Bool

    init(id: BlockID, kind: MediaKind, mediaID: String, displayWidth: CGFloat? = nil, height: CGFloat? = nil,
         naturalSize: Size2D = Size2D(width: 0, height: 0), alignment: ImageAlignment = .center,
         caption: [TextRun] = [], spoiler: Bool = false) {
        self.id = id
        self.kind = kind
        self.mediaID = mediaID
        self.displayWidth = displayWidth
        self.height = height
        self.naturalSize = naturalSize
        self.alignment = alignment
        self.caption = caption
        self.spoiler = spoiler
    }
}

/// How a group of media (photos/videos, ≤10) is presented. `collage` = the chat's mosaic
/// (`GroupedLayout`); `slideshow` = a paging slider (deferred — the kind is reserved so a group can be
/// toggled to a slider later without a model migration).
@available(macOS 12, *)
enum MediaGroupKind: String, Equatable {
    case collage
    case slideshow
}

/// A macOS-only group of media shown as a collage mosaic (or, later, a slider), with one editable caption
/// below. Each `mediaID` resolves to a host media exactly like `MediaBlock.mediaID`. At most 10 items.
@available(macOS 12, *)
struct MediaGroupBlock: Equatable {
    var id: BlockID
    var kind: MediaGroupKind
    /// Opaque content keys, in order; the host resolves each to a real photo/video. ≤10.
    var mediaIDs: [String]
    var caption: [TextRun]
    /// Per-tile Telegram-style spoiler flags, parallel to `mediaIDs` (padded/truncated to match).
    var spoilers: [Bool]

    init(id: BlockID, kind: MediaGroupKind = .collage, mediaIDs: [String], caption: [TextRun] = [], spoilers: [Bool] = []) {
        self.id = id
        self.kind = kind
        let ids = Array(mediaIDs.prefix(10))
        self.mediaIDs = ids
        self.caption = caption
        self.spoilers = (0 ..< ids.count).map { $0 < spoilers.count ? spoilers[$0] : false }
    }
}

/// The canvas's internal block currency. The undo snapshot + `setModelBlocks` round-trip in
/// `CanvasModelBlock` (not `[Block]`) so the macOS-only `.media` (file/audio/map/image/video) and
/// `.mediaGroup` (collage) blocks survive editing/undo; the public `Document`/`[Block]` boundary maps
/// `.core` through and drops the rest (persistence of media blocks is deferred — see the design doc).
@available(macOS 12, *)
enum CanvasModelBlock: Equatable {
    case core(Block)
    case media(MediaBlock)
    case mediaGroup(MediaGroupBlock)
}
#endif
