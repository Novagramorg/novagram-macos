import Cocoa
import XCTest
import TGUIKit
@testable import FoldingViewHarness

extension FoldingViewTests {
    func testSubviewOrderAndPixelsMatchAcrossGrowthShrinkAndTypeReplacement() {
        var comparisons = 0
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            for width in [CGFloat(160), 380] {
                let view = FoldingTextView(frame: .zero), old = LegacyFoldingTextView(frame: .zero)
                let extra = View(frame: NSRect(x: 0, y: 0, width: 30, height: 8))
                let oldExtra = View(frame: extra.frame)
                extra.backgroundColor = .red; oldExtra.backgroundColor = .red
                view.addSubview(extra); old.addSubview(oldExtra)
                for (step, count) in [1, 3, 12, 12, 2, 0, 4].enumerated() {
                    let a = legacy(count, quoted: step % 2 == 0), b = layout(count, quoted: step % 2 == 0)
                    a.measure(width: width); b.measure(width: width)
                    if count > 0 { a.blocks[0].text.selectedRange.range = NSRange(location: 1, length: 4); b.blocks[0].text.selectedRange.range = NSRange(location: 1, length: 4) }
                    view.addSubview(extra, positioned: .below, relativeTo: nil)
                    old.addSubview(oldExtra, positioned: .below, relativeTo: nil)
                    old.update(layout: a, animated: false); view.update(layout: b, animated: false)
                    XCTAssertEqual(view.subviews.count, count + 1)
                    XCTAssertTrue(view.subviews.last === extra)
                    XCTAssertEqual(view.textViews.count, count)
                    XCTAssertEqual(view.subviews.map { $0.frame }, old.subviews.map { $0.frame })
                    XCTAssertEqual(view.textViews.map { $0.textLayout?.selectedRange.range }, old.textViews.map { $0.textLayout?.selectedRange.range })
                    let size = NSSize(width: width + 20, height: max(20, b.size.height + 20))
                    old.setFrameSize(size); view.setFrameSize(size)
                    XCTAssertEqual(ViewSnapshot.render(view, scale: scale).differingPixels(from: ViewSnapshot.render(old, scale: scale), tolerance: 0), 0, "scale=\(scale), width=\(width), step=\(step)")
                    comparisons += 1
                }
            }
        }
        XCTAssertEqual(comparisons, 42)
        System.updateScaleFactor(2)
    }

    func testStableBlocksKeepTheirViewsAndClearRemovedBlocks() {
        let view = FoldingTextView(frame: .zero)
        let value = layout(3)
        view.update(layout: value, animated: false)
        let retained = view.textViews
        for _ in 0..<20 { view.update(layout: value, animated: false) }
        XCTAssertTrue(zip(retained, view.textViews).allSatisfy { $0 === $1 })
        view.update(layout: layout(1), animated: false)
        XCTAssertTrue(view.textViews.first === retained[0])
        XCTAssertNil(retained[1].superview)
        XCTAssertNil(retained[2].superview)
        view.update(layout: layout(0), animated: false)
        XCTAssertTrue(view.textViews.isEmpty)
        XCTAssertTrue(view.subviews.isEmpty)
    }

    func testRevealHandlersRetainIndicesAndSelectionSuppressionAcrossReuse() {
        let view = FoldingTextView(frame: .zero)
        var selected: [Int] = []
        view.revealBlockAtIndex = { selected.append($0) }
        for count in [1, 4, 2, 5] {
            view.update(layout: layout(count, quoted: true), animated: false)
            selected.removeAll()
            for text in view.textViews { text.send(event: .Down); text.send(event: .Click) }
            XCTAssertEqual(selected, Array(0..<count))
            selected.removeAll()
            view.textViews[0].selectionWasCleared = true
            view.textViews[0].send(event: .Down); view.textViews[0].send(event: .Click)
            XCTAssertTrue(selected.isEmpty)
            view.textViews[0].selectionWasCleared = false
            view.textViews[0].textLayout?.selectedRange.range = NSRange(location: 0, length: 1)
            view.textViews[0].send(event: .Down); view.textViews[0].send(event: .Click)
            XCTAssertTrue(selected.isEmpty)
            view.textLayouts.forEach { $0.clearSelect() }
        }
    }

    func testStreamingHandoffReleasesOldDotsAndTransfersOwnership() throws {
        let source = FoldingTextView(frame: .zero), target = FoldingTextView(frame: .zero)
        source.update(layout: layout(1, streaming: true), animated: false)
        target.update(layout: layout(1, streaming: true), animated: false)
        let incoming = try XCTUnwrap(source.appendingAnimationView)
        let replaced = try XCTUnwrap(target.appendingAnimationView)
        target.update(layout: layout(2, streaming: true), animated: false, appendingAnimationView: incoming)
        XCTAssertNil(source.appendingAnimationView)
        XCTAssertTrue(target.appendingAnimationView === incoming)
        XCTAssertTrue(incoming.superview === target)
        XCTAssertNil(replaced.superview)
        XCTAssertEqual(target.subviews.filter { $0 is LottiePlayerView }.count, 1)
        source.update(layout: layout(1), animated: false)
        XCTAssertTrue(incoming.superview === target)
        target.update(layout: layout(1), animated: false)
        XCTAssertNil(incoming.superview)
        XCTAssertNil(target.appendingAnimationView)
    }

    func testExplicitDotsArgumentIsRemovedWhenIncomingContentIsNotStreaming() throws {
        let source = FoldingTextView(frame: .zero), target = FoldingTextView(frame: .zero)
        source.update(layout: layout(1, streaming: true), animated: false)
        let incoming = try XCTUnwrap(source.appendingAnimationView)
        target.update(layout: layout(1), animated: false, appendingAnimationView: incoming)
        XCTAssertNil(target.appendingAnimationView)
        XCTAssertNil(source.appendingAnimationView)
        XCTAssertNil(incoming.superview)
        source.update(layout: layout(1, streaming: true), animated: false)
        XCTAssertTrue(source.appendingAnimationView?.superview === source)
    }
}

extension FoldingViewTests {
    func testNativeFoldingToggleAndSelectionSurviveRepeatedBinding() {
        let string = NSAttributedString(string: "one\ntwo\nthree\nfour\nfive\nsix", attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black, TextInputAttributes.quote: TextViewBlockQuoteData(id: 20, colors: .init(main: .blue), collapsable: true)])
        let layout = FoldingTextLayout.make(string, context: BlockContext(), revealed: [], takeLayout: { TextViewLayout($0) })
        layout.measure(width: 240)
        XCTAssertTrue(layout.blocks[0].canReveal)
        let view = FoldingTextView(frame: .zero)
        view.update(layout: layout, animated: false)
        let text = view.textViews[0]
        let collapsedHeight = view.subviews[0].frame.height
        text.send(event: .Down); text.send(event: .Click)
        XCTAssertTrue(layout.revealed.contains(0))
        XCTAssertGreaterThan(view.subviews[0].frame.height, collapsedHeight)
        for _ in 0..<5 { view.update(layout: layout, animated: false) }
        XCTAssertTrue(view.textViews[0] === text)
        text.textLayout?.selectedRange.range = NSRange(location: 0, length: 3)
        view.update(layout: layout, animated: false)
        XCTAssertEqual(text.textLayout?.selectedRange.range, NSRange(location: 0, length: 3))
        text.send(event: .Down); text.send(event: .Click)
        XCTAssertTrue(layout.revealed.contains(0))
        text.textLayout?.clearSelect()
        text.send(event: .Down); text.send(event: .Click)
        XCTAssertFalse(layout.revealed.contains(0))
        XCTAssertEqual(view.subviews[0].frame.height, collapsedHeight)
    }

    func testStoppingStreamingReleasesTheLoadingView() {
        let view = FoldingTextView(frame: .zero)
        weak var dots: LottiePlayerView?
        autoreleasepool {
            view.update(layout: layout(1, streaming: true), animated: false)
            dots = view.appendingAnimationView
            XCTAssertNotNil(dots)
            view.update(layout: layout(1), animated: false)
        }
        XCTAssertNil(dots)
    }
}

extension FoldingViewTests {
    func testRetainedHandlersResetSuppressionAndUseTheLatestCallback() {
        let view = FoldingTextView(frame: .zero)
        let value = layout(2)
        view.update(layout: value, animated: false)
        let text = view.textViews[1]
        var first = 0, second: [Int] = []
        view.revealBlockAtIndex = { _ in first += 1 }
        text.selectionWasCleared = true
        text.send(event: .Down)
        view.update(layout: value, animated: false)
        view.revealBlockAtIndex = { second.append($0) }
        text.send(event: .Click)
        XCTAssertEqual(first, 0)
        XCTAssertEqual(second, [1])
        view.revealBlockAtIndex = { index in
            second.append(index)
            view.update(layout: self.layout(1, quoted: true), animated: false)
        }
        text.send(event: .Down); text.send(event: .Click)
        XCTAssertEqual(second, [1, 1])
        XCTAssertEqual(view.textViews.count, 1)
        view.revealBlockAtIndex = nil
    }

    func testRemovedBlockActionsAreInertAndHandlersDoNotRetainTheirOwner() {
        for quoted in [false, true] {
            let old = LegacyFoldingTextView(frame: .zero)
            old.update(layout: legacy(3, quoted: quoted), animated: false)
            let retired = old.textViews[2]
            var oldCalls = 0
            old.revealBlockAtIndex = { _ in oldCalls += 1 }
            old.update(layout: legacy(0), animated: false)
            retired.send(event: .Down); retired.send(event: .Click)
            XCTAssertEqual(oldCalls, 1)
            weak var owner: FoldingTextView?
            var retained: TextView?
            var calls = 0
            autoreleasepool {
                var view: FoldingTextView? = FoldingTextView(frame: .zero)
                owner = view
                view!.update(layout: layout(3, quoted: quoted), animated: false)
                retained = view!.textViews[2]
                view!.revealBlockAtIndex = { _ in calls += 1 }
                view!.update(layout: layout(0), animated: false)
                retained!.send(event: .Down); retained!.send(event: .Click)
                XCTAssertEqual(calls, 0)
                view = nil
            }
            XCTAssertNil(owner)
            retained!.send(event: .Down); retained!.send(event: .Click)
            XCTAssertEqual(calls, 0)
            retained = nil
        }
    }
}
