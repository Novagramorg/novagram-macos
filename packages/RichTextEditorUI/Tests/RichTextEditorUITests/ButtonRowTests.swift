#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

/// InstantPage button rows in the canvas: the V2-metric packing (`richTextPackButtonRow`), the
/// text-free `ButtonRowBox` position contract, the outgoing round-trip, and the markdown degradation.
@available(macOS 12, *)
final class ButtonRowTests: AppKitTestCase {
    private let mapper = AttributedStringMapper()
    private let metrics = RichTextButtonMetrics.default

    private func button(_ label: String, action: ButtonAction = .url("https://example.com")) -> ButtonRef {
        ButtonRef(label: [TextRun(text: label)], action: action)
    }

    private func pack(_ buttons: [ButtonRef], alignment: ButtonRowAlignment, width: CGFloat, isRTL: Bool = false)
        -> (attachments: [ButtonTextAttachment], frames: [CGRect], totalHeight: CGFloat) {
        richTextPackButtonRow(buttons: buttons, alignment: alignment, availableWidth: width,
                              metrics: metrics, isRTL: isRTL) { [mapper] b, maxWidth, padding in
            mapper.buttonAttachment(button: b, isBlockPill: true, maxWidth: maxWidth, horizontalPadding: padding)
        }
    }

    // MARK: - Packing

    func test_justify_splitsTheWidthIntoEqualColumns() {
        let packed = pack([button("A"), button("B"), button("C")], alignment: .justify, width: 306)
        XCTAssertEqual(packed.frames.count, 3)
        let expectedWidth = (306 - metrics.blockSpacing * 2) / 3
        for frame in packed.frames {
            XCTAssertEqual(frame.width, expectedWidth, accuracy: 0.5)
            XCTAssertEqual(frame.height, metrics.blockRowHeight)
        }
        XCTAssertEqual(packed.frames[1].minX, expectedWidth + metrics.blockSpacing, accuracy: 0.5)
        XCTAssertEqual(packed.totalHeight, metrics.blockRowHeight)
    }

    func test_justify_wrapsAtTheEightButtonCap() {
        let packed = pack((0 ..< 9).map { button("B\($0)") }, alignment: .justify, width: 400)
        XCTAssertEqual(packed.frames[8].minY, metrics.blockRowHeight + metrics.blockSpacing)
        XCTAssertEqual(packed.frames[8].width, 400, accuracy: 0.5)   // lone button on row 2 takes the width
        XCTAssertEqual(packed.totalHeight, metrics.blockRowHeight * 2 + metrics.blockSpacing)
    }

    func test_hugging_centerAlignsEachRowOnItsOwnWidth() {
        let packed = pack([button("A"), button("B")], alignment: .center, width: 400)
        let rowWidth = packed.frames[0].width + metrics.blockSpacing + packed.frames[1].width
        XCTAssertEqual(packed.frames[0].minX, (400 - rowWidth) / 2, accuracy: 0.5)
        XCTAssertLessThan(packed.frames[0].width, 100, "a hugging pill hugs its short label")
        // The pill hugs label ink + padding on both sides (badge reserve arms outside the padding).
        let a = packed.attachments[0]
        XCTAssertEqual(packed.frames[0].width, a.size.width + max(0, metrics.blockIconReserve - a.horizontalPadding) * 2,
                       accuracy: 0.5)
    }

    func test_hugging_rtl_reversesVisualOrder_framesStayModelOrder() {
        let ltr = pack([button("First"), button("Second")], alignment: .left, width: 400)
        let rtl = pack([button("First"), button("Second")], alignment: .left, width: 400, isRTL: true)
        XCTAssertEqual(ltr.frames.count, 2)
        XCTAssertEqual(rtl.frames.count, 2)
        XCTAssertLessThan(ltr.frames[0].minX, ltr.frames[1].minX, "LTR: model order runs left to right")
        XCTAssertGreaterThan(rtl.frames[0].minX, rtl.frames[1].minX, "RTL: the FIRST pill sits at the reading start (right)")
        // `left` means LEADING: the RTL row hugs the right edge.
        XCTAssertEqual(rtl.frames[0].maxX, 400, accuracy: 0.5)
    }

    func test_pack_emptyRowOrZeroWidth_isEmpty() {
        XCTAssertTrue(pack([], alignment: .justify, width: 300).frames.isEmpty)
        XCTAssertTrue(pack([button("A")], alignment: .justify, width: 0).frames.isEmpty)
    }

    func test_blockPill_truncatingLabel_retriesAtTightPadding() {
        let long = button(String(repeating: "M", count: 40), action: .disabled)
        let packed = pack([long], alignment: .justify, width: 120)
        let a = packed.attachments[0]
        XCTAssertTrue(a.isTruncated, "a 40-em label cannot fit a 120pt pill")
        XCTAssertEqual(metrics.blockMinimumHorizontalPadding, 6.0, "the renderer's tight fallback")
        XCTAssertEqual(a.horizontalPadding, metrics.blockMinimumHorizontalPadding,
                       "a truncating label is re-measured at the tight padding, like the sent message")
    }

    func test_badgeReserve_matchesTheRendererPerAction() {
        XCTAssertEqual(richTextButtonBadgeReserve(button("A", action: .url("https://x.y")), metrics: metrics), 28.0)
        XCTAssertEqual(richTextButtonBadgeReserve(button("G", action: .url("🎁")), metrics: metrics), 0.0,
                       "a single-emoji URL draws no icon")
        XCTAssertEqual(richTextButtonBadgeReserve(button("C", action: .copyText("s")), metrics: metrics), 28.0)
        XCTAssertEqual(richTextButtonBadgeReserve(button("Later", action: .disabled), metrics: metrics), 0.0)
        XCTAssertEqual(richTextButtonBadgeReserve(button("Open", action: .disabled), metrics: metrics), 28.0)
        XCTAssertEqual(richTextButtonBadgeReserve(button("Profile", action: .disabled), metrics: metrics), 30.0,
                       "the profile icon is 10pt, not 8")
        XCTAssertEqual(richTextButtonBadgeReserve(
            button("X", action: .unsupported(kind: "replyMarkupButtonAction", payload: "")), metrics: metrics),
            metrics.blockIconReserve, "an opaque action keeps the flat approximation")
    }

    func test_justify_degenerateWidth_clampsSpacingInsideTheRow() {
        let packed = pack((0 ..< 8).map { button("B\($0)") }, alignment: .justify, width: 24)
        XCTAssertEqual(packed.frames.count, 8)
        for frame in packed.frames {
            XCTAssertLessThanOrEqual(frame.maxX, 24.0 + 0.5,
                                     "clamped spacing keeps every pill inside the row, like the renderer")
        }
    }

    // MARK: - ButtonRowBox position contract

    func test_box_nodeSize_isAtomsPlusTwo_flooredAtOneAtom() {
        let empty = ButtonRowBox(row: ButtonRowBlock(id: BlockID.generate()), mapper: mapper, width: 300)
        XCTAssertEqual(empty.nodeSize, 3, "an empty row keeps one interior slot so it stays selectable")
        XCTAssertEqual(empty.height, metrics.blockRowHeight, "an empty row is floored at one pill row")
        let two = ButtonRowBox(row: ButtonRowBlock(id: BlockID.generate(), buttons: [button("A"), button("B")]),
                               mapper: mapper, width: 300)
        XCTAssertEqual(two.nodeSize, 4)
        XCTAssertTrue(two.leafRegions().isEmpty, "a row owns no editable text")
        XCTAssertEqual(two.textLength, 0)
    }

    func test_box_closestPosition_snapsToTheNearestPillAtom() {
        let box = ButtonRowBox(row: ButtonRowBlock(id: BlockID.generate(), buttons: [button("A"), button("B")]),
                               mapper: mapper, width: 300)
        box.nodeStart = 10
        box.frame = CGRect(x: 0, y: 0, width: 300, height: box.height)
        let secondPill = box.pillCanvasRect(1)!
        XCTAssertEqual(box.closestPosition(toCanvasPoint: CGPoint(x: secondPill.midX, y: secondPill.midY)), 12)
        XCTAssertEqual(box.closestPosition(toCanvasPoint: CGPoint(x: -50, y: -50)), 11,
                       "a point outside every pill still lands on the nearest atom")
    }

    // MARK: - Canvas round-trip + backspace

    func test_buttonRow_roundTrips_throughOutgoingBlocks() {
        let row = ButtonRowBlock(id: BlockID.generate(),
                                 buttons: [ButtonRef(label: [TextRun(text: "Open")], action: .url("https://x.y"),
                                                     color: .danger, isLink: false),
                                           ButtonRef(label: [TextRun(text: "Later")], action: .disabled)],
                                 alignment: .center)
        let v = DocumentCanvasView()
        v.setOutgoingBlocks([.paragraph(ParagraphBlock(id: BlockID.generate(), runs: [TextRun(text: "Hi")])),
                             .buttonRow(row)], width: 400)
        let out = v.outgoingBlocks()
        XCTAssertEqual(out.count, 2)
        guard case let .buttonRow(back) = out[1] else { return XCTFail("buttonRow survived the round-trip") }
        XCTAssertEqual(back, row, "actions, colors, isLink and alignment are preserved verbatim")
    }

    func test_backspaceOnPillAtom_deletesOnePill_thenTheRow() {
        let row = ButtonRowBlock(id: BlockID.generate(), buttons: [button("A"), button("B")])
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID.generate(), runs: [TextRun(text: "Hi")])),
                     .buttonRow(row)], width: 400)
        let box = v.boxes[1] as! ButtonRowBox
        v.anchor = box.nodeStart + 2; v.head = box.nodeStart + 2      // caret on pill "B"
        v.performDeleteBackward()
        XCTAssertEqual((v.boxes[1] as! ButtonRowBox).buttons.map(\.labelText), ["A"])
        v.performDeleteBackward()                                     // caret landed on the surviving pill
        XCTAssertEqual(v.boxes.count, 1, "deleting the last pill removes the whole row")
        XCTAssertFalse(v.boxes[0] is ButtonRowBox)
    }

    func test_deletingTheOnlyRowsLastPill_leavesAnEmptyParagraph_caretRenderable() {
        let row = ButtonRowBlock(id: BlockID.generate(), buttons: [button("A")])
        let v = DocumentCanvasView()
        v.setBlocks([.buttonRow(row)], width: 400)
        let box = v.boxes[0] as! ButtonRowBox
        v.anchor = box.nodeStart + 1; v.head = box.nodeStart + 1
        v.performDeleteBackward()
        XCTAssertEqual(v.boxes.count, 1)
        XCTAssertTrue(v.boxes[0] is BlockBox, "an empty paragraph replaces the last row — never a zero-block canvas")
        XCTAssertEqual(v.head, v.boxes[0].textStart, "caret parks on a renderable slot")
        v.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual((v.boxes[0] as! BlockBox).textLength, 1, "the canvas stays editable")
    }

    func test_deletingATrailingRow_parksCaretAtThePreviousParagraphEnd() {
        let row = ButtonRowBlock(id: BlockID.generate(), buttons: [button("A")])
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID.generate(), runs: [TextRun(text: "Hi")])),
                     .buttonRow(row)], width: 400)
        let box = v.boxes[1] as! ButtonRowBox
        v.anchor = box.nodeStart + 1; v.head = box.nodeStart + 1
        v.performDeleteBackward()
        XCTAssertEqual(v.boxes.count, 1)
        XCTAssertEqual(v.head, v.boxes[0].textStart + v.boxes[0].textLength,
                       "caret parks at the previous paragraph's end, not past the document")
    }

    func test_backspaceAfterDeletingARow_doesNotWipeTheAdjacentRow() {
        let rowA = ButtonRowBlock(id: BlockID.generate(), buttons: [button("A")])
        let rowB = ButtonRowBlock(id: BlockID.generate(), buttons: [button("B")])
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID.generate(), runs: [TextRun(text: "Hi")])),
                     .buttonRow(rowA), .buttonRow(rowB)], width: 400)
        let boxA = v.boxes[1] as! ButtonRowBox
        v.anchor = boxA.nodeStart + 1; v.head = boxA.nodeStart + 1
        v.performDeleteBackward()
        XCTAssertEqual(v.boxes.count, 2, "rowA is gone; para + rowB remain")
        XCTAssertEqual(v.head, v.boxes[0].textStart + v.boxes[0].textLength,
                       "caret parks at the paragraph end, not on rowB's structural nodeStart")
        v.performDeleteBackward()
        XCTAssertEqual((v.boxes[0] as! BlockBox).textLength, 1, "the next Backspace eats one paragraph char")
        XCTAssertEqual((v.boxes.last as? ButtonRowBox)?.buttons.map(\.labelText), ["B"],
                       "rowB survives with its pill — never wiped whole by one keypress")
    }

    func test_backspaceOnARowsBoundarySlot_snapsWithoutDeleting() {
        let row = ButtonRowBlock(id: BlockID.generate(), buttons: [button("A"), button("B")])
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID.generate(), runs: [TextRun(text: "Hi")])),
                     .buttonRow(row)], width: 400)
        let box = v.boxes[1] as! ButtonRowBox
        v.anchor = box.nodeStart; v.head = box.nodeStart      // structural slot, not a pill atom
        v.performDeleteBackward()
        XCTAssertEqual(v.boxes.count, 2, "nothing is deleted from a boundary slot")
        XCTAssertEqual((v.boxes.last as? ButtonRowBox)?.buttons.count, 2)
        XCTAssertEqual(v.head, v.boxes[0].textStart + v.boxes[0].textLength, "the caret snaps to a renderable slot")
    }

    func test_selectAllBackspace_removesACoveredRow() {
        let row = ButtonRowBlock(id: BlockID.generate(), buttons: [button("A")])
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID.generate(), runs: [TextRun(text: "Hi")])),
                     .buttonRow(row)], width: 400)
        v.selectAllText()
        v.performDeleteBackward()
        XCTAssertFalse(v.boxes.contains { $0 is ButtonRowBox }, "a fully-covered row is removed, not left as a husk")
    }

    // MARK: - Keyboard navigation

    func test_rightArrow_entersARowAtItsFirstPill_andWalksPillByPill() {
        let row = ButtonRowBlock(id: BlockID.generate(), buttons: [button("A"), button("B")])
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID.generate(), runs: [TextRun(text: "Hi")])),
                     .buttonRow(row),
                     .paragraph(ParagraphBlock(id: BlockID.generate(), runs: [TextRun(text: "Yo")]))], width: 400)
        let box = v.boxes[1] as! ButtonRowBox
        let paraEnd = v.boxes[0].textStart + v.boxes[0].textLength
        XCTAssertEqual(v.nextTextPosition(after: paraEnd), box.nodeStart + 1, "Right enters the row at its FIRST pill")
        XCTAssertEqual(v.nextTextPosition(after: box.nodeStart + 1), box.nodeStart + 2, "then steps pill-by-pill")
        XCTAssertEqual(v.nextTextPosition(after: box.nodeStart + 2), v.boxes[2].textStart, "then exits into the next region")
        XCTAssertEqual(v.prevTextPosition(before: v.boxes[2].textStart), box.nodeStart + 2, "Left enters at the LAST pill")
        XCTAssertEqual(v.prevTextPosition(before: box.nodeStart + 2), box.nodeStart + 1)
        XCTAssertEqual(v.prevTextPosition(before: box.nodeStart + 1), paraEnd, "and exits to the previous region end")
    }

    func test_adjacentRows_traversePillByPill_inBothDirections() {
        let rowA = ButtonRowBlock(id: BlockID.generate(), buttons: [button("A1"), button("A2")])
        let rowB = ButtonRowBlock(id: BlockID.generate(), buttons: [button("B1"), button("B2")])
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID.generate(), runs: [TextRun(text: "Hi")])),
                     .buttonRow(rowA), .buttonRow(rowB),
                     .paragraph(ParagraphBlock(id: BlockID.generate(), runs: [TextRun(text: "Yo")]))], width: 400)
        let a = v.boxes[1] as! ButtonRowBox
        let b = v.boxes[2] as! ButtonRowBox
        XCTAssertEqual(v.nextTextPosition(after: a.nodeStart + 2), b.nodeStart + 1,
                       "rowA's last pill steps onto rowB's FIRST pill — no row is skipped")
        XCTAssertEqual(v.prevTextPosition(before: b.nodeStart + 1), a.nodeStart + 2,
                       "and Left steps back onto rowA's LAST pill")
    }

    func test_arrowsAroundAMediaNeighbor_stopOnPills_notStructuralSlots() {
        let row = ButtonRowBlock(id: BlockID.generate(), buttons: [button("A")])
        let v = DocumentCanvasView()
        v.setModelBlocks([
            .core(.paragraph(ParagraphBlock(id: BlockID.generate(), runs: [TextRun(text: "Hi")]))),
            .core(.buttonRow(row)),
            .media(MediaBlock(id: BlockID("img"), kind: .image, mediaID: "x",
                              naturalSize: Size2D(width: 80, height: 50))),
        ], width: 400)
        let box = v.boxes[1] as! ButtonRowBox
        let media = v.boxes[2]
        XCTAssertEqual(v.nextTextPosition(after: box.nodeStart + 1), media.nodeStart,
                       "Right off the last pill stops on the media gap, not past it")
        let back = v.prevTextPosition(before: media.nodeStart)
        XCTAssertEqual(back, box.nodeStart + 1, "Left from the media gap lands on the row's LAST pill")
        XCTAssertTrue(v.isRenderablePosition(back), "never the row's degenerate nodeStart")
    }

    // MARK: - Paste-only action downgrade scoping

    func test_insertFragment_preservesUnsupportedActions_unlessPasting() {
        let unsupported = ButtonAction.unsupported(kind: "replyMarkupButtonAction", payload: "blob")
        let frag: [Block] = [.buttonRow(ButtonRowBlock(id: BlockID.generate(),
                                                       buttons: [ButtonRef(label: [TextRun(text: "Do")], action: unsupported)]))]
        func host() -> DocumentCanvasView {
            let v = DocumentCanvasView()
            v.setBlocks([.paragraph(ParagraphBlock(id: BlockID.generate(), runs: [TextRun(text: "Hi")]))], width: 400)
            v.setCaret(global: v.boxes[0].textStart + v.boxes[0].textLength)
            return v
        }
        let splice = host()
        splice.insertFragment(frag)
        XCTAssertEqual(splice.boxes.compactMap { $0 as? ButtonRowBox }.first?.buttons.first?.action, unsupported,
                       "the host AI-splice path (replaceSelection) preserves actions verbatim")
        let paste = host()
        paste.insertFragment(frag, downgradeUnsupportedActions: true)
        XCTAssertEqual(paste.boxes.compactMap { $0 as? ButtonRowBox }.first?.buttons.first?.action, .disabled,
                       "the paste path downgrades unsupported actions")
    }

    // MARK: - Markdown degradation

    func test_markdown_urlButtonDegradesToLink_othersToLabelText() {
        let blocks: [Block] = [.buttonRow(ButtonRowBlock(id: BlockID.generate(), buttons: [
            ButtonRef(label: [TextRun(text: "Visit")], action: .url("https://t.me")),
            ButtonRef(label: [TextRun(text: "Nope")], action: .disabled),
        ]))]
        XCTAssertEqual(RichTextMarkdown.markdown(from: blocks), "[Visit](https://t.me) Nope")
    }

    func test_markdown_rowPillLabels_escapeMetacharacters_likeTheInlineArm() {
        let blocks: [Block] = [.buttonRow(ButtonRowBlock(id: BlockID.generate(), buttons: [
            ButtonRef(label: [TextRun(text: "a]b")], action: .url("https://t.me")),
            ButtonRef(label: [TextRun(text: "c*d")], action: .disabled),
        ]))]
        XCTAssertEqual(RichTextMarkdown.markdown(from: blocks), "[a\\]b](https://t.me) c\\*d")
    }

    func test_markdown_inlineButtonRunDegrades() {
        var ca = CharacterAttributes()
        ca.button = ButtonRef(label: [TextRun(text: "Tap")], action: .url("https://t.me"))
        let blocks: [Block] = [.paragraph(ParagraphBlock(id: BlockID.generate(),
                                                         runs: [TextRun(text: "See "),
                                                                TextRun(text: "\u{FFFC}", attributes: ca)]))]
        XCTAssertEqual(RichTextMarkdown.markdown(from: blocks), "See [Tap](https://t.me)")
    }

    // MARK: - Inline pill mapping

    func test_inlineButtonRun_roundTripsThroughTheMapper() {
        var ca = CharacterAttributes()
        ca.button = ButtonRef(label: [TextRun(text: "Tap")], action: .copyText("secret"))
        let attrs = mapper.attributes(for: ca, style: .body)
        let attachment = attrs[.attachment] as? ButtonTextAttachment
        XCTAssertNotNil(attachment, "an inline button run renders as a measured pill attachment")
        XCTAssertGreaterThan(attachment!.size.width, attachment!.horizontalPadding * 2)
        XCTAssertEqual(mapper.characterAttributes(from: attrs).button, ca.button,
                       "read-back recovers the button and nothing render-derived")
    }

    func test_inlineLinkButton_rendersAsPlainLinkText_notAFilledPill() {
        var ca = CharacterAttributes()
        ca.button = ButtonRef(label: [TextRun(text: "Tap")], action: .url("https://t.me"), isLink: true)
        let attachment = mapper.attributes(for: ca, style: .body)[.attachment] as! ButtonTextAttachment
        XCTAssertEqual(attachment.horizontalPadding, 0, "a plain link takes no pill padding")
        XCTAssertEqual(attachment.colors.fill, .clear, "and draws no fill")
        XCTAssertEqual(attachment.colors.label, mapper.appearance.linkColor)
        let labelFont = attachment.labelString.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        let bodyFont = mapper.styleSheet.font(for: .body, attributes: CharacterAttributes())
        XCTAssertEqual(labelFont.pointSize, bodyFont.pointSize,
                       "the label keeps the paragraph's typography — no pill font push")
    }

    func test_pillLabelWeights_inlineMedium_blockSemibold() {
        var ca = CharacterAttributes()
        ca.button = ButtonRef(label: [TextRun(text: "Tap")], action: .url("https://t.me"))
        let inline = mapper.attributes(for: ca, style: .body)[.attachment] as! ButtonTextAttachment
        XCTAssertEqual(inline.labelString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
                       NSFont.systemFont(ofSize: metrics.inlineFontSize, weight: .medium),
                       "inline pills letter in MEDIUM, like the renderer")
        let block = mapper.buttonAttachment(button: ca.button!, isBlockPill: true, maxWidth: nil)
        XCTAssertEqual(block.labelString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
                       NSFont.systemFont(ofSize: metrics.blockFontSize, weight: .semibold),
                       "block pills stay semibold")
    }

    func test_inlinePill_plainUnicodeEmoji_isInsetTo075x_blockIsNot() {
        let b = ButtonRef(label: [TextRun(text: "🎁")], action: .url("https://t.me"))
        let inline = mapper.buttonAttachment(button: b, isBlockPill: false, maxWidth: nil)
        let inlineFont = inline.labelString.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        XCTAssertEqual(inlineFont.pointSize, metrics.inlineFontSize * 0.75, accuracy: 0.01,
                       "inline pills scale plain Unicode emoji like the renderer")
        let block = mapper.buttonAttachment(button: b, isBlockPill: true, maxWidth: nil)
        let blockFont = block.labelString.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        XCTAssertEqual(blockFont.pointSize, metrics.blockFontSize, "block rows don't scale on either side")
    }

    func test_emojiLabel_measuresTheReservedEmojiSquare_notABareObjectReplacement() {
        var emojiAttrs = CharacterAttributes()
        emojiAttrs.emoji = EmojiRef(id: "42", instanceID: "i1")
        let withEmoji = ButtonRef(label: [TextRun(text: "Go "),
                                          TextRun(text: "\u{FFFC}", attributes: emojiAttrs)],
                                  action: .url("https://t.me"))
        let plain = ButtonRef(label: [TextRun(text: "Go ")], action: .url("https://t.me"))
        let a = mapper.buttonAttachment(button: withEmoji, isBlockPill: true, maxWidth: nil)
        let b = mapper.buttonAttachment(button: plain, isBlockPill: true, maxWidth: nil)
        let pillFont = NSFont.systemFont(ofSize: metrics.blockFontSize, weight: .semibold)
        XCTAssertEqual(a.size.width - b.size.width, pillFont.ascender - pillFont.descender, accuracy: 0.5,
                       "the emoji advance is the renderer's reserved square, not the bare U+FFFC glyph")
        let measuredInk = a.size.width - a.horizontalPadding * 2
        XCTAssertEqual(a.labelString.size().width, measuredInk, accuracy: 1.0,
                       "the TextKit draw path reserves the same advance the CTLine measure did")
    }

    // MARK: - Authoring

    private func paragraphCanvas(_ text: String) -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID.generate(), runs: text.isEmpty ? [] : [TextRun(text: text)]))],
                    width: 400)
        v.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        v.layoutSubtreeIfNeeded()
        return v
    }

    func test_insertButtonRow_onEmptyParagraph_replacesIt() {
        let v = paragraphCanvas("")
        v.anchor = v.boxes[0].textStart; v.head = v.boxes[0].textStart
        v.insertButtonRow()
        XCTAssertEqual(v.boxes.count, 1)
        guard let row = v.boxes[0] as? ButtonRowBox else { return XCTFail("the row replaced the empty paragraph") }
        XCTAssertEqual(row.buttons.count, 1, "one default pill")
        XCTAssertEqual(row.buttons[0].action, .url(""), "blank URL, for the property sheet to fill")
        XCTAssertEqual(row.alignment, .justify)
        XCTAssertEqual(v.head, row.nodeStart + 1, "caret parks on the pill atom")
    }

    func test_insertButtonRow_midParagraph_splitsIt() {
        let v = paragraphCanvas("HelloWorld")
        let start = v.boxes[0].textStart
        v.anchor = start + 5; v.head = start + 5
        v.insertButtonRow()
        XCTAssertEqual(v.boxes.count, 3)
        XCTAssertEqual((v.boxes[0] as? BlockBox)?.currentParagraph().text, "Hello")
        XCTAssertTrue(v.boxes[1] is ButtonRowBox)
        XCTAssertEqual((v.boxes[2] as? BlockBox)?.currentParagraph().text, "World")
    }

    func test_insertButtonRow_atParagraphEdges_insertsBeforeOrAfter() {
        let atEnd = paragraphCanvas("Hi")
        atEnd.anchor = atEnd.boxes[0].textStart + 2; atEnd.head = atEnd.anchor
        atEnd.insertButtonRow()
        XCTAssertEqual(atEnd.boxes.count, 2)
        XCTAssertTrue(atEnd.boxes[1] is ButtonRowBox, "caret at the end inserts after")

        let atStart = paragraphCanvas("Hi")
        atStart.anchor = atStart.boxes[0].textStart; atStart.head = atStart.anchor
        atStart.insertButtonRow()
        XCTAssertEqual(atStart.boxes.count, 2)
        XCTAssertTrue(atStart.boxes[0] is ButtonRowBox, "caret at the start inserts before")
    }

    func test_insertButtonRow_insideTable_noops() {
        let cell = Cell(id: BlockID("c"), blocks: [.paragraph(ParagraphBlock(id: BlockID("cp"), runs: [TextRun(text: "T")]))])
        let v = DocumentCanvasView()
        v.setBlocks([.table(TableBlock(id: BlockID("t"), columns: [ColumnSpec(width: 120)],
                                       rows: [Row(id: BlockID("r"), isHeader: true, cells: [cell])]))], width: 400)
        let box = v.boxes[0] as! TableBlockBox
        let pos = box.cellTextStart(row: 0, column: 0)!
        v.selectedGlobalRange = (pos, pos)
        v.insertButtonRow()
        XCTAssertEqual(v.boxes.count, 1)
        XCTAssertTrue(v.boxes[0] is TableBlockBox, "rows are top-level only — no insert inside a table")
    }

    func test_makeSelectionInlineButton_collapsesSelectionToOneAtom() {
        let v = paragraphCanvas("Click here please")
        let start = v.boxes[0].textStart
        v.selectedGlobalRange = (start + 6, start + 10)               // "here"
        v.makeSelectionInlineButton()
        let p = (v.boxes[0] as! BlockBox).currentParagraph()
        XCTAssertEqual(p.text, "Click \u{FFFC} please", "the selection collapsed to one atom")
        let run = p.runs.first { $0.attributes.button != nil }
        XCTAssertEqual(run?.attributes.button?.labelText, "here", "the label is the selected text")
        XCTAssertEqual(run?.attributes.button?.action, .url(""))
        XCTAssertEqual(v.head, start + 7, "caret lands after the atom")
    }

    func test_replaceInlineButton_updatesOrRemovesTheAtom() {
        let v = paragraphCanvas("Click here please")
        let start = v.boxes[0].textStart
        v.selectedGlobalRange = (start + 6, start + 10)
        v.makeSelectionInlineButton()
        let atomPos = v.head - 1
        var updated = ButtonRef(label: [TextRun(text: "there")], action: .url("https://t.me"))
        updated.color = .danger
        v.replaceInlineButton(at: atomPos, with: updated)
        var p = (v.boxes[0] as! BlockBox).currentParagraph()
        XCTAssertEqual(p.runs.first { $0.attributes.button != nil }?.attributes.button, updated)
        v.replaceInlineButton(at: atomPos, with: nil)
        p = (v.boxes[0] as! BlockBox).currentParagraph()
        XCTAssertEqual(p.text, "Click  please", "nil removes the atom")
        XCTAssertNil(p.runs.first { $0.attributes.button != nil })
    }

    func test_requestNewButton_appendsOnlyWhenTheSheetCommits() {
        // SHEET-FIRST: nothing is appended until the sheet's completion delivers a configured button.
        let row = ButtonRowBlock(id: BlockID("row"), buttons: [button("A")])
        let v = DocumentCanvasView()
        v.setBlocks([.buttonRow(row)], width: 400)
        var captured: ((ButtonRef?) -> Void)?
        v.buttonEditRequested = { b, isBlockPill, completion in
            XCTAssertTrue(isBlockPill)
            XCTAssertEqual(b, ButtonRef(label: [], action: .url("")), "the sheet is seeded blank")
            captured = completion
        }
        v.requestNewButton(forRow: BlockID("row"))
        let box = v.boxes[0] as! ButtonRowBox
        XCTAssertEqual(box.buttons.count, 1, "nothing appended while the sheet is open")
        captured?(ButtonRef(label: [TextRun(text: "B")], action: .url("https://t.me")))
        XCTAssertEqual(box.buttons.map(\.labelText), ["A", "B"], "the commit appends the configured pill")
        XCTAssertEqual(v.head, box.nodeStart + 2, "caret on the new pill")
    }

    func test_requestNewButton_cancelAppendsNothing() {
        let row = ButtonRowBlock(id: BlockID("row"), buttons: [button("A")])
        let v = DocumentCanvasView()
        v.setBlocks([.buttonRow(row)], width: 400)
        var captured: ((ButtonRef?) -> Void)?
        v.buttonEditRequested = { _, _, completion in captured = completion }
        v.requestNewButton(forRow: BlockID("row"))
        captured?(nil)
        XCTAssertEqual((v.boxes[0] as! ButtonRowBox).buttons.map(\.labelText), ["A"],
                       "a cancelled sheet leaves the row untouched")
    }

    func test_setButtonRowAlignment_and_deleteButtonRow() {
        let row = ButtonRowBlock(id: BlockID("row"), buttons: [button("A")])
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID.generate(), runs: [TextRun(text: "Hi")])),
                     .buttonRow(row)], width: 400)
        v.setButtonRowAlignment(rowID: BlockID("row"), .center)
        XCTAssertEqual((v.boxes[1] as! ButtonRowBox).alignment, .center)
        v.deleteButtonRow(rowID: BlockID("row"))
        XCTAssertEqual(v.boxes.count, 1)
        XCTAssertEqual(v.head, v.boxes[0].textStart + v.boxes[0].textLength,
                       "caret parks on the paragraph end, a renderable slot")
    }

    func test_menuAffordance_stampedByHostHook_reservesWidth() {
        let row = ButtonRowBlock(id: BlockID("row"), buttons: [button("A")])
        let v = DocumentCanvasView()
        v.setBlocks([.buttonRow(row)], width: 400)
        let box = v.boxes[0] as! ButtonRowBox
        XCTAssertFalse(box.showsMenuAffordance, "no host hook — composer pills match the sent message")
        XCTAssertEqual(box.menuButtonFrame, .zero)
        let plainWidth = box.pillFrames[0].width
        v.buttonEditRequested = { _, _, _ in }
        XCTAssertTrue(box.showsMenuAffordance, "wiring the editor hook enables the authoring chrome")
        XCTAssertNotEqual(box.menuButtonFrame, .zero)
        XCTAssertLessThan(box.pillFrames[0].width, plainWidth, "the pills give up the \"…\" reserve")
        XCTAssertTrue(box.hitsMenuButton(atCanvasPoint: CGPoint(x: box.frame.minX + box.menuButtonFrame.midX,
                                                                y: box.frame.minY + box.menuButtonFrame.midY)))
    }

    func test_insertButtonRow_undoRestoresTheParagraph() {
        let v = paragraphCanvas("Hi")
        let um = UndoManager(); um.groupsByEvent = false
        v.undoManagerOverride = um
        v.anchor = v.boxes[0].textStart + 2; v.head = v.anchor
        um.beginUndoGrouping(); v.insertButtonRow(); um.endUndoGrouping()
        XCTAssertEqual(v.boxes.count, 2)
        um.undo()
        XCTAssertEqual(v.boxes.count, 1)
        XCTAssertEqual((v.boxes[0] as? BlockBox)?.currentParagraph().text, "Hi", "one undo removes the row")
    }

    func test_makeSelectionInlineButton_inCodeBlock_refuses() {
        // A code block serializes its layout string verbatim, so a button atom there would silently
        // destroy the selected text on the first round-trip — the command must refuse, and the
        // enablement predicate must agree.
        let v = DocumentCanvasView()
        v.setBlocks([.code(CodeBlock(id: BlockID("c"), language: nil, runs: [TextRun(text: "let x = 1")]))], width: 400)
        let start = v.boxes[0].textStart
        v.selectedGlobalRange = (start + 4, start + 5)                // "x"
        XCTAssertFalse(v.canMakeSelectionInlineButton)
        v.makeSelectionInlineButton()
        guard case .code(let code)? = v.currentBlocks().first else { return XCTFail("still a code block") }
        XCTAssertEqual(code.runs.first?.text, "let x = 1", "the code text is untouched")
    }

    func test_canInsertButtonRow_matchesTheCommandGuard() {
        let para = paragraphCanvas("Hi")
        para.anchor = para.boxes[0].textStart; para.head = para.anchor
        XCTAssertTrue(para.canInsertButtonRow)

        let code = DocumentCanvasView()
        code.setBlocks([.code(CodeBlock(id: BlockID("c"), language: nil, runs: [TextRun(text: "x")]))], width: 400)
        code.selectedGlobalRange = (code.boxes[0].textStart, code.boxes[0].textStart)
        XCTAssertFalse(code.canInsertButtonRow, "a code block cannot host a row — the menu item must gray out")

        let cellBlock = Cell(id: BlockID("c"), blocks: [.paragraph(ParagraphBlock(id: BlockID("cp"), runs: [TextRun(text: "T")]))])
        let table = DocumentCanvasView()
        table.setBlocks([.table(TableBlock(id: BlockID("t"), columns: [ColumnSpec(width: 120)],
                                           rows: [Row(id: BlockID("r"), isHeader: true, cells: [cellBlock])]))], width: 400)
        let pos = (table.boxes[0] as! TableBlockBox).cellTextStart(row: 0, column: 0)!
        table.selectedGlobalRange = (pos, pos)
        XCTAssertFalse(table.canInsertButtonRow)
    }

    func test_insertButtonRowWith_insertsTheConfiguredPill() {
        // The sheet-first flow: the host collects the properties BEFORE inserting, so the row lands
        // already configured — no blank placeholder ever enters the document.
        let v = paragraphCanvas("")
        v.anchor = v.boxes[0].textStart; v.head = v.anchor
        let filled = ButtonRef(label: [TextRun(text: "Go")], action: .url("https://t.me"), color: .primary)
        v.insertButtonRow(with: filled)
        XCTAssertEqual(v.boxes.count, 1)
        XCTAssertEqual((v.boxes[0] as? ButtonRowBox)?.buttons, [filled])
    }

    func test_insertInlineButton_atBareCaret_insertsAtom() {
        let v = paragraphCanvas("Hello world")
        let start = v.boxes[0].textStart
        v.selectedGlobalRange = (start + 5, start + 5)                // caret after "Hello"
        let configured = ButtonRef(label: [TextRun(text: "Go")], action: .url("https://t.me"))
        XCTAssertTrue(v.canInsertInlineButton)
        v.insertInlineButton(with: configured)
        let p = (v.boxes[0] as! BlockBox).currentParagraph()
        XCTAssertEqual(p.text, "Hello\u{FFFC} world", "the pill lands at the caret like an emoji atom")
        XCTAssertEqual(p.runs.first { $0.attributes.button != nil }?.attributes.button, configured)
        XCTAssertEqual(v.head, start + 6, "caret after the atom")
    }

    func test_insertInlineButton_inCodeBlock_refuses() {
        let v = DocumentCanvasView()
        v.setBlocks([.code(CodeBlock(id: BlockID("c"), language: nil, runs: [TextRun(text: "let x = 1")]))], width: 400)
        let start = v.boxes[0].textStart
        v.selectedGlobalRange = (start + 3, start + 3)
        XCTAssertFalse(v.canInsertInlineButton)
        v.insertInlineButton(with: ButtonRef(label: [TextRun(text: "Go")], action: .url("https://t.me")))
        guard case .code(let code)? = v.currentBlocks().first else { return XCTFail("still a code block") }
        XCTAssertEqual(code.runs.first?.text, "let x = 1", "the code text is untouched")
    }

    func test_adjacentButtonRows_stackAtTheirOwnPadding_notTheFramedMargin() {
        // The V2 renderer separates two rows by their own padding (4+4), not the framed-atom margin —
        // the editor mirrors that so stacked rows read like the sent message.
        let v = DocumentCanvasView()
        v.setBlocks([.buttonRow(ButtonRowBlock(id: BlockID("r1"), buttons: [button("A")])),
                     .buttonRow(ButtonRowBlock(id: BlockID("r2"), buttons: [button("B")]))], width: 400)
        v.frame = CGRect(x: 0, y: 0, width: 400, height: 400); v.layoutSubtreeIfNeeded()
        let gap = v.boxes[1].frame.minY - v.boxes[0].frame.maxY
        XCTAssertEqual(gap, 8, accuracy: 0.5, "row↔row stacks at the base inset, not base + framed margin")
    }

    func test_makeSelectionInlineButtonWith_usesTheSheetButton() {
        let v = paragraphCanvas("Click here please")
        let start = v.boxes[0].textStart
        v.selectedGlobalRange = (start + 6, start + 10)               // "here"
        let configured = ButtonRef(label: [TextRun(text: "There")], action: .url("https://t.me"))
        v.makeSelectionInlineButton(with: configured)
        let p = (v.boxes[0] as! BlockBox).currentParagraph()
        XCTAssertEqual(p.text, "Click \u{FFFC} please")
        XCTAssertEqual(p.runs.first { $0.attributes.button != nil }?.attributes.button, configured,
                       "the pill carries the sheet's button, label edits included")
    }

    func test_typingOnPillAtom_opensParagraphAfterTheRow() {
        // The row is text-free — a keystroke with the caret parked on a pill atom must open a body
        // paragraph after the row, never be silently dropped.
        let row = ButtonRowBlock(id: BlockID("row"), buttons: [button("A")])
        let v = DocumentCanvasView()
        v.setBlocks([.buttonRow(row)], width: 400)
        let box = v.boxes[0] as! ButtonRowBox
        v.anchor = box.nodeStart + 1; v.head = box.nodeStart + 1
        v.commitText("x")
        XCTAssertEqual(v.boxes.count, 2)
        XCTAssertEqual((v.boxes[1] as? BlockBox)?.currentParagraph().text, "x")
        XCTAssertEqual(v.head, v.boxes[1].textStart + 1, "caret after the typed character")
    }

    func test_enterOnPillAtom_opensEmptyParagraphAfterTheRow() {
        let row = ButtonRowBlock(id: BlockID("row"), buttons: [button("A")])
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID.generate(), runs: [TextRun(text: "Hi")])),
                     .buttonRow(row)], width: 400)
        let box = v.boxes[1] as! ButtonRowBox
        v.anchor = box.nodeStart + 1; v.head = box.nodeStart + 1
        v.insertParagraphBreak()
        XCTAssertEqual(v.boxes.count, 3)
        XCTAssertEqual((v.boxes[2] as? BlockBox)?.currentParagraph().text, "")
        XCTAssertEqual(v.head, v.boxes[2].textStart, "caret in the fresh paragraph below the row")
    }

    func test_caretOnPillAtom_rendersAtThePillTrailingEdge() {
        // Standard atom semantics: the caret sits AFTER the thing Backspace would delete, like a
        // character or an emoji — never at the pill's leading edge (which reads as "before the button").
        let row = ButtonRowBlock(id: BlockID("row"), buttons: [button("A"), button("B")], alignment: .left)
        let v = DocumentCanvasView()
        v.setBlocks([.buttonRow(row)], width: 400)
        v.frame = CGRect(x: 0, y: 0, width: 400, height: 200); v.layoutSubtreeIfNeeded()
        let box = v.boxes[0] as! ButtonRowBox
        let rect = v.caretRect(forGlobal: box.nodeStart + 1)
        let pill = box.pillCanvasRect(0)!
        XCTAssertEqual(rect.minX, pill.maxX + 1, accuracy: 0.5, "the caret trails the pill it would delete")
        XCTAssertEqual(rect.height, pill.height, accuracy: 0.5)
    }

    func test_verticalNav_stepsThroughTheRow_bothDirections() {
        // The collapsed-quote / media-gap rule applied to rows: Down from a pill lands in the block
        // below, Up at the end of the block above — the arrow keys must never dead-end on a pill.
        let row = ButtonRowBlock(id: BlockID("row"), buttons: [button("A")])
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID.generate(), runs: [TextRun(text: "Up")])),
                     .buttonRow(row),
                     .paragraph(ParagraphBlock(id: BlockID.generate(), runs: [TextRun(text: "Down")]))], width: 400)
        v.frame = CGRect(x: 0, y: 0, width: 400, height: 400); v.layoutSubtreeIfNeeded()
        let box = v.boxes[1] as! ButtonRowBox
        let pill = box.nodeStart + 1
        XCTAssertEqual(v.verticalPosition(from: pill, down: true), v.boxes[2].textStart,
                       "Down from the pill lands at the start of the paragraph below")
        XCTAssertEqual(v.verticalPosition(from: pill, down: false), v.boxes[0].textStart + 2,
                       "Up from the pill lands at the end of the paragraph above")
        let fromAbove = v.verticalPosition(from: v.boxes[0].textStart, down: true)
        XCTAssertNotNil(v.buttonRowPill(at: fromAbove), "Down from the paragraph above lands on the pill atom")
    }

    func test_verticalNav_onTrailingRow_downIsANoop() {
        let row = ButtonRowBlock(id: BlockID("row"), buttons: [button("A")])
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID.generate(), runs: [TextRun(text: "Up")])),
                     .buttonRow(row)], width: 400)
        v.frame = CGRect(x: 0, y: 0, width: 400, height: 400); v.layoutSubtreeIfNeeded()
        let box = v.boxes[1] as! ButtonRowBox
        let pill = box.nodeStart + 1
        XCTAssertEqual(v.verticalPosition(from: pill, down: true), pill,
                       "Down at the document's bottom edge stays put rather than jumping backwards")
    }

    func test_pendingSheetCompletion_resolvesThePillByIdentity_afterIndicesShift() {
        // The property sheet stays open while the canvas can still mutate (window-level ⌘Z), so the
        // completion must act on the pill it was opened FOR, wherever it now sits — never a stale index.
        let row = ButtonRowBlock(id: BlockID("row"), buttons: [button("A"), button("B")])
        let v = DocumentCanvasView()
        v.setBlocks([.buttonRow(row)], width: 400)
        v.frame = CGRect(x: 0, y: 0, width: 400, height: 200); v.layoutSubtreeIfNeeded()
        var captured: ((ButtonRef?) -> Void)?
        v.buttonEditRequested = { clicked, _, completion in
            XCTAssertEqual(clicked.labelText, "B")
            captured = completion
        }
        let box = v.boxes[0] as! ButtonRowBox
        let pillB = box.pillCanvasRect(1)!
        XCTAssertTrue(v.handleButtonClickIfNeeded(at: CGPoint(x: pillB.midX, y: pillB.midY)))
        v.editing { v.deleteButtonPill(row: box, index: 0) }          // "A" deleted while the sheet is open
        let filled = ButtonRef(label: [TextRun(text: "B2")], action: .url("https://t.me"))
        captured?(filled)
        XCTAssertEqual(box.buttons, [filled], "the commit updates B — the pill the sheet was opened for, not index 1")
    }
}
#endif
