#if canImport(AppKit)
import CoreGraphics

/// Document-level layout metrics shared across block types.
@available(macOS 12, *)
enum CanvasMetrics {
    /// Horizontal page margin: text/tables inset by this; images bleed past it to the canvas edge.
    static let pageMargin: CGFloat = 16
    /// Max height of a media area (single image/video, collage mosaic, or slider). Taller content is
    /// reserved at this height and its hosted view is clamped to it, so media never dominates the document.
    static let maxMediaHeight: CGFloat = 320
}
#endif
