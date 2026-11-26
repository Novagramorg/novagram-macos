import Cocoa
import XCTest
@testable import ChatRowGeometryHarness

private final class LegacyMediaRow: LegacyChatRowView {
    var calls = 0
    override func contentFrame(_ item: ChatRowItem) -> NSRect {
        calls += 1
        return super.contentFrame(item).offsetBy(dx: -11, dy: 19)
    }
}

private final class CandidateMediaRow: CandidateChatRowView {
    var calls = 0
    override func contentFrame(_ item: ChatRowItem) -> NSRect {
        calls += 1
        return super.contentFrame(item).offsetBy(dx: -11, dy: 19)
    }
}

private final class InsetCountingItem: ChatRowItem {
    var reads = 0
    override var leftInset: CGFloat {
        get { reads += 1; return super.leftInset }
        set { super.leftInset = newValue }
    }
}

final class GeometryTests: XCTestCase {
    func fixture(kind: Int, flags: Int, seed: Int = 0) -> ChatRowItem {
        let item: ChatRowItem = kind == 1 ? ChatVideoMessageItem() : kind == 2 ? ChatMessageItem() : ChatRowItem()
        item.isIncoming = flags & 1 != 0
        item.isBubbled = flags & 2 != 0
        item.hasBubble = flags & 4 != 0
        item.isStateOverlayLayout = flags & 8 != 0
        item.chatInteraction.mode.isThreadMode = flags & 16 != 0
        item.message = GeometryMessage(id: 1)
        item.chatInteraction.chatLocation.threadMsgId = 1
        item.commentsBubbleData = flags & 32 != 0 ? 1 : nil
        (item as? ChatVideoMessageItem)?.canTranscribe = flags & 64 != 0
        if let message = item as? ChatMessageItem {
            message.containsBigEmoji = flags & 128 != 0
            message.actionButtonText = flags & 256 != 0 ? "Open" : nil
            message.webpageLayout = flags & 512 != 0 ? 1 : nil
            message.actionButtonHeight = 20 + CGFloat(seed % 13) / 2
        }
        item.bubbleFrame = NSRect(x: 17.5, y: 6.25, width: 210 + CGFloat(seed % 37) / 2, height: 180 + CGFloat(seed % 19) / 4)
        item.contentOffset = NSPoint(x: 40.5, y: 32.25)
        item.contentSize = NSSize(width: 145.25 + CGFloat(seed % 11), height: 100.5)
        item.rightSize = NSSize(width: 57.25, height: 15.5)
        item.leftInset = 13.5
        item.rightInset = 12.25
        item.bubbleContentInset = 11.5
        item.additionBubbleInset = 6.25
        return item
    }

    func testAllContentAndPresentationCombinationsMatchOriginalFrameMethods() {
        var cases = 0
        for kind in 0..<3 {
            for flags in 0..<1024 {
                for width in [CGFloat(0), 220.5, 401, 720.75, 1280] {
                    let item = fixture(kind: kind, flags: flags, seed: flags)
                    let frame = NSRect(x: 31, y: 19, width: width, height: 280)
                    let before = LegacyChatRowView(frame: frame), after = CandidateChatRowView(frame: frame)
                    XCTAssertEqual(before.rightFrame(item), after.rightFrame(item), "timestamp kind \(kind), flags \(flags), width \(width)")
                    XCTAssertEqual(before.bubbleFrame(item), after.bubbleFrame(item))
                    XCTAssertEqual(before.cachedContentFrame(item), after.cachedContentFrame(item))
                    XCTAssertEqual(before.contentFrame(item), after.contentFrame(item))
                    cases += 1
                }
            }
        }
        XCTAssertEqual(cases, 15_360)
        print("GEOMETRY_PARITY \(cases) cases, \(cases * 4) frame comparisons")
    }

    func testThreadIdentityRoundingAndUnusualDimensionsMatchOriginal() {
        for message in [nil, 1, 2] as [Int?] {
            for thread in [nil, 1, 2] as [Int?] {
                for width in [CGFloat(-101.25), 0, 17.5, 101.25] {
                    let item = fixture(kind: 0, flags: 16 | 2)
                    item.message = message.map(GeometryMessage.init)
                    item.chatInteraction.chatLocation.threadMsgId = thread
                    item.bubbleFrame.size = NSSize(width: width, height: width)
                    let frame = NSRect(x: 0, y: 0, width: 401.5, height: 200)
                    let before = LegacyChatRowView(frame: frame), after = CandidateChatRowView(frame: frame)
                    XCTAssertEqual(before.bubbleFrame(item), after.bubbleFrame(item))
                    XCTAssertEqual(before.rightFrame(item), after.rightFrame(item))
                }
            }
        }
    }

    func testSubclassContentOverridesAndCacheInvalidationRemainEffective() {
        let item = fixture(kind: 1, flags: 1 | 2 | 8 | 64)
        let frame = NSRect(x: 0, y: 0, width: 500, height: 300)
        let before = LegacyMediaRow(frame: frame), after = CandidateMediaRow(frame: frame)
        XCTAssertEqual(before.rightFrame(item), after.rightFrame(item))
        XCTAssertEqual(after.calls, 1)
        for _ in 0..<10 {
            XCTAssertEqual(before.cachedContentFrame(item), after.cachedContentFrame(item))
            XCTAssertEqual(before.rightFrame(item), after.rightFrame(item))
        }
        XCTAssertEqual(after.calls, 1)
        item.contentSize.width += 60
        before.frame.size.width += 200
        after.frame.size.width += 200
        before.invalidateFrameCache()
        after.invalidateFrameCache()
        XCTAssertEqual(before.rightFrame(item), after.rightFrame(item))
        XCTAssertEqual(after.calls, 2)
        XCTAssertEqual(after.calls, before.calls)
        XCTAssertEqual(after.cachedContentFrame(item).origin.y, item.contentOffset.y + 19)
    }

    func testGeometryCanBeUsedWithoutConstructingAnyRowView() {
        let item = fixture(kind: 2, flags: 2 | 4 | 32 | 256)
        let bubble = ChatRowGeometry.bubbleFrame(.init(item: item, rowWidth: 500))
        let content = ChatRowGeometry.contentFrame(.init(item: item, bubbleFrame: bubble))
        let timestamp = ChatRowGeometry.timestampFrame(.init(item: item, rowWidth: 500, bubbleFrame: bubble, contentFrame: content))
        let original = LegacyChatRowView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        XCTAssertEqual(bubble, original.bubbleFrame(item))
        XCTAssertEqual(content, original.contentFrame(item))
        XCTAssertEqual(timestamp, original.rightFrame(item))
    }

    func testIncomingBubbleDoesNotEvaluateUnusedInsetGetter() {
        let item = InsetCountingItem()
        item.bubbleFrame = NSRect(x: 56, y: 8, width: 200, height: 100)
        item.isIncoming = true
        XCTAssertEqual(ChatRowGeometry.bubbleFrame(.init(item: item, rowWidth: 500)), item.bubbleFrame)
        XCTAssertEqual(item.reads, 0)
        item.isIncoming = false
        XCTAssertEqual(ChatRowGeometry.bubbleFrame(.init(item: item, rowWidth: 500)).minX, 287)
        XCTAssertEqual(item.reads, 1)
    }
}
