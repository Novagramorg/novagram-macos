#if canImport(AppKit)
import Foundation
import RichTextEditorCore

/// A send-oriented, media-preserving view of the editor's content. Unlike the `Document` / `[Block]`
/// boundary (which drops media — persistence is deferred there), this carries the macOS-local media and
/// media-group blocks as opaque `mediaID`s plus a `kind` string, so a host can resolve them to real `Media`
/// and serialize the whole document (e.g. into an InstantPage rich message). It exposes only public Core
/// types (`ParagraphBlock`/`TableBlock`/`CodeBlock`/`TextRun`) + strings, so the internal canvas model
/// (`CanvasModelBlock`/`MediaBlock`/…) stays encapsulated and there's no `MediaBlock` name clash for hosts.
/// (Ungated: it wraps only `RichTextEditorCore` value types, so a host can name it without `@available`.)
public enum RichTextOutgoingBlock: Equatable {
    case paragraph(ParagraphBlock)
    case table(TableBlock)
    case code(CodeBlock)
    case pullQuote(PullQuote)
    /// A recursive block-quote container: nested outgoing blocks + the collapse flag.
    indirect case blockQuote(children: [RichTextOutgoingBlock], collapsed: Bool)
    /// `kind` ∈ "image" / "video" / "file" / "audio" / "map". `spoiler` hides it behind the dust overlay.
    case media(kind: String, mediaID: String, caption: [TextRun], spoiler: Bool)
    /// `kind` ∈ "collage" / "slideshow". `spoilers` is parallel to `mediaIDs` (per-tile).
    case mediaGroup(kind: String, mediaIDs: [String], caption: [TextRun], spoilers: [Bool])
    /// A block-level row of InstantPage buttons (`ButtonRowBlock` is a pure Core value type).
    case buttonRow(ButtonRowBlock)
}

public extension RichTextOutgoingBlock {
    /// Core → outgoing (recursive for `blockQuote`). Core media blocks return nil (not produced on macOS).
    init?(core: Block) {
        switch core {
        case .paragraph(let p): self = .paragraph(p)
        case .table(let t): self = .table(t)
        case .code(let c): self = .code(c)
        case .pullQuote(let pq): self = .pullQuote(pq)
        case .blockQuote(let bq):
            self = .blockQuote(children: bq.children.compactMap { RichTextOutgoingBlock(core: $0) }, collapsed: bq.collapsed)
        case .buttonRow(let r): self = .buttonRow(r)
        case .media: return nil
        case .details: return nil
        }
    }

    /// Outgoing → Core, when the case is representable as a pure Core block (media/mediaGroup → nil;
    /// media nested inside a block quote is dropped).
    var coreBlock: Block? {
        switch self {
        case .paragraph(let p): return .paragraph(p)
        case .table(let t): return .table(t)
        case .code(let c): return .code(c)
        case .pullQuote(let pq): return .pullQuote(pq)
        case .blockQuote(let children, let collapsed):
            return .blockQuote(BlockQuote(id: BlockID.generate(), children: children.compactMap { $0.coreBlock }, collapsed: collapsed))
        case .buttonRow(let r): return .buttonRow(r)
        case .media, .mediaGroup: return nil
        }
    }
}
#endif
