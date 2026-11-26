#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// The list state across the selection's touched paragraphs: uniformly no list, a single shared marker,
/// or a mix (so no list menu item is shown selected).
@available(macOS 12, *)
public enum ParagraphListSelection: Equatable {
    case none
    case marker(ListMarker)
    case mixed
}

/// The active paragraph-level formatting across the selection's touched paragraphs — what a host
/// toolbar highlights. Each field is the uniform value, or nil / `.mixed` when the touched paragraphs
/// disagree (so no menu item is marked selected).
@available(macOS 12, *)
public struct ParagraphFormatState: Equatable {
    public var style: ParagraphStyleName?
    public var list: ParagraphListSelection
    public var alignment: TextAlignment?
    /// Number of `Block.blockQuote` containers enclosing the caret (0 = not in a quote). Drives a
    /// host toolbar's Quote check-state (≥1 → checked).
    public var blockQuoteDepth: Int
    /// True when the caret/selection is inside a pull-quote block.
    public var isPullQuote: Bool
    public init(style: ParagraphStyleName? = nil, list: ParagraphListSelection = .none, alignment: TextAlignment? = nil, blockQuoteDepth: Int = 0, isPullQuote: Bool = false) {
        self.style = style
        self.list = list
        self.alignment = alignment
        self.blockQuoteDepth = blockQuoteDepth
        self.isPullQuote = isPullQuote
    }
}

/// Paragraph-level formatting commands. They apply to every top-level `BlockBox` the selection
/// touches (a collapsed caret = its one paragraph), mutate the box's `style` / `paragraphAttributes`,
/// and run inside `editing { }` for undo. Top-level only in 5a — paragraph styles inside table cells
/// (headings in cells aren't meaningful GFM) are out of scope.
@available(macOS 12, *)
extension DocumentCanvasView {
    /// The active paragraph style / list / alignment across the touched paragraphs (same set
    /// `setParagraphStyle`/`setList`/`setAlignment` mutate) — for a host toolbar's selected-item marks.
    /// Whether the current selection touches a block's text range `[lo, hi]`. A collapsed caret matches
    /// inclusively (a caret at either edge counts); a non-empty selection requires `selTo > lo` so a
    /// selection that ENDS exactly at the next paragraph's start doesn't spill the paragraph operation into
    /// that untouched neighbor (the "select line 1, format it, line 2 also changes" bug).
    func selectionTouchesRange(lo: Int, hi: Int) -> Bool {
        guard selFrom <= hi else { return false }
        return selFrom == selTo ? selFrom >= lo : selTo > lo
    }

    func currentParagraphFormatState() -> ParagraphFormatState {
        var styles: [ParagraphStyleName] = []
        var markers: [ListMarker?] = []
        var alignments: [TextAlignment] = []
        for box in boxes {
            guard let p = box as? BlockBox else { continue }
            let lo = p.textStart, hi = p.textStart + p.textLength
            guard selectionTouchesRange(lo: lo, hi: hi) else { continue }
            styles.append(p.style)
            markers.append(p.listMembership?.marker)
            alignments.append(p.paragraphAttributes.alignment)
        }
        let style = (!styles.isEmpty && styles.allSatisfy { $0 == styles[0] }) ? styles[0] : nil
        let alignment = (!alignments.isEmpty && alignments.allSatisfy { $0 == alignments[0] }) ? alignments[0] : nil
        let nonNil = markers.compactMap { $0 }
        let list: ParagraphListSelection
        if nonNil.isEmpty {
            list = .none
        } else if markers.allSatisfy({ $0 != nil }) && nonNil.allSatisfy({ $0 == nonNil[0] }) {
            list = .marker(nonNil[0])
        } else {
            list = .mixed
        }
        return ParagraphFormatState(style: style, list: list, alignment: alignment,
                                    blockQuoteDepth: blockQuoteDepth(at: head),
                                    isPullQuote: resolveBox(at: selFrom)?.box is PullQuoteBox)
    }

    /// Assigns a named paragraph style (Title/H1–H3/Body/Quote) to the touched paragraphs and rebuilds
    /// their run layout so the style's font (size/weight) actually applies. Run size/family pins are
    /// cleared so the style decides them; user bold/italic/strike/code and links are preserved.
    /// Known limitation: a heading injects bold that round-trips into the model, so down-converting a
    /// heading to body can leave residual bold (cosmetic; revisited when the markdown layer separates
    /// style fonts from char emphasis).
    func setParagraphStyle(_ name: ParagraphStyleName) {
        guard !boxes.isEmpty else { return }
        editing {
            for box in boxes {
                guard let p = box as? BlockBox else { continue }
                let lo = p.textStart, hi = p.textStart + p.textLength
                guard selectionTouchesRange(lo: lo, hi: hi) else { continue }
                p.style = name
                var para = p.currentParagraph()
                para.runs = para.runs.map { run in
                    var a = run.attributes
                    a.fontSize = nil
                    a.fontFamily = nil
                    return TextRun(text: run.text, attributes: a)
                }
                p.layout.attributedString = mapper.attributedString(for: para)
            }
            recomputeSpans()
        }
    }

    /// Toggle the touched top-level paragraphs into a single code block, or (if the selection is already a
    /// single code block) toggle it back into body paragraphs split on "\n". Top-level only. Runs in
    /// `editing { }`.
    func makeCodeBlock() {
        guard !boxes.isEmpty else { return }
        let touched = boxes.indices.filter { i in
            let b = boxes[i]
            let lo = b.textStart, hi = b.textStart + b.textLength
            return selectionTouchesRange(lo: lo, hi: hi)
        }
        guard let first = touched.first, let last = touched.last else { return }
        func boxText(_ box: CanvasBlock) -> String? {
            if let p = box as? BlockBox { return p.currentParagraph().text }
            if let c = box as? CodeBlockBox { return c.currentCode().text }
            return nil   // media/table: no flat-text representation
        }
        let isToggleOff = touched.count == 1 && boxes[first] is CodeBlockBox
        // Refuse a toggle-ON that spans a non-text block (image/table) — replaceSubrange would
        // otherwise silently delete it. Must run BEFORE `editing { }` to avoid a no-op undo entry.
        if !isToggleOff, (first...last).contains(where: { boxText(boxes[$0]) == nil }) { return }
        editing {
            if isToggleOff, let codeBox = boxes[first] as? CodeBlockBox {
                let lines = codeBox.currentCode().text.components(separatedBy: "\n")
                let paras: [CanvasBlock] = lines.map { line in
                    BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), style: .body,
                                                       runs: line.isEmpty ? [] : [TextRun(text: line)]),
                             mapper: mapper, width: effectiveWidth)
                }
                var newBoxes = boxes
                newBoxes.replaceSubrange(first...first, with: paras)
                boxes = newBoxes
                recomputeSpans()
                anchor = paras[0].textStart; head = paras[0].textStart
                return
            }
            let text = (first...last).compactMap { boxText(boxes[$0]) }.joined(separator: "\n")
            let codeBox = CodeBlockBox(code: CodeBlock(id: BlockID.generate(), language: nil,
                                                       runs: [TextRun(text: text)]),
                                       mapper: mapper, width: effectiveWidth)
            var newBoxes = boxes
            newBoxes.replaceSubrange(first...last, with: [codeBox])
            boxes = newBoxes
            recomputeSpans()
            anchor = codeBox.textStart + codeBox.textLength
            head = anchor
        }
    }

    /// True when the caret's (or selection start's) owning box is a code block (any nesting depth) —
    /// its code text OR its language line. The language line resolves to no `activeStack` (by design,
    /// see `activeStack`), so the box test alone would report false there and a host toolbar would stop
    /// showing the block as code mid-edit.
    func isCaretInCodeBlock() -> Bool {
        caretCodeBox() != nil
    }

    /// The `CodeBlockBox` the caret (selection start) sits in — via `activeStack` for a code-text caret,
    /// via the region + `stackContainingCodeBox` for a language-line caret (off `activeStack`'s radar).
    func caretCodeBox() -> CodeBlockBox? {
        if let code = activeStack(at: selFrom)?.box as? CodeBlockBox { return code }
        if let (region, _) = leafRegion(containingGlobal: selFrom),
           case let .codeLanguage(id) = region.ref {
            return stackContainingCodeBox(id: id)?.box
        }
        return nil
    }

    /// The language of the caret's code block (nil when not in a code block / no language set).
    func caretCodeBlockLanguage() -> String? {
        caretCodeBox()?.currentCode().language
    }

    /// Sets (or clears, on empty/nil) the caret's code-block language — now simply a programmatic write
    /// into the block's editable language line. One undo step; the line's height tracks its content, so
    /// the block re-lays.
    func setCodeBlockLanguage(_ language: String?) {
        guard let code = caretCodeBox() else { return }
        let normalized = language?.trimmingCharacters(in: .whitespacesAndNewlines)
        editing {
            code.languageLayout.attributedString = CodeBlockBox.languageAttributedString(
                for: (normalized?.isEmpty == false) ? normalized : nil, appearance: mapper.appearance)
            recomputeSpans()
            anchor = clampGlobal(anchor); head = clampGlobal(head)
        }
    }

    /// Sets paragraph alignment on the touched paragraphs. Alignment is a pure paragraph-style
    /// property, so `restyle` (which re-applies `.paragraphStyle`) suffices — no font rebuild.
    func setAlignment(_ alignment: TextAlignment) {
        guard !boxes.isEmpty else { return }
        editing {
            for box in boxes {
                guard let p = box as? BlockBox else { continue }
                let lo = p.textStart, hi = p.textStart + p.textLength
                guard selectionTouchesRange(lo: lo, hi: hi) else { continue }
                p.paragraphAttributes.alignment = alignment
                restyle(p)
            }
            recomputeSpans()
        }
    }

    // MARK: - Block quote (recursive container) commands

    /// Wraps the touched block(s) of the active stack into one `Block.blockQuote`, preserving them as
    /// children. When the caret is already inside a block quote, the active stack is that quote's child
    /// stack, so re-applying Quote nests one level deeper. Runs in `editing { }`.
    ///
    /// No-ops when the caret (or either selection endpoint) is inside a table cell — wrapping a cell's
    /// content into a block quote is not supported.
    func wrapInBlockQuote() {
        let lo = min(selFrom, selTo), hi = max(selFrom, selTo)
        guard !isInsideTable(lo), !isInsideTable(hi) else { return }
        guard sameOwningStack(lo, hi), let owning = activeStack(at: lo)?.stack else {
            wrapTopLevelInBlockQuote(); return
        }
        let stackBoxes = owning.boxes
        let touched = stackBoxes.indices.filter { i in
            let b = stackBoxes[i]; return lo <= b.textStart + b.textLength && hi >= b.textStart
        }
        guard let first = touched.first, let last = touched.last else { return }
        let children = (first...last).map { stackBoxes[$0].currentBlock() }
        let bqBox = BlockQuoteBox(blockQuote: BlockQuote(id: .generate(), children: children, collapsed: false),
                                  mapper: mapper, width: effectiveWidth)
        editing {
            owning.boxes.replaceSubrange(first...last, with: [bqBox])
            recomputeSpans()
            let caret = bqBox.children.boxes.first?.leafRegions().first?.globalStart ?? (bqBox.nodeStart + 1)
            anchor = caret; head = caret
        }
    }

    /// Fallback for cross-stack selections: wraps the touched TOP-LEVEL boxes into one blockQuote.
    private func wrapTopLevelInBlockQuote() {
        let lo = min(selFrom, selTo), hi = max(selFrom, selTo)
        let touched = boxes.indices.filter { i in
            let b = boxes[i]; return lo <= b.textStart + b.textLength && hi >= b.textStart
        }
        guard let first = touched.first, let last = touched.last else { return }
        let children = (first...last).map { boxes[$0].currentBlock() }
        let bqBox = BlockQuoteBox(blockQuote: BlockQuote(id: .generate(), children: children, collapsed: false),
                                  mapper: mapper, width: effectiveWidth)
        editing {
            var newBoxes = boxes
            newBoxes.replaceSubrange(first...last, with: [bqBox])
            boxes = newBoxes
            recomputeSpans()
            let caret = bqBox.children.boxes.first?.leafRegions().first?.globalStart ?? (bqBox.nodeStart + 1)
            anchor = caret; head = caret
        }
    }

    /// The DEEPEST BlockQuoteBox whose token span contains `pos`, plus the stack it lives in and its index.
    func enclosingBlockQuote(at pos: Int) -> (box: BlockQuoteBox, parentStack: BlockStack, index: Int)? {
        var result: (BlockQuoteBox, BlockStack, Int)? = nil
        func descend(_ stack: BlockStack) {
            for (i, b) in stack.boxes.enumerated() {
                if let bq = b as? BlockQuoteBox, pos > b.nodeStart, pos < b.nodeStart + b.nodeSize {
                    result = (bq, stack, i)          // record; a deeper quote inside overwrites it
                    descend(bq.children)
                } else if let t = b as? TableBlockBox, pos > b.nodeStart, pos < b.nodeStart + b.nodeSize {
                    for row in t.cells { for cell in row { descend(cell) } }
                }
            }
        }
        descend(root)
        return result
    }

    /// "None": removes exactly one block-quote level around the caret — the deepest enclosing quote's
    /// children are spliced back into its parent stack in place. Runs in `editing { }`.
    func unwrapBlockQuoteLevel() {
        guard let (bqBox, parentStack, index) = enclosingBlockQuote(at: min(anchor, head)) else { return }
        guard case .blockQuote(let model) = bqBox.currentBlock() else { return }
        let childBoxes = model.children.compactMap {
            makeBox(for: $0, mapper: mapper, width: effectiveWidth)
        }
        editing {
            parentStack.boxes.replaceSubrange(index...index, with: childBoxes)
            recomputeSpans()
            let caret = childBoxes.first?.leafRegions().first?.globalStart ?? bqBox.nodeStart
            anchor = caret; head = caret
        }
    }

    /// If the caret sits on an EMPTY child that is the LAST child of its enclosing block quote, exit:
    /// remove that empty child and drop a body paragraph AFTER the quote (or, if it was the quote's only
    /// child, REPLACE the quote with that body paragraph). Returns true when it handled the exit.
    func blockQuoteEmptyTrailingChildExit() -> Bool {
        guard let active = activeStack(at: head), let child = active.box as? BlockBox, child.textLength == 0,
              let (bqBox, parentStack, index) = enclosingBlockQuote(at: head),
              bqBox.children.boxes.last === child else { return false }
        editing {
            let body = BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), style: .body, runs: []),
                                mapper: mapper, width: effectiveWidth)
            if bqBox.children.boxes.count == 1 {
                parentStack.boxes.replaceSubrange(index...index, with: [body])  // wholly-empty quote → body
            } else {
                bqBox.children.boxes.removeLast()                                // drop the empty trailing child
                parentStack.boxes.insert(body, at: index + 1)                    // body after the quote
            }
            recomputeSpans()
            let caret = body.leafRegions().first?.globalStart ?? body.nodeStart
            anchor = caret; head = caret
        }
        return true
    }

    /// Number of block quotes enclosing `pos` (0 = not in a quote; N = nested N levels deep).
    func blockQuoteDepth(at pos: Int) -> Int {
        var depth = 0
        func descend(_ stack: BlockStack) {
            for b in stack.boxes {
                if let bq = b as? BlockQuoteBox, pos > b.nodeStart, pos < b.nodeStart + b.nodeSize {
                    depth += 1; descend(bq.children)
                } else if let t = b as? TableBlockBox, pos > b.nodeStart, pos < b.nodeStart + b.nodeSize {
                    for row in t.cells { for cell in row { descend(cell) } }
                }
            }
        }
        descend(root)
        return depth
    }

    // MARK: - Pull quote

    /// Toggle the touched top-level paragraphs into one pull quote, or (if the selection is a single
    /// pull quote) toggle it back into body paragraphs split on "\n". Mirrors `makeCodeBlock`.
    func makePullQuote() {
        guard !boxes.isEmpty else { return }
        let touched = boxes.indices.filter { i in
            let b = boxes[i]
            let lo = b.textStart, hi = b.textStart + b.textLength
            return selectionTouchesRange(lo: lo, hi: hi)
        }
        guard let first = touched.first, let last = touched.last else { return }
        func boxRuns(_ box: CanvasBlock) -> [TextRun]? {
            if let p = box as? BlockBox { return p.currentParagraph().runs }
            if let pq = box as? PullQuoteBox, case let .pullQuote(model) = pq.currentBlock() { return model.runs }
            return nil   // media/table/code: not pull-quotable
        }
        let isToggleOff = touched.count == 1 && boxes[first] is PullQuoteBox
        if !isToggleOff, (first...last).contains(where: { boxRuns(boxes[$0]) == nil }) { return }
        editing {
            if isToggleOff, let pqBox = boxes[first] as? PullQuoteBox, case let .pullQuote(model) = pqBox.currentBlock() {
                let paras: [CanvasBlock] = splitRunsOnNewlines(model.runs).map { runs in
                    BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), style: .body, runs: runs),
                             mapper: mapper, width: effectiveWidth)
                }
                var newBoxes = boxes
                newBoxes.replaceSubrange(first...first, with: paras.isEmpty ? [BlockBox(paragraph: ParagraphBlock(id: BlockID.generate()), mapper: mapper, width: effectiveWidth)] : paras)
                boxes = newBoxes
                recomputeSpans()
                anchor = newBoxes[first].textStart; head = anchor
                return
            }
            var runs: [TextRun] = []
            for i in first...last {
                if !runs.isEmpty { runs.append(TextRun(text: "\n")) }
                runs.append(contentsOf: boxRuns(boxes[i]) ?? [])
            }
            let pqBox = PullQuoteBox(pullQuote: PullQuote(id: BlockID.generate(), runs: runs),
                                     mapper: mapper, width: effectiveWidth)
            var newBoxes = boxes
            newBoxes.replaceSubrange(first...last, with: [pqBox])
            boxes = newBoxes
            recomputeSpans()
            anchor = pqBox.textStart + pqBox.textLength
            head = anchor
        }
    }

    /// Splits a run array into paragraph-run arrays on "\n" boundaries (the runs may carry interior newlines).
    func splitRunsOnNewlines(_ runs: [TextRun]) -> [[TextRun]] {
        var paras: [[TextRun]] = [[]]
        for run in runs {
            let parts = run.text.components(separatedBy: "\n")
            for (i, part) in parts.enumerated() {
                if i > 0 { paras.append([]) }
                if !part.isEmpty { paras[paras.count - 1].append(TextRun(text: part, attributes: run.attributes)) }
            }
        }
        return paras.filter { !( $0.isEmpty && paras.count == 1 ) }
    }
}
#endif
