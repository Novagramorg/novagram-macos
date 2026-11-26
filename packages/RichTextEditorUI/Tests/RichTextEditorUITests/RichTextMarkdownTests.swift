#if canImport(AppKit)
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

/// Document ↔ Markdown serializer + parser. Pure-model (no AppKit), so these run fast under `swift test`.
final class RichTextMarkdownTests: XCTestCase {
    private func p(_ text: String, _ style: ParagraphStyleName = .body, list: ListMembership? = nil, _ runs: [TextRun]? = nil) -> Block {
        .paragraph(ParagraphBlock(id: BlockID.generate(), style: style, list: list, runs: runs ?? [TextRun(text: text)]))
    }
    private func md(_ blocks: [Block]) -> String { RichTextMarkdown.markdown(from: blocks) }
    private func parse(_ s: String) -> [Block] { RichTextMarkdown.blocks(from: s) }
    private func paras(_ blocks: [Block]) -> [ParagraphBlock] { blocks.compactMap { if case .paragraph(let p) = $0 { return p } else { return nil } } }

    // MARK: Serialize

    func test_serialize_headingsAndBody() {
        let out = md([p("Title", .heading1), p("Sub", .heading2), p("Body text")])
        XCTAssertEqual(out, "# Title\n\n## Sub\n\nBody text")
    }

    func test_headings1to6_roundTrip() {
        let blocks: [Block] = [p("A", .heading1), p("B", .heading2), p("C", .heading3),
                               p("D", .heading4), p("E", .heading5), p("F", .heading6)]
        XCTAssertEqual(md(blocks), "# A\n\n## B\n\n### C\n\n#### D\n\n##### E\n\n###### F")
        XCTAssertEqual(paras(parse(md(blocks))).map { $0.style },
                       [.heading1, .heading2, .heading3, .heading4, .heading5, .heading6])
    }

    func test_serialize_inlineFormats() {
        let runs = [TextRun(text: "a "), TextRun(text: "bold", attributes: CharacterAttributes(bold: true)),
                    TextRun(text: " "), TextRun(text: "it", attributes: CharacterAttributes(italic: true)),
                    TextRun(text: " "), TextRun(text: "code", attributes: CharacterAttributes(inlineCode: true))]
        XCTAssertEqual(md([p("", .body, list: nil, runs)]), "a **bold** _it_ `code`")
    }

    func test_serialize_linkAndFormula() {
        let runs = [TextRun(text: "see ", attributes: CharacterAttributes()),
                    TextRun(text: "site", attributes: CharacterAttributes(link: "https://t.me")),
                    TextRun(text: " and "), TextRun(text: "\u{FFFC}", attributes: CharacterAttributes(formula: "x^2"))]
        XCTAssertEqual(md([p("", .body, list: nil, runs)]), "see [site](https://t.me) and $x^2$")
    }

    func test_serialize_listsAndChecklist() {
        let bullet = ListMembership(marker: .bullet, level: 0)
        let nested = ListMembership(marker: .bullet, level: 1)
        let done = ListMembership(marker: .checklist, level: 0, checked: true)
        let todo = ListMembership(marker: .checklist, level: 0, checked: false)
        let out = md([p("one", .body, list: bullet), p("sub", .body, list: nested),
                      p("done", .body, list: done), p("todo", .body, list: todo)])
        XCTAssertEqual(out, "- one\n  - sub\n- [x] done\n- [ ] todo")
    }

    func test_serialize_blockquoteAndCode() {
        let quote = Block.blockQuote(BlockQuote(id: BlockID.generate(), children: [p("quoted", .body)]))
        let out = md([quote,
                      .code(CodeBlock(id: BlockID.generate(), language: "swift", runs: [TextRun(text: "let x = 1")]))])
        XCTAssertEqual(out, "> quoted\n\n```swift\nlet x = 1\n```")
    }

    func test_serialize_table() {
        let cols = [ColumnSpec(width: 100), ColumnSpec(width: 100)]
        func cell(_ t: String, _ h: TextAlignment = .left) -> Cell { Cell(id: BlockID.generate(), blocks: [.paragraph(ParagraphBlock(id: BlockID.generate(), runs: [TextRun(text: t)]))], horizontalAlignment: h) }
        // Alignment is per-cell now; markdown export reads the header row's cell alignment per column.
        let rows = [Row(id: BlockID.generate(), isHeader: true, cells: [cell("A", .left), cell("B", .center)]),
                    Row(id: BlockID.generate(), cells: [cell("1"), cell("2")])]
        let out = md([.table(TableBlock(id: BlockID.generate(), columns: cols, rows: rows))])
        XCTAssertEqual(out, "| A | B |\n| --- | :---: |\n| 1 | 2 |")
    }

    // MARK: Parse

    func test_parse_headingAndInline() {
        let blocks = parse("# Title\n\nhello **bold** _it_")
        XCTAssertEqual(paras(blocks).first?.style, .heading1)
        XCTAssertEqual(paras(blocks).first?.runs.map(\.text).joined(), "Title")
        let body = paras(blocks).last!
        XCTAssertEqual(body.runs.first(where: { $0.attributes.bold })?.text, "bold")
        XCTAssertEqual(body.runs.first(where: { $0.attributes.italic })?.text, "it")
    }

    func test_parse_checklistAndOrdered() {
        let blocks = parse("- [x] done\n- [ ] todo\n1. first\n2. second")
        let ps = paras(blocks)
        XCTAssertEqual(ps[0].list?.marker, .checklist); XCTAssertEqual(ps[0].list?.checked, true)
        XCTAssertEqual(ps[1].list?.checked, false)
        XCTAssertEqual(ps[2].list?.marker, .ordered)
        XCTAssertEqual(ps[3].runs.map(\.text).joined(), "second")
    }

    func test_parse_codeBlockAndQuote() {
        let blocks = parse("> quoted\n\n```py\nprint(1)\n```")
        guard case .blockQuote(let bq) = blocks.first, case .paragraph(let qp)? = bq.children.first else {
            return XCTFail("expected a blockQuote container")
        }
        XCTAssertEqual(qp.runs.map(\.text).joined(), "quoted")
        guard case .code(let code) = blocks.last else { return XCTFail() }
        XCTAssertEqual(code.language, "py")
        XCTAssertEqual(code.text, "print(1)")
    }

    func test_parse_link() {
        let blocks = parse("see [site](https://t.me) ok")
        let linked = paras(blocks).first?.runs.first(where: { $0.attributes.link != nil })
        XCTAssertEqual(linked?.text, "site")
        XCTAssertEqual(linked?.attributes.link, "https://t.me")
    }

    func test_parse_table() {
        let blocks = parse("| A | B |\n| --- | :---: |\n| 1 | 2 |")
        guard case .table(let table) = blocks.first else { return XCTFail() }
        XCTAssertEqual(table.rows.count, 2)
        XCTAssertTrue(table.rows[0].isHeader)
        XCTAssertEqual(table.rows[0].cells[1].horizontalAlignment, .center)
        if case .paragraph(let cellP)? = table.rows[1].cells.last?.blocks.first {
            XCTAssertEqual(cellP.runs.map(\.text).joined(), "2")
        } else { XCTFail() }
    }

    // MARK: Round-trip

    func test_roundTrip_mixedDocument() {
        let original: [Block] = [
            p("Title", .heading1),
            p("", .body, list: nil, [TextRun(text: "a "), TextRun(text: "b", attributes: CharacterAttributes(bold: true)),
                                     TextRun(text: " "), TextRun(text: "x", attributes: CharacterAttributes(link: "https://t.me"))]),
            p("item", .body, list: ListMembership(marker: .bullet, level: 0)),
            .blockQuote(BlockQuote(id: BlockID.generate(), children: [p("quoted", .body)])),
            .code(CodeBlock(id: BlockID.generate(), language: nil, runs: [TextRun(text: "code\nline2")])),
        ]
        let parsed = parse(md(original))
        let back = paras(parsed)
        XCTAssertEqual(back[0].style, .heading1)
        XCTAssertEqual(back[1].runs.first(where: { $0.attributes.bold })?.text, "b")
        XCTAssertEqual(back[1].runs.first(where: { $0.attributes.link != nil })?.attributes.link, "https://t.me")
        XCTAssertEqual(back[2].list?.marker, .bullet)
        XCTAssertTrue(parsed.contains { if case .blockQuote = $0 { return true } else { return false } },
                      "the quote round-trips as a blockQuote container")
        // the code block survives as a code block with its (multi-line) text
        let codeText = parse(md(original)).compactMap { if case .code(let c) = $0 { return c.text } else { return nil } }.first
        XCTAssertEqual(codeText, "code\nline2")
    }

    func test_roundTrip_escapesSpecialChars() {
        let runs = [TextRun(text: "2 * 3 = 6 and a_b")]
        let back = paras(parse(md([p("", .body, list: nil, runs)])))
        XCTAssertEqual(back.first?.runs.map(\.text).joined(), "2 * 3 = 6 and a_b", "literal * and _ survive via escaping")
    }
}
#endif
