#if canImport(AppKit)
import AppKit
import XCTest
import RichTextEditorCore
@testable import RichTextEditorUI

@available(macOS 12, *)
final class EmojiTests: XCTestCase {
    func testForwardMapProducesAttachment() {
        let mapper = AttributedStringMapper()
        var ca = CharacterAttributes()
        ca.emoji = EmojiRef(id: "e1", instanceID: "i1", altText: "😀")
        let dict = mapper.attributes(for: ca, style: .body)
        XCTAssertEqual((dict[.attachment] as? EmojiTextAttachment)?.ref.id, "e1")
    }

    func testReadBackRecoversRef() {
        let mapper = AttributedStringMapper()
        let dict: [NSAttributedString.Key: Any] = [
            .attachment: EmojiTextAttachment(ref: EmojiRef(id: "e1", instanceID: "i1"), scale: 1.0)
        ]
        XCTAssertEqual(mapper.characterAttributes(from: dict).emoji?.id, "e1")
    }

    func testInsertEmojiPlacesSingleObjectReplacementChar() {
        let view = RichTextEditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        view.document = Document(blocks: [.paragraph(ParagraphBlock(id: .generate(), runs: [TextRun(text: "hi")]))])
        view.layoutSubtreeIfNeeded()
        view.makeEditorFirstResponder()
        view.registerEmojiViewProvider { _, size in NSView(frame: CGRect(origin: .zero, size: size)) }
        view.selectAll()
        view.insertEmoji(id: "e1", altText: "😀")
        guard case let .paragraph(p) = view.document.blocks[0] else { return XCTFail("expected paragraph") }
        let emojiRuns = p.runs.filter { $0.attributes.emoji != nil }
        XCTAssertEqual(emojiRuns.count, 1)
        XCTAssertEqual(emojiRuns.first?.text, "\u{FFFC}")
    }
}
#endif
