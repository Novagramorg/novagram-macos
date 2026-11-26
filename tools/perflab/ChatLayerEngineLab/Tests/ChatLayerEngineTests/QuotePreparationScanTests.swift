import Cocoa
import XCTest
import TGUIKit
import InputTextView
@testable import ChatLayerEngine

final class QuotePreparationScanTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func testGeneralPresentationPreservesLastQuoteTypeAcrossMixedAttributes() {
        let values: [Any] = [TextViewBlockQuoteData(id: 1, colors: .init(main: .blue)), NSNull(), TextViewBlockQuoteData(id: 2, colors: .init(main: .red), collapsable: true)]
        for sample in 0..<1024 {
            let text = NSMutableAttributedString(string: "first\nsecond\nthird\nfourth", attributes: [.font: NSFont.systemFont(ofSize: 14)])
            for index in 0..<text.length {
                if sample & (1 << (index % 10)) != 0 { text.addAttribute(TextInputAttributes.quote, value: values[(sample + index / 3) % values.count], range: NSRange(location: index, length: 1)) }
                if sample % 7 == 0 { text.addAttribute(.link, value: "target", range: NSRange(location: index, length: 1)) }
            }
            let layout = TextViewLayout(text)
            layout.measure(width: 100)
            let source = FoldingTextLayout(blocks: [.init(text: layout, isRevealed: sample % 2 == 0, size: NSSize(width: 100, height: 30))], appendingAnimation: sample % 13 == 0)
            let current = ChatLayerMessageTextPresentation(source), previous = ChatLayerMessageTextPresentation.referencePresentation(source)
            XCTAssertEqual(current.size, previous.size)
            XCTAssertEqual(current.nativeFeatures, previous.nativeFeatures)
            XCTAssertEqual(current.requiresRevealAction, previous.requiresRevealAction)
            XCTAssertEqual(current.blocks.map(\.frame), previous.blocks.map(\.frame))
            XCTAssertEqual(current.blocks.map(\.hasLinks), previous.blocks.map(\.hasLinks))
            XCTAssertEqual(current.blocks.map(\.clipsTextToBounds), previous.blocks.map(\.clipsTextToBounds))
            XCTAssertEqual(current.blocks.map { $0.folding != nil }, previous.blocks.map { $0.folding != nil })
        }
    }
}
