import Cocoa
import XCTest
import TGUIKit
import SwiftSignalKit
@testable import FoldingViewHarness
@testable import ChatLayerEngine

final class LayerCaptionTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }
    let fixtures = CaptionReuseTests()

    func nativeCaption(_ id: Int, text: String? = nil, context: BlockContext) -> FoldingViewHarness.ChatRowItem.RowCaption {
        let caption = fixtures.caption(id, text: text, context: context, quoted: true)
        (caption.layout.blocks[0].text.attributedString as! NSMutableAttributedString).addAttribute(TextInputAttributes.formattedDate, value: "date", range: NSRange(location: 0, length: 1))
        return caption
    }

    func testPlainCaptionsUseOneHostAndReserveUnchangedSiblingsBeforeReuse() throws {
        let context = BlockContext(), row = LayerCaptionRow(frame: .zero)
        let first = fixtures.caption(1, context: context, blocks: 3), second = fixtures.caption(2, context: context), third = fixtures.caption(3, context: context)
        row.bind(ChatRowItem([first, second, third]))
        let originals = row.contentViews
        XCTAssertTrue(row.views.isEmpty)
        XCTAssertEqual(originals.map(viewTreeCount), [1, 1, 1])
        let next = ChatRowItem([fixtures.caption(4, context: context), second, first])
        row.bind(next)
        XCTAssertTrue(row.contentViews[0] === originals[2])
        XCTAssertTrue(row.contentViews[1] === originals[1])
        XCTAssertTrue(row.contentViews[2] === originals[0])
        XCTAssertEqual(row.ids, [4, 2, 1])
        XCTAssertEqual(row.rowView.subviews.count, 4)
        XCTAssertEqual(row.textSelectionSources.count, 5)
    }

    func testSameCaptionPreservesSelectionAndLoadingIdentity() throws {
        for external in [false, true] {
            let context = BlockContext(), row = LayerCaptionRow(frame: .zero)
            row.bind(ChatRowItem([fixtures.caption(1, context: context)]))
            let host = try XCTUnwrap(row.captionViews[0].layerView), node = host.body.textNodes[0]
            let range = NSRange(location: 1, length: 4)
            if external { node.setExternalSelection(range) } else { node.setSelection(range) }
            for loading in [true, false] {
                let next = fixtures.caption(1, context: context, loading: loading)
                row.bind(ChatRowItem([next]))
                XCTAssertTrue(row.captionViews[0].layerView === host)
                XCTAssertEqual(next.layout.blocks[0].text.selectedRange.range, range)
                XCTAssertEqual(node.hasExternalTextSelection, external)
                XCTAssertEqual(row.shimmers, [loading])
            }
        }
    }

    func testDifferentMessageAndAccountDoNotInheritSelection() throws {
        for changeAccount in [false, true] {
            let context = BlockContext(), row = LayerCaptionRow(frame: .zero)
            row.bind(ChatRowItem([fixtures.caption(1, stableId: 7, text: "same text", context: context)]))
            let host = try XCTUnwrap(row.captionViews[0].layerView)
            host.body.textNodes[0].setExternalSelection(NSRange(location: 0, length: 4))
            let next = fixtures.caption(changeAccount ? 1 : 2, stableId: 7, text: "same text", context: changeAccount ? BlockContext() : context)
            row.bind(ChatRowItem([next]))
            XCTAssertFalse(next.layout.hasSelectedText)
            XCTAssertFalse(row.captionViews[0].layerView === host)
            XCTAssertNil(host.superview)
            XCTAssertTrue(host.isEventLess)
        }
    }

    func testSameLayoutRendererTransitionPreservesSelection() throws {
        let context = BlockContext(), row = LayerCaptionRow(frame: .zero)
        let caption = fixtures.caption(1, context: context)
        row.bind(ChatRowItem([caption]))
        let host = try XCTUnwrap(row.captionViews[0].layerView)
        let range = NSRange(location: 0, length: 4)
        host.body.textNodes[0].setExternalSelection(range)
        let string = try XCTUnwrap(caption.layout.blocks[0].text.attributedString as? NSMutableAttributedString)
        string.addAttribute(TextInputAttributes.formattedDate, value: "date", range: range)
        row.bind(ChatRowItem([caption]))
        XCTAssertNotNil(row.captionViews[0].nativeView)
        XCTAssertEqual(caption.layout.blocks[0].text.selectedRange.range, range)
        XCTAssertNil(host.superview)
        string.removeAttribute(TextInputAttributes.formattedDate, range: range)
        row.bind(ChatRowItem([caption]))
        XCTAssertNotNil(row.captionViews[0].nativeView)
        caption.layout.blocks[0].text.clearSelect()
        row.bind(ChatRowItem([caption]))
        XCTAssertNotNil(row.captionViews[0].layerView)
    }

    func testRichCaptionsKeepNativeRenderingAndCurrentRevealCallbacks() throws {
        let context = BlockContext(), row = LayerCaptionRow(frame: .zero)
        for id in [1, 2, 3] {
            let rich = fixtures.caption(id, stableId: 9, text: "one\ntwo\nthree\nfour\nfive\nsix", context: context, quoted: true)
            (rich.layout.blocks[0].text.attributedString as! NSMutableAttributedString).addAttribute(TextInputAttributes.formattedDate, value: "date", range: NSRange(location: 0, length: 3))
            let item = ChatRowItem([fixtures.caption(10, context: context), rich])
            row.bind(item)
            XCTAssertNotNil(row.captionViews[0].layerView)
            let native = try XCTUnwrap(row.captionViews[1].nativeView)
            native.revealBlockAtIndex?(2)
            XCTAssertEqual(item.revealed.map { $0.1 }, [id])
            XCTAssertEqual(row.textSelectionSources.count, 2)
        }
    }

    func testNativeAnimationDefersMigrationAndAnimatedBindingDefersGeometry() throws {
        let context = BlockContext(), row = LayerCaptionRow(frame: .zero)
        row.bind(ChatRowItem([nativeCaption(1, text: "same", context: context)]))
        let native = try XCTUnwrap(row.captionViews[0].nativeView)
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.duration = 100
        native.layer?.add(animation, forKey: "test")
        let plain = fixtures.caption(1, text: "same", context: context)
        row.bind(ChatRowItem([plain]))
        XCTAssertTrue(row.captionViews[0].nativeView === native)
        native.layer?.removeAllAnimations()
        row.bind(ChatRowItem([plain]))
        let host = try XCTUnwrap(row.captionViews[0].layerView), frame = host.frame
        let next = fixtures.caption(1, text: "same", context: context, offset: NSPoint(x: 10, y: 80))
        row.bind(ChatRowItem([next]), animated: true)
        XCTAssertEqual(host.frame, frame)
        row.finishLayout()
        XCTAssertEqual(host.frame.origin, next.offset)
    }

    func testLatestReentrantCaptionBindingWinsWithoutOrphanedViews() throws {
        let context = BlockContext(), row = LayerCaptionRow(frame: .zero)
        row.bind(ChatRowItem([fixtures.caption(1, context: context), fixtures.caption(2, context: context)]))
        let node = try XCTUnwrap(row.captionViews[0].layerView?.body.textNodes.first)
        node.setExternalSelection(NSRange(location: 0, length: 4))
        let newest = ChatRowItem([fixtures.caption(5, context: context), fixtures.caption(6, context: context)])
        var callbacks = 0
        node.onSelectionChanged = { _ in
            node.onSelectionChanged = nil
            callbacks += 1
            row.bind(ChatRowItem([self.fixtures.caption(4, context: context)]))
            row.bind(newest)
        }
        row.bind(ChatRowItem([nativeCaption(3, context: context)]))
        XCTAssertEqual(callbacks, 1)
        XCTAssertTrue(row.item === newest)
        XCTAssertEqual(row.ids, [5, 6])
        XCTAssertEqual(row.rowView.subviews.count, 3)
        XCTAssertTrue(row.captionViews.allSatisfy { $0.layerView != nil && !$0.view.isEventLess })
    }

    func testPendingMenuDisposalKeepsNewestCaptionSet() throws {
        let context = BlockContext(), row = LayerCaptionRow(frame: .zero)
        let caption = fixtures.caption(1, context: context)
        let newest = ChatRowItem([fixtures.caption(3, context: context)])
        let layout = caption.layout.blocks[0].text
        layout.alwaysStaticItems = false
        var cancelled = 0
        layout.interactions.topWindow = { Signal { _ in ActionDisposable { cancelled += 1; row.bind(newest) } } }
        row.bind(ChatRowItem([caption]))
        let node = try XCTUnwrap(row.captionViews[0].layerView?.body.textNodes.first)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 5, y: 5), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
        XCTAssertTrue(node.requestMenu(at: NSPoint(x: 5, y: 5), event: event))
        row.bind(ChatRowItem([]))
        XCTAssertEqual(cancelled, 1)
        XCTAssertEqual(row.ids, [3])
        XCTAssertTrue(row.item === newest)
        XCTAssertEqual(row.rowView.subviews.count, 2)
    }

    func testCaptionBodyWebpageAndFactCheckSelectionOrder() throws {
        let context = BlockContext(), captions = LayerCaptionRow(frame: .zero)
        captions.bind(ChatRowItem([fixtures.caption(1, context: context, blocks: 2), fixtures.caption(2, context: context, quoted: true)]))
        let fact = CaptionFactCheck()
        let factLayout = TextViewLayout(NSAttributedString(string: "fact"))
        factLayout.measure(width: 100)
        fact.textView.textView.update(factLayout)
        captions.factCheckView = fact
        XCTAssertEqual(captions.textSelectionSources.count, 4)
        XCTAssertTrue(captions.textSelectionSources[3].textLayout === factLayout)
        for nativeBody in [false, true] {
            let row = LayerChatTextRow(frame: .zero)
            row.captionViews = captions.captionViews
            row.nativeCaptions = [fact.textView.textView]
            let body = ChatTextReuseTests().item(4, quoted: nativeBody, context: context, text: nativeBody ? "one\ntwo\nthree\nfour\nfive\nsix" : nil, collapsable: nativeBody)
            if nativeBody {
                (body.textLayout.blocks[0].text.attributedString as! NSMutableAttributedString).addAttribute(TextInputAttributes.formattedDate, value: "date", range: NSRange(location: 0, length: 3))
            }
            row.bind(body)
            let webpage = ChatTextWebpage(), text = TextView()
            let layout = TextViewLayout(NSAttributedString(string: "webpage"))
            layout.measure(width: 100)
            text.update(layout)
            webpage.selectableTextViews = [text]
            row.webpageContent = webpage
            let sources = row.textSelectionSources
            XCTAssertEqual(sources.count, 6)
            XCTAssertTrue(sources[0].textLayout === captions.captionViews[0].layerView?.body.textNodes[0].textLayout)
            XCTAssertTrue(sources[3].textLayout === factLayout)
            XCTAssertTrue(sources[5].textLayout === layout)
        }
    }

    func testRemovedCaptionsReleaseHostsAndContexts() {
        weak var weakHost: View?
        weak var weakContext: BlockContext?
        let row = LayerCaptionRow(frame: .zero)
        autoreleasepool {
            let context = BlockContext()
            weakContext = context
            row.bind(ChatRowItem([fixtures.caption(1, context: context)]))
            weakHost = row.contentViews[0]
            row.bind(ChatRowItem([]))
        }
        XCTAssertNil(weakHost)
        XCTAssertNil(weakContext)
        XCTAssertEqual(row.rowView.subviews.count, 1)
    }

    func testPixelsAndClickGeometryMatchNativeForMixedCaptions() throws {
        var comparisons = 0
        for scale: CGFloat in [1, 2, 3] {
            for mixed in [false, true] {
                for step in 0..<3 {
                    let context = BlockContext(), native = ReusedCaptionRow(frame: NSRect(x: 0, y: 0, width: 320, height: 440))
                    let current = LayerCaptionRow(frame: native.frame)
                    for row in [native as CaptionRowEnvironment, current] {
                        let values = (0..<3).map { i in fixtures.caption(step * 10 + i + 1, text: "Caption \(step) مرحبا 👩🏽‍💻 中文\nText \(i)", context: context, blocks: 2, quoted: mixed && i == 1, offset: NSPoint(x: 7, y: 130 * i + 5)) }
                        row.bind(ChatRowItem(step == 1 ? values.reversed() : values))
                        row.finishLayout()
                    }
                    let expected = ViewSnapshot.render(native, scale: scale), actual = ViewSnapshot.render(current, scale: scale)
                    XCTAssertEqual(actual.differingPixels(from: expected, tolerance: 0), 0, "scale=\(scale) mixed=\(mixed) step=\(step)")
                    comparisons += 1
                    for (reference, candidate) in zip(native.views, current.captionViews) {
                        for y in stride(from: CGFloat(-4), through: reference.frame.height + 4, by: 4) {
                            for x in stride(from: CGFloat(-4), through: 260, by: 4) {
                                let point = NSPoint(x: x, y: y)
                                XCTAssertEqual(candidate.clickInContent(point: point), reference.clickInContent(point: point))
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(comparisons, 18)
    }
    func testCrossRowCopyMatchesNativeWithMixedCaptions() throws {
        let context = BlockContext()
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        func makeRow(_ index: Int, layered: Bool) -> ChatTextRow {
            let row: ChatTextRow = layered ? LayerChatTextRow(frame: .zero) : PreviousNativeChatTextRow(frame: .zero)
            let item = ChatTextReuseTests().item(index, context: context, text: "body \(index)")
            item.textOrigin = NSPoint(x: 8, y: 48)
            row.bind(item)
            row.header = "Author \(index)"
            let captions: CaptionRowEnvironment = layered ? LayerCaptionRow(frame: .zero) : ReusedCaptionRow(frame: .zero)
            captions.bind(ChatRowItem([fixtures.caption(10, text: "caption \(index)", context: context, offset: NSPoint(x: 8, y: 0)), fixtures.caption(11, text: "quote \(index)", context: context, quoted: true, offset: NSPoint(x: 8, y: 22))]))
            if let captions = captions as? LayerCaptionRow { row.captionViews = captions.captionViews }
            else { row.nativeCaptions = captions.views.flatMap { $0.textViews } }
            for view in captions.contentViews { row.addSubview(view) }
            let webpage = ChatTextWebpage(), text = TextView()
            let layout = TextViewLayout(NSAttributedString(string: "webpage \(index)", attributes: [.font: NSFont.systemFont(ofSize: 14)]))
            layout.measure(width: 260)
            text.update(layout)
            text.setFrameOrigin(NSPoint(x: 8, y: 74))
            row.addSubview(text)
            webpage.selectableTextViews = [text]
            row.webpageContent = webpage
            return row
        }
        for reversedTable in [false, true] {
            let reference = ReferenceEmbeddedSelectionLoopHarness(SelectionTable(views: (0..<3).map { makeRow($0, layered: false) }, reversed: reversedTable))
            let current = SelectionLoopHarness(SelectionTable(views: (0..<3).map { makeRow($0, layered: true) }, reversed: reversedTable))
            for (begin, end) in [(NSPoint.zero, NSPoint(x: 299, y: 299)), (NSPoint(x: 20, y: 6), NSPoint(x: 80, y: 278))] {
                for backwards in [false, true] {
                    reference.select(begin: backwards ? end : begin, end: backwards ? begin : end, window: window, reversedTable: reversedTable)
                    current.select(begin: backwards ? end : begin, end: backwards ? begin : end, window: window, reversedTable: reversedTable)
                    XCTAssertTrue(current.selectManager.selectedText.isEqual(to: reference.selectManager.selectedText), "\(current.selectManager.selectedText.string) vs \(reference.selectManager.selectedText.string)")
                }
            }
        }
    }

    func testLinkedCaptionDispatchAndPressedReuseCancellation() throws {
        let context = BlockContext(), row = LayerCaptionRow(frame: .zero)
        func linked(_ id: Int) -> FoldingViewHarness.ChatRowItem.RowCaption {
            .init(messageId: id, id: UInt32(id), layout: ChatTextReuseTests().item(id, context: context, linked: true).textLayout)
        }
        var opened: [String] = []
        let first = linked(1)
        first.layout.blocks[0].text.interactions.processURL = { opened.append($0 as! String) }
        row.bind(ChatRowItem([first]))
        let host = try XCTUnwrap(row.captionViews[0].layerView)
        XCTAssertTrue(host.handlePointer(.down, at: NSPoint(x: 2, y: 5)))
        XCTAssertTrue(host.handlePointer(.up, at: NSPoint(x: 2, y: 5)))
        XCTAssertEqual(opened, ["https://example.com/1/0"])
        XCTAssertTrue(host.handlePointer(.down, at: NSPoint(x: 2, y: 5)))
        row.bind(ChatRowItem([linked(2)]))
        XCTAssertFalse(host.hasActiveInput)
        XCTAssertTrue(host.isEventLess)
        _ = host.handlePointer(.up, at: NSPoint(x: 2, y: 5))
        XCTAssertEqual(opened.count, 1)
        XCTAssertNil(host.superview)
    }

    func testCaptionSearchHighlightMatchesNativeAndClearsOnReuse() throws {
        let context = BlockContext()
        for scale: CGFloat in [1, 2, 3] {
            let native = ReusedCaptionRow(frame: NSRect(x: 0, y: 0, width: 300, height: 150)), current = LayerCaptionRow(frame: NSRect(x: 0, y: 0, width: 300, height: 150))
            for row in [native as CaptionRowEnvironment, current] {
                row.bind(ChatRowItem([fixtures.caption(1, text: "word first\n", context: context, blocks: 2, offset: NSPoint(x: 8, y: 8))]))
            }
            let range = NSRange(location: 11, length: 4)
            native.views[0].highlight(text: "word", color: .yellow, range: range)
            current.captionViews[0].highlight(text: "word", color: .yellow, range: range)
            XCTAssertEqual(ViewSnapshot.render(native, scale: scale).differingPixels(from: ViewSnapshot.render(current, scale: scale), tolerance: 0), 0)
            let host = try XCTUnwrap(current.captionViews[0].layerView)
            current.bind(ChatRowItem([fixtures.caption(2, text: "word first\n", context: context, blocks: 2, offset: NSPoint(x: 8, y: 8))]))
            XCTAssertTrue(current.captionViews[0].layerView === host)
            XCTAssertTrue(host.body.textNodes.allSatisfy { ($0.layer.sublayers?.count ?? 0) == 1 })
        }
    }

    func testNativeCleanupCallbackCannotOverwriteANewerLayerBinding() throws {
        let context = BlockContext(), row = LayerCaptionRow(frame: .zero)
        let old = nativeCaption(1, context: context)
        row.bind(ChatRowItem([old]))
        let newest = fixtures.caption(3, context: context)
        var rebound = false
        old.layout.blocks[0].text.interactions.hoverOnLink = { _ in
            if !rebound {
                rebound = true
                row.bind(ChatRowItem([newest]))
            }
        }
        row.bind(ChatRowItem([nativeCaption(2, context: context)]))
        XCTAssertTrue(rebound)
        XCTAssertEqual(row.ids, [3])
        XCTAssertTrue(row.views.isEmpty)
        XCTAssertTrue(row.captionViews[0].layerView?.body.textNodes.first?.textLayout === newest.layout.blocks[0].text)
        XCTAssertEqual(row.rowView.subviews.count, 2)
    }

    func testSpecializedRowsPreserveNativeSelectionOverride() throws {
        let context = BlockContext()
        let rows: [LayerCaptionRow] = [ChatInvoiceItemCaptionSelection(frame: .zero), ChatPollItemCaptionSelection(frame: .zero), ChatTodoItemCaptionSelection(frame: .zero)]
        for row in rows {
            row.bind(ChatRowItem([fixtures.caption(1, context: context)]))
            XCTAssertNotNil(row.captionViews[0].layerView)
            XCTAssertEqual(row.textSelectionSources.count, 1)
            if case let .view(view) = row.textSelectionSources[0] {
                XCTAssertTrue(view === row.selectableTextViews[0])
            } else {
                XCTFail("Specialized row selection must keep its native override")
            }
        }
    }
}
