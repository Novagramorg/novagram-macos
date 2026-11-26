#if canImport(AppKit)
import AppKit
import RichTextEditorCore

@available(macOS 12, *)
extension DocumentCanvasView {
    /// The media under `point` (canvas coords): an image (bitmap), a media group (collage/slider), or a
    /// single hosted media (file/audio/map/video) — by its media-area band. For the host context menu.
    func mediaContext(atCanvasPoint p: CGPoint) -> EditorMediaContext? {
        if let img = imageBoxAtCanvasPoint(p) { return EditorMediaContext(blockID: img.id.rawValue, kind: "image") }
        for case let g as MediaGroupBlockBox in boxes where p.y >= g.frame.minY && p.y < g.textOrigin.y {
            return EditorMediaContext(blockID: g.id.rawValue, kind: g.kind.rawValue)
        }
        for case let m as MediaBlockBox in boxes where p.y >= m.frame.minY && p.y < m.textOrigin.y {
            return EditorMediaContext(blockID: m.id.rawValue, kind: m.kind.rawValue)
        }
        return nil
    }

    /// The image whose drawn bitmap (`imageRect`) contains `point` (canvas coords) — for click-to-select.
    /// The caption below is a normal text region and is NOT matched here (clicking it edits the caption).
    func imageBoxAtCanvasPoint(_ point: CGPoint) -> ImageBlockBox? {
        for case let img as ImageBlockBox in boxes where img.imageRect().contains(point) { return img }
        return nil
    }

    /// Clicking an image selects it (covers its atom, so it shows the accent wash and Backspace removes it),
    /// mirroring `selectMediaBlock`. A second click toggles the selection off (caret before the atom).
    func selectImageBlock(_ box: ImageBlockBox) {
        window?.makeFirstResponder(self)
        if soleSelectedImageBlock()?.id == box.id {
            setCaret(global: box.nodeStart)   // second click → deselect (clears the accent wash)
            return
        }
        setCaret(global: box.nodeStart)
        setSelectionHead(global: box.textStart)
    }

    /// Image blocks whose atom (the gap before the caption) lies inside the current selection.
    func imageBoxesInSelection() -> [ImageBlockBox] {
        guard selFrom != selTo else { return [] }
        return boxes.compactMap { $0 as? ImageBlockBox }.filter { selFrom <= $0.nodeStart && $0.nodeStart < selTo }
    }

    /// The single image the selection is confined to (a click-select "handle" — covers only the atom, not
    /// caption text). Lets Backspace/Delete remove a click-selected image. Mirrors `soleSelectedMediaBlock`.
    func soleSelectedImageBlock() -> ImageBlockBox? {
        let imgs = imageBoxesInSelection()
        guard imgs.count == 1, let img = imgs.first else { return nil }
        return (selFrom >= img.nodeStart && selTo <= img.textStart) ? img : nil
    }

    /// Draws the selection wash over each click-selected image's bitmap (the cross-block text-selection
    /// `selectionRects` only covers text regions, so a selected image atom would otherwise show no accent).
    func drawImageSelectionHighlight(in ctx: CGContext) {
        let selected = imageBoxesInSelection()
        guard !selected.isEmpty else { return }
        let color = (window?.firstResponder === self ? editorAppearance.selectionFocused : editorAppearance.selectionUnfocused)
        color.setFill()
        for img in selected { ctx.fill(img.imageRect()) }
    }
}
#endif
