import Cocoa
import XCTest
import Postbox
import TelegramCore
import InAppSettings
@testable import InstantPageUI

final class InstantPageCollapsedQuoteTests: XCTestCase {
    private func layout(_ blocks: [InstantPageBlock], toggled: Set<Int> = []) -> InstantPageV2Layout {
        let page = InstantPage(blocks: blocks, media: [:], isComplete: true, rtl: false, url: "", views: nil)
        let content = TelegramMediaWebpageLoadedContent(url: "", displayUrl: "", hash: 0, type: nil, websiteName: nil, title: nil, text: nil, embedUrl: nil, embedType: nil, embedSize: nil, duration: nil, author: nil, isMediaLargeByDefault: nil, imageIsVideoCover: false, image: nil, file: nil, story: nil, attributes: [], instantPage: page)
        let webpage = TelegramMediaWebpage(webpageId: MediaId(namespace: 0, id: 0), content: .Loaded(content))
        let theme = instantPageThemeForType(.light, settings: InstantViewAppearance.defaultSettings)
        return layoutInstantPageV2(webpage: webpage, instantPage: page, boundingWidth: 320, horizontalInset: 0, theme: theme, toggledDetails: toggled)
    }

    private func details(in layout: InstantPageV2Layout) -> [InstantPageV2DetailsItem] {
        return layout.items.compactMap {
            if case let .details(item) = $0 { return item }
            return nil
        }
    }

    func testHiddenQuoteBecomesHighlightableAfterExpansion() throws {
        let blocks: [InstantPageBlock] = [.details(title: .plain("Section"), blocks: [.paragraph(.bold(.plain("before quoted passage after")))], expanded: false)]
        let collapsed = layout(blocks)
        XCTAssertNil(try XCTUnwrap(details(in: collapsed).first).innerLayout)
        let index = try XCTUnwrap(collapsed.collapsedDetailsIndex(forQuote: "quoted passage"))
        XCTAssertEqual(index, 0)
        XCTAssertNil(try XCTUnwrap(details(in: collapsed).first).innerLayout)

        let expanded = layout(blocks, toggled: [index])
        XCTAssertNil(expanded.collapsedDetailsIndex(forQuote: "quoted passage"))
        let body = try XCTUnwrap(details(in: expanded).first?.innerLayout)
        let texts = body.items.compactMap { item -> NSAttributedString? in
            if case let .text(text) = item { return text.textItem.attributedString }
            return nil
        }
        XCTAssertEqual(instantPageQuoteRanges(in: texts, text: "quoted passage"), [NSRange(location: 7, length: 14)])
    }

    func testNestedParentsExpandInOrder() throws {
        let blocks: [InstantPageBlock] = [
            .details(title: .plain("Outer"), blocks: [
                .details(title: .plain("Inner"), blocks: [.paragraph(.plain("deep quote"))], expanded: false)
            ], expanded: false),
            .details(title: .plain("Unrelated"), blocks: [.paragraph(.plain("other text"))], expanded: false)
        ]
        var toggled: Set<Int> = []
        for expected in [0, 1] {
            let index = try XCTUnwrap(layout(blocks, toggled: toggled).collapsedDetailsIndex(forQuote: "deep quote"))
            XCTAssertEqual(index, expected)
            toggled.insert(index)
        }
        let expanded = layout(blocks, toggled: toggled)
        XCTAssertNil(expanded.collapsedDetailsIndex(forQuote: "deep quote"))
        XCTAssertFalse(try XCTUnwrap(details(in: expanded).last).isExpanded)
    }

    func testExpansionPreservesOtherSectionsState() throws {
        let blocks: [InstantPageBlock] = [
            .details(title: .plain("Outer"), blocks: [
                .details(title: .plain("Inner"), blocks: [.paragraph(.plain("target"))], expanded: false)
            ], expanded: false),
            .details(title: .plain("Other"), blocks: [.paragraph(.plain("already open"))], expanded: false)
        ]
        let before = layout(blocks, toggled: [2])
        XCTAssertTrue(try XCTUnwrap(details(in: before).last).isExpanded)
        let after = layout(blocks, toggled: [0, 1, 2])
        XCTAssertTrue(try XCTUnwrap(details(in: after).last).isExpanded)
        XCTAssertEqual(details(in: before).map { $0.index }, details(in: after).map { $0.index })
    }

    func testUserCollapsedDefaultExpandedSectionCanBeReopened() throws {
        let blocks: [InstantPageBlock] = [.details(title: .plain("Section"), blocks: [.paragraph(.plain("target"))], expanded: true)]
        let collapsed = layout(blocks, toggled: [0])
        XCTAssertEqual(collapsed.collapsedDetailsIndex(forQuote: "target"), 0)
        let expanded = layout(blocks)
        XCTAssertTrue(try XCTUnwrap(details(in: expanded).first).isExpanded)
        XCTAssertNil(expanded.collapsedDetailsIndex(forQuote: "target"))
    }

    func testVisibleTitleAndMissingQuoteDoNotExpandSections() {
        let blocks: [InstantPageBlock] = [.details(title: .plain("Visible title"), blocks: [.paragraph(.plain("hidden body"))], expanded: false)]
        let collapsed = layout(blocks)
        XCTAssertNil(collapsed.collapsedDetailsIndex(forQuote: "Visible title"))
        XCTAssertNil(collapsed.collapsedDetailsIndex(forQuote: "missing"))
        XCTAssertNil(collapsed.collapsedDetailsIndex(forQuote: ""))
    }

    func testQuoteAcrossParagraphsInsideCollapsedSection() {
        let blocks: [InstantPageBlock] = [.details(title: .plain("Section"), blocks: [
            .paragraph(.plain("before first")), .paragraph(.italic(.plain("second after")))
        ], expanded: false)]
        XCTAssertEqual(layout(blocks).collapsedDetailsIndex(forQuote: "first\nsecond"), 0)
    }

    func testQuoteInsideTableInCollapsedSection() {
        let cell = InstantPageTableCell(text: .bold(.plain("table target")), header: false, alignment: .left, verticalAlignment: .top, colspan: 1, rowspan: 1)
        let table = InstantPageBlock.table(title: .empty, rows: [InstantPageTableRow(cells: [cell])], bordered: true, striped: false, compact: false)
        let blocks: [InstantPageBlock] = [.details(title: .plain("Section"), blocks: [table], expanded: false)]
        XCTAssertEqual(layout(blocks).collapsedDetailsIndex(forQuote: "table target"), 0)
    }

    func testNestedDetailsInListKeepSiblingIndicesStable() {
        let blocks: [InstantPageBlock] = [
            .details(title: .plain("Outer"), blocks: [.list(items: [
                .blocks([.details(title: .plain("Inner"), blocks: [.paragraph(.plain("target"))], expanded: false)], nil, nil)
            ], ordered: false)], expanded: false),
            .details(title: .plain("Sibling"), blocks: [.paragraph(.plain("sibling"))], expanded: false)
        ]
        XCTAssertEqual(details(in: layout(blocks)).map { $0.index }, [0, 2])
        XCTAssertEqual(details(in: layout(blocks, toggled: [0])).map { $0.index }, [0, 2])
        XCTAssertEqual(layout(blocks, toggled: [0]).collapsedDetailsIndex(forQuote: "target"), 1)
    }
}
