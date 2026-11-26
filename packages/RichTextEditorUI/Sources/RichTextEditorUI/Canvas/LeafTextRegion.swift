#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// One editable text region produced by a block's recursive enumeration. `globalStart`/`length`
/// are absolute positions in the document; `canvasOrigin` is where `layout` offset 0 draws in
/// canvas coordinates. (A paragraph yields one; an image yields its caption; a table flat-maps
/// over its cells' stacks.)
@available(macOS 12, *)
struct LeafTextRegion {
    let layout: BlockLayout
    let globalStart: Int
    let length: Int
    let ref: TextNodeRef
    let canvasOrigin: CGPoint
}
#endif
