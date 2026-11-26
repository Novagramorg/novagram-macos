#if canImport(AppKit)
import AppKit
import RichTextEditorCore

@available(macOS 12, *)
extension DocumentCanvasView {
    struct BlockquoteDecoration { let fill: CGRect; let bar: CGRect }

    /// One bar+fill rect pair per `BlockQuoteBox` (recursively, so nested quotes each get their own
    /// fill), in canvas coordinates. The block frames are already inset by the page margin (root
    /// layout), so the bar sits at `frame.minX` and the fill spans the content width. Drawn behind the
    /// text. Code blocks draw their own chat-style chrome instead — see `drawCodeBlockDecorations`.
    func blockquoteDecorations() -> [BlockquoteDecoration] {
        var result: [BlockquoteDecoration] = []
        func add(_ frame: CGRect) {
            result.append(BlockquoteDecoration(fill: frame, bar: CGRect(x: frame.minX, y: frame.minY, width: 3, height: frame.height)))
        }
        func walk(_ boxes: [CanvasBlock]) {
            for box in boxes {
                if let bq = box as? BlockQuoteBox {
                    add(bq.frame)
                    walk(bq.children.boxes)                                       // nested quotes inside this quote
                } else if let t = box as? TableBlockBox {
                    for row in t.cells { for cell in row { walk(cell.boxes) } }   // quotes inside cells
                }
            }
        }
        walk(boxes)
        return result
    }

    /// Every code block in the document (recursing into quote children and table cells).
    func codeBlockBoxes() -> [CodeBlockBox] {
        var result: [CodeBlockBox] = []
        func walk(_ boxes: [CanvasBlock]) {
            for box in boxes {
                if let c = box as? CodeBlockBox {
                    result.append(c)
                } else if let bq = box as? BlockQuoteBox {
                    walk(bq.children.boxes)
                } else if let t = box as? TableBlockBox {
                    for row in t.cells { for cell in row { walk(cell.boxes) } }
                }
            }
        }
        walk(boxes)
        return result
    }

    /// The chat's code-block chrome: a rounded fill from the accent (black-based when dark) at 0.25 and a
    /// 3pt accent bar, mirroring the standard message code block (`TextView`'s
    /// `TextViewBlockQuoteData(isCode:)` rendering). The old display-only header band (language label +
    /// copy icon) is gone — the language is now the block's own always-visible, editable language line,
    /// drawn by `CodeBlockBox.draw` above the code text.
    func drawCodeBlockDecorations(in ctx: CGContext) {
        let accent = mapper.appearance.codeAccent ?? mapper.appearance.linkColor
        let bodyBase = mapper.appearance.isDark ? NSColor.black : accent
        let radius: CGFloat = 3
        for code in codeBlockBoxes() {
            let path = NSBezierPath(roundedRect: code.frame, xRadius: radius, yRadius: radius)
            bodyBase.withAlphaComponent(0.25).setFill(); path.fill()
            ctx.saveGState()
            path.addClip()
            accent.setFill()
            ctx.fill(CGRect(x: code.frame.minX, y: code.frame.minY, width: 3, height: code.frame.height))
            ctx.restoreGState()
        }
    }

    /// Blockquote fill corner radius (measured from the reference design).
    static let blockquoteCornerRadius: CGFloat = 2.5

    func drawBlockquoteDecorations(in ctx: CGContext) {
        for d in blockquoteDecorations() {
            let path = NSBezierPath(roundedRect: d.fill, xRadius: DocumentCanvasView.blockquoteCornerRadius,
                                    yRadius: DocumentCanvasView.blockquoteCornerRadius)
            NSColor.systemBlue.withAlphaComponent(0.10).setFill(); path.fill()
            // Clip the bar to the rounded fill so its outer (left) corners match the quote's rounding.
            ctx.saveGState()
            path.addClip()
            NSColor.systemBlue.setFill(); ctx.fill(d.bar)
            ctx.restoreGState()
        }
        drawPullQuoteDecorations(in: ctx)
        drawCodeBlockDecorations(in: ctx)
    }

    /// One centered, content-hugging pill rect per PullQuoteBox (canvas coords). Width = the box's
    /// widest laid-out line + symmetric padding, floored at `minWidth`, clamped to the box width,
    /// centered on the box's mid-x. Height spans the box.
    func pullQuotePillRects() -> [CGRect] {
        boxes.compactMap { box in
            guard let pq = box as? PullQuoteBox else { return nil }
            let hPad = PullQuoteBox.horizontalPadding
            // Hug the WIDER of the quote text and the author line so a long author isn't clipped.
            let w = min(max(pq.pillContentWidth + hPad * 2, PullQuoteBox.minWidth), box.frame.width)
            return CGRect(x: box.frame.midX - w / 2, y: box.frame.minY, width: w, height: box.frame.height)
        }
    }

    /// Barless tinted pill + corner quote marks per pull quote (open mark top-left; close mark
    /// bottom-right, rotated 180°).
    func drawPullQuoteDecorations(in ctx: CGContext) {
        for box in boxes {
            guard let pq = box as? PullQuoteBox else { continue }
            let hPad = PullQuoteBox.horizontalPadding
            let w = min(max(pq.pillContentWidth + hPad * 2, PullQuoteBox.minWidth), box.frame.width)
            // The pill spans the full box (author included); the corner marks bracket the QUOTE TEXT only.
            let pill = CGRect(x: box.frame.midX - w / 2, y: box.frame.minY, width: w, height: box.frame.height)
            let path = NSBezierPath(roundedRect: pill, xRadius: PullQuoteBox.cornerRadius, yRadius: PullQuoteBox.cornerRadius)
            NSColor.systemBlue.withAlphaComponent(PullQuoteBox.fillAlpha).setFill(); path.fill()

            let inset = PullQuoteBox.markInset
            let markFont = NSFont.boldSystemFont(ofSize: PullQuoteBox.markSize)
            let attrs: [NSAttributedString.Key: Any] = [.font: markFont, .foregroundColor: NSColor.systemBlue]
            let mark = NSAttributedString(string: "\u{201C}", attributes: attrs)
            let mSize = mark.size()
            // Open mark: top-left corner of the pill.
            mark.draw(at: CGPoint(x: pill.minX + inset, y: pill.minY + inset - mSize.height * 0.15))
            // Close mark: bottom-right corner of the QUOTE TEXT region (above any author line), rotated
            // 180° about its OWN box center so it stays compact in the corner instead of sprawling upward.
            let closeRect = CGRect(x: pill.maxX - inset - mSize.width,
                                   y: box.frame.minY + pq.quoteOnlyHeight - inset - mSize.height,
                                   width: mSize.width, height: mSize.height)
            ctx.saveGState()
            ctx.translateBy(x: closeRect.midX, y: closeRect.midY)
            ctx.rotate(by: .pi)
            ctx.translateBy(x: -closeRect.midX, y: -closeRect.midY)
            mark.draw(at: CGPoint(x: closeRect.minX, y: closeRect.minY - mSize.height * 0.15))
            ctx.restoreGState()
        }
    }
}

@available(macOS 12, *)
extension DocumentCanvasView {
    struct PlaceholderDraw { let text: String; let origin: CGPoint; let font: NSFont }

    private func placeholderText(for style: ParagraphStyleName) -> String? {
        switch style {
        case .body:  return editorLocalized("RichTextEditor.Placeholder.TypeSomething", "Type something…")
        default:     return nil  // headings, quote & caption: no placeholder in 6a
        }
    }

    /// A placeholder for the CARET'S empty top-level paragraph only (an empty paragraph the caret isn't
    /// on shows nothing — Shift+Enter'd blank lines would otherwise each repeat the prompt), plus an
    /// editorLocalized("RichTextEditor.Placeholder.AddCaption", "Add caption…") prompt for each media block with an empty caption. List items are excluded — they
    /// show their marker, and the placeholder would overlap it.
    func placeholderDraws() -> [PlaceholderDraw] {
        var result: [PlaceholderDraw] = []
        for box in boxes {
            if let p = box as? BlockBox, p.layout.length == 0, p.listMembership == nil,
               p.paragraphAttributes.firstLineIndent == 0,   // an indented empty paragraph drops the prompt (it wouldn't track the caret)
               selFrom == selTo, head == p.textStart,
               let text = placeholderText(for: p.style) {
                result.append(PlaceholderDraw(text: text, origin: p.textOrigin,
                                              font: mapper.styleSheet.font(for: p.style, attributes: .plain)))
            } else if let media = box as? MediaBlockBox, media.caption.length == 0 {
                result.append(PlaceholderDraw(text: editorLocalized("RichTextEditor.Placeholder.AddCaption", "Add caption…"), origin: media.textOrigin,
                                              font: mapper.styleSheet.font(for: .caption, attributes: .plain)))
            } else if let image = box as? ImageBlockBox, image.caption.length == 0 {
                result.append(PlaceholderDraw(text: editorLocalized("RichTextEditor.Placeholder.AddCaption", "Add caption…"), origin: image.textOrigin,
                                              font: mapper.styleSheet.font(for: .caption, attributes: .plain)))
            } else if let group = box as? MediaGroupBlockBox, group.caption.length == 0 {
                result.append(PlaceholderDraw(text: editorLocalized("RichTextEditor.Placeholder.AddCaption", "Add caption…"), origin: group.textOrigin,
                                              font: mapper.styleSheet.font(for: .caption, attributes: .plain)))
            }
        }
        return result
    }

    func drawPlaceholders(in ctx: CGContext) {
        for d in placeholderDraws() {
            NSAttributedString(string: d.text,
                attributes: [.font: d.font, .foregroundColor: NSColor.placeholderTextColor]).draw(at: d.origin)
        }
    }
}
#endif
