import Foundation
import RichTextEditorCore

/// Document ↔ Markdown (GFM-flavoured) for the macOS editor. Package-local (operates on the public
/// `RichTextEditorCore` model), pure-Foundation and `swift test`-able; it does not touch shared Core/iOS.
///
/// Covered: headings (H1–H3), body, blockquote, fenced code blocks, bullet/ordered/checklist lists
/// (nested by indent), pipe tables (with column alignment), and inline bold/italic/strikethrough/inline-code
/// /links/formulas (`$…$`)/spoilers (`||…||`). Media blocks have no markdown form — their caption is kept as
/// a paragraph (the text survives; the attachment doesn't). The parser is `RichTextMarkdown.document(from:)`.
public enum RichTextMarkdown {

    // MARK: Serialize (Document → Markdown)

    public static func markdown(from document: Document) -> String {
        return markdown(from: document.blocks)
    }

    public static func markdown(from blocks: [Block]) -> String {
        var pieces: [String] = []
        var index = 0
        while index < blocks.count {
            let block = blocks[index]
            switch block {
            case let .paragraph(paragraph) where paragraph.list != nil:
                // Gather the consecutive run of list items into one list (no blank line between items).
                var run: [ParagraphBlock] = []
                while index < blocks.count, case let .paragraph(p) = blocks[index], p.list != nil {
                    run.append(p); index += 1
                }
                pieces.append(listMarkdown(run))
            case let .paragraph(paragraph):
                pieces.append(paragraphMarkdown(paragraph)); index += 1
            case let .code(code):
                pieces.append(codeMarkdown(code)); index += 1
            case let .table(table):
                pieces.append(tableMarkdown(table)); index += 1
            case let .media(media):
                // No markdown form for a local attachment — keep its caption text if any.
                if !media.caption.isEmpty { pieces.append(inline(media.caption)) }
                index += 1
            case let .pullQuote(quote):
                pieces.append(quote.text.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n"))
                index += 1
            case let .blockQuote(quote):
                // Recursive: prefix every line of the children's markdown with "> ".
                let innerMarkdown = markdown(from: quote.children)
                pieces.append(innerMarkdown.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n"))
                index += 1
            case let .details(details):
                // Markdown has no folding-block spelling, so the title degrades to a plain line above the
                // children's markdown. Content survives; the fold does not. macOS never builds a details
                // block (`coreBlocks(from:)` has no arm producing one), so this is a defensive path.
                let title = inline(details.title)
                let innerMarkdown = markdown(from: details.children)
                pieces.append(title.isEmpty ? innerMarkdown : title + "\n\n" + innerMarkdown)
                index += 1
            case let .buttonRow(row):
                // Markdown has no button spelling. A URL button degrades to a link, anything else to its
                // label text; the row itself (and non-URL actions) does not survive the round-trip.
                let rendered = row.buttons.map { button -> String in
                    if case let .url(url) = button.action, !url.isEmpty {
                        return "[" + escape(button.labelText) + "](" + url + ")"
                    }
                    return escape(button.labelText)
                }.filter { !$0.isEmpty }.joined(separator: " ")
                if !rendered.isEmpty { pieces.append(rendered) }
                index += 1
            }
        }
        return pieces.joined(separator: "\n\n")
    }

    private static func paragraphMarkdown(_ p: ParagraphBlock) -> String {
        let text = inline(p.runs)
        switch p.style {
        case .heading1: return "# " + text
        case .heading2: return "## " + text
        case .heading3: return "### " + text
        case .heading4: return "#### " + text
        case .heading5: return "##### " + text
        case .heading6: return "###### " + text
        case .body, .caption, .pullQuote: return text
        }
    }

    private static func codeMarkdown(_ code: CodeBlock) -> String {
        let fence = "```"
        return fence + (code.language ?? "") + "\n" + code.text + "\n" + fence
    }

    /// A consecutive run of list paragraphs → a markdown list. Nesting via 2-space indent per level;
    /// ordered items auto-number per level; checklist items use `- [ ]` / `- [x]`.
    private static func listMarkdown(_ items: [ParagraphBlock]) -> String {
        var lines: [String] = []
        var ordinalByLevel: [Int: Int] = [:]
        for item in items {
            guard let list = item.list else { continue }
            let indent = String(repeating: "  ", count: max(0, list.level))
            let bullet: String
            switch list.marker {
            case .bullet:
                bullet = "- "
            case .ordered:
                let n = (ordinalByLevel[list.level] ?? 0) + 1
                ordinalByLevel[list.level] = n
                bullet = "\(n). "
            case .checklist:
                bullet = (list.checked == true) ? "- [x] " : "- [ ] "
            }
            // A change of level resets deeper ordinals so a new sublist restarts numbering.
            for level in ordinalByLevel.keys where level > list.level { ordinalByLevel[level] = nil }
            lines.append(indent + bullet + inline(item.runs))
        }
        return lines.joined(separator: "\n")
    }

    private static func tableMarkdown(_ table: TableBlock) -> String {
        guard !table.rows.isEmpty else { return "" }
        let columnCount = table.columns.count
        func cells(_ row: Row) -> [String] {
            var out = (0 ..< columnCount).map { col -> String in
                guard col < row.cells.count else { return "" }
                return cellInline(row.cells[col])
            }
            if out.isEmpty { out = [""] }
            return out
        }
        func rowLine(_ cells: [String]) -> String { "| " + cells.joined(separator: " | ") + " |" }
        var lines: [String] = []
        // Header row: the first row (the editor's tables always have a header row).
        lines.append(rowLine(cells(table.rows[0])))
        // Delimiter row with per-column alignment.
        let delimiters = (0 ..< max(columnCount, 1)).map { col -> String in
            // Alignment is now per-cell; a markdown column takes the header row's cell alignment.
            let alignment: TextAlignment = {
                guard let headerCells = table.rows.first?.cells, col < headerCells.count else { return .left }
                return headerCells[col].horizontalAlignment
            }()
            switch alignment {
            case .center: return ":---:"
            case .right:  return "---:"
            case .left, .justified, .natural: return "---"
            }
        }
        lines.append("| " + delimiters.joined(separator: " | ") + " |")
        for row in table.rows.dropFirst() {
            lines.append(rowLine(cells(row)))
        }
        return lines.joined(separator: "\n")
    }

    /// A table cell's text: its paragraphs' inline markdown, joined by `<br>` (pipe tables can't hold a
    /// real newline). Non-paragraph cell content is dropped.
    private static func cellInline(_ cell: Cell) -> String {
        let parts = cell.blocks.compactMap { block -> String? in
            if case let .paragraph(p) = block { return inline(p.runs) }
            return nil
        }
        return parts.joined(separator: "<br>")
    }

    // MARK: Inline runs → Markdown

    static func inline(_ runs: [TextRun]) -> String {
        return runs.map(inline(_:)).joined()
    }

    private static func inline(_ run: TextRun) -> String {
        let a = run.attributes
        if let button = a.button {
            // No markdown button spelling: a URL button degrades to a link, anything else to its label.
            if case let .url(url) = button.action, !url.isEmpty {
                return "[" + escape(button.labelText) + "](" + url + ")"
            }
            return escape(button.labelText)
        }
        if let latex = a.formula, !latex.isEmpty {
            return "$" + latex + "$"
        }
        if let emoji = a.emoji {
            return emoji.altText ?? ""
        }
        if run.text.isEmpty { return "" }

        var text: String
        if a.inlineCode {
            text = "`" + run.text + "`"   // inline code is literal — no escaping, no nested emphasis
        } else {
            text = escape(run.text)
            if a.strikethrough { text = "~~" + text + "~~" }
            if a.italic { text = "_" + text + "_" }
            if a.bold { text = "**" + text + "**" }
            if a.spoiler { text = "||" + text + "||" }
        }
        if let link = a.link, !link.isEmpty {
            text = "[" + text + "](" + link + ")"
        }
        return text
    }

    /// Escape the markdown metacharacters that would otherwise be misparsed in body text.
    private static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "\\", "`", "*", "_", "[", "]", "|", "~":
                out.append("\\"); out.append(ch)
            default:
                out.append(ch)
            }
        }
        return out
    }

    // MARK: Parse (Markdown → Document)

    public static func document(from markdown: String) -> Document {
        return Document(blocks: blocks(from: markdown))
    }

    public static func blocks(from markdown: String) -> [Block] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [Block] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { i += 1; continue }   // blank line: block separator

            // Fenced code block.
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    body.append(lines[i]); i += 1
                }
                if i < lines.count { i += 1 }   // consume the closing fence
                result.append(.code(CodeBlock(id: BlockID.generate(), language: language.isEmpty ? nil : language,
                                              runs: [TextRun(text: body.joined(separator: "\n"))])))
                continue
            }

            // Pipe table: a `| … |` row immediately followed by a delimiter row.
            if line.contains("|"), i + 1 < lines.count, isDelimiterRow(lines[i + 1]) {
                let alignments = parseAlignments(lines[i + 1])
                var rowLines: [String] = [line]
                i += 2
                while i < lines.count, lines[i].contains("|"), !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    rowLines.append(lines[i]); i += 1
                }
                result.append(.table(parseTable(rowLines, alignments: alignments)))
                continue
            }

            // Heading (H1–H6).
            if let hashes = trimmed.prefix(while: { $0 == "#" }).count as Int?, hashes >= 1, hashes <= 6,
               trimmed.dropFirst(hashes).first == " " {
                let headingStyles: [ParagraphStyleName] = [.heading1, .heading2, .heading3, .heading4, .heading5, .heading6]
                let style = headingStyles[hashes - 1]
                let rest = String(trimmed.dropFirst(hashes + 1))
                result.append(.paragraph(ParagraphBlock(id: BlockID.generate(), style: style, runs: parseInline(rest))))
                i += 1; continue
            }

            // Blockquote: gather the consecutive "> " run into ONE recursive blockQuote container,
            // parsing the stripped inner lines as their own block sequence (so nested "> >" nests).
            if trimmed.hasPrefix(">") {
                var innerLines: [String] = []
                var j = i
                while j < lines.count {
                    let t = lines[j].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    innerLines.append(String(t.dropFirst()).trimmingCharacters(in: .whitespaces))
                    j += 1
                }
                let children = blocks(from: innerLines.joined(separator: "\n"))
                result.append(.blockQuote(BlockQuote(id: BlockID.generate(), children: children, collapsed: false)))
                i = j; continue
            }

            // List item (bullet / ordered / checklist), level from leading-space indent (2 spaces/level).
            if let item = parseListItem(line) {
                let membership = ListMembership(marker: item.marker, level: item.level, checked: item.checked)
                result.append(.paragraph(ParagraphBlock(id: BlockID.generate(), style: .body, list: membership,
                                                        runs: parseInline(item.content))))
                i += 1; continue
            }

            // Plain body paragraph.
            result.append(.paragraph(ParagraphBlock(id: BlockID.generate(), style: .body, runs: parseInline(trimmed))))
            i += 1
        }
        return result
    }

    // MARK: Block-parse helpers

    private static func isDelimiterRow(_ line: String) -> Bool {
        let cells = splitRow(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let c = cell.trimmingCharacters(in: .whitespaces)
            return !c.isEmpty && c.allSatisfy { $0 == "-" || $0 == ":" } && c.contains("-")
        }
    }

    private static func parseAlignments(_ delimiterLine: String) -> [TextAlignment] {
        return splitRow(delimiterLine).map { cell -> TextAlignment in
            let c = cell.trimmingCharacters(in: .whitespaces)
            let left = c.hasPrefix(":"), right = c.hasSuffix(":")
            if left && right { return .center }
            if right { return .right }
            return .left
        }
    }

    private static func parseTable(_ rowLines: [String], alignments: [TextAlignment]) -> TableBlock {
        let rowsCells = rowLines.map { splitRow($0) }
        let columnCount = max(alignments.count, rowsCells.map { $0.count }.max() ?? 0)
        let columns = (0 ..< max(columnCount, 1)).map { _ in ColumnSpec(width: 120) }
        let rows = rowsCells.enumerated().map { rowIndex, cells -> Row in
            let cellModels = (0 ..< max(columnCount, 1)).map { col -> Cell in
                let raw = col < cells.count ? cells[col] : ""
                let paragraphs = raw.components(separatedBy: "<br>").map { part in
                    Block.paragraph(ParagraphBlock(id: BlockID.generate(), style: .body, runs: parseInline(part.trimmingCharacters(in: .whitespaces))))
                }
                // Alignment moved from the column to the cell — apply the parsed per-column alignment here.
                return Cell(id: BlockID.generate(), blocks: paragraphs,
                            horizontalAlignment: col < alignments.count ? alignments[col] : .left)
            }
            return Row(id: BlockID.generate(), isHeader: rowIndex == 0, cells: cellModels)
        }
        return TableBlock(id: BlockID.generate(), columns: columns, rows: rows)
    }

    /// Split a `| a | b |` row into its cell strings (drops the leading/trailing pipe; honours `\|`).
    private static func splitRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        var cells: [String] = []
        var current = ""
        let chars = Array(trimmed)
        var i = 0
        while i < chars.count {
            if chars[i] == "\\", i + 1 < chars.count { current.append(chars[i]); current.append(chars[i + 1]); i += 2; continue }
            if chars[i] == "|" { cells.append(current); current = ""; i += 1; continue }
            current.append(chars[i]); i += 1
        }
        cells.append(current)
        return cells
    }

    private struct ListItem { let marker: ListMarker; let level: Int; let checked: Bool?; let content: String }

    private static func parseListItem(_ line: String) -> ListItem? {
        let leadingSpaces = line.prefix(while: { $0 == " " }).count
        let level = leadingSpaces / 2
        let body = line.drop(while: { $0 == " " })
        // Ordered: "N. "
        if let dot = body.firstIndex(of: "."), body[body.startIndex ..< dot].allSatisfy({ $0.isNumber }),
           body[body.startIndex] .isNumber, body.index(after: dot) < body.endIndex, body[body.index(after: dot)] == " " {
            let content = String(body[body.index(body.index(after: dot), offsetBy: 1)...])
            return ListItem(marker: .ordered, level: level, checked: nil, content: content)
        }
        // Bullet / checklist: "- " or "* "
        if body.hasPrefix("- ") || body.hasPrefix("* ") {
            let content = String(body.dropFirst(2))
            if content.hasPrefix("[ ] ") { return ListItem(marker: .checklist, level: level, checked: false, content: String(content.dropFirst(4))) }
            if content.hasPrefix("[x] ") || content.hasPrefix("[X] ") { return ListItem(marker: .checklist, level: level, checked: true, content: String(content.dropFirst(4))) }
            return ListItem(marker: .bullet, level: level, checked: nil, content: content)
        }
        return nil
    }

    // MARK: Inline parse (Markdown → [TextRun])

    static func parseInline(_ s: String) -> [TextRun] {
        var runs: [TextRun] = []
        parseInline(Array(s), base: CharacterAttributes(), into: &runs)
        return mergeAdjacent(runs)
    }

    private static func parseInline(_ chars: [Character], base: CharacterAttributes, into runs: inout [TextRun]) {
        var plain = ""
        var i = 0
        func flush() { if !plain.isEmpty { runs.append(TextRun(text: plain, attributes: base)); plain = "" } }
        func recurse(_ range: Range<Int>, _ attrs: CharacterAttributes) { parseInline(Array(chars[range]), base: attrs, into: &runs) }

        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count { plain.append(chars[i + 1]); i += 2; continue }

            if c == "`", let close = findChar(chars, "`", from: i + 1) {
                flush(); var a = base; a.inlineCode = true
                runs.append(TextRun(text: String(chars[(i + 1) ..< close]), attributes: a))   // literal
                i = close + 1; continue
            }
            if c == "$", let close = findChar(chars, "$", from: i + 1) {
                flush(); var a = base; a.formula = String(chars[(i + 1) ..< close])
                runs.append(TextRun(text: "\u{FFFC}", attributes: a))
                i = close + 1; continue
            }
            if c == "[", let link = parseLink(chars, from: i) {
                flush(); var a = base; a.link = link.url
                recurse(link.text, a); i = link.end; continue
            }
            if c == "*", i + 1 < chars.count, chars[i + 1] == "*", let close = findSeq(chars, ["*", "*"], from: i + 2) {
                flush(); var a = base; a.bold = true; recurse((i + 2) ..< close, a); i = close + 2; continue
            }
            if c == "~", i + 1 < chars.count, chars[i + 1] == "~", let close = findSeq(chars, ["~", "~"], from: i + 2) {
                flush(); var a = base; a.strikethrough = true; recurse((i + 2) ..< close, a); i = close + 2; continue
            }
            if c == "|", i + 1 < chars.count, chars[i + 1] == "|", let close = findSeq(chars, ["|", "|"], from: i + 2) {
                flush(); var a = base; a.spoiler = true; recurse((i + 2) ..< close, a); i = close + 2; continue
            }
            if (c == "_" || c == "*"), let close = findChar(chars, c, from: i + 1) {
                flush(); var a = base; a.italic = true; recurse((i + 1) ..< close, a); i = close + 1; continue
            }
            plain.append(c); i += 1
        }
        flush()
    }

    private static func findChar(_ chars: [Character], _ target: Character, from: Int) -> Int? {
        var i = from
        while i < chars.count {
            if chars[i] == "\\" { i += 2; continue }
            if chars[i] == target { return i }
            i += 1
        }
        return nil
    }

    private static func findSeq(_ chars: [Character], _ seq: [Character], from: Int) -> Int? {
        var i = from
        while i + seq.count <= chars.count {
            if chars[i] == "\\" { i += 2; continue }
            if Array(chars[i ..< i + seq.count]) == seq { return i }
            i += 1
        }
        return nil
    }

    private static func parseLink(_ chars: [Character], from: Int) -> (text: Range<Int>, url: String, end: Int)? {
        guard chars[from] == "[", let closeBracket = findChar(chars, "]", from: from + 1),
              closeBracket + 1 < chars.count, chars[closeBracket + 1] == "(",
              let closeParen = findChar(chars, ")", from: closeBracket + 2) else { return nil }
        let url = String(chars[(closeBracket + 2) ..< closeParen])
        return ((from + 1) ..< closeBracket, url, closeParen + 1)
    }

    /// Merge consecutive runs that carry identical attributes (keeps the run list tidy after recursion).
    private static func mergeAdjacent(_ runs: [TextRun]) -> [TextRun] {
        var out: [TextRun] = []
        for run in runs {
            if var last = out.last, last.attributes == run.attributes,
               last.attributes.formula == nil, run.attributes.formula == nil,
               last.attributes.button == nil, run.attributes.button == nil {
                last.text += run.text
                out[out.count - 1] = last
            } else {
                out.append(run)
            }
        }
        return out
    }
}
