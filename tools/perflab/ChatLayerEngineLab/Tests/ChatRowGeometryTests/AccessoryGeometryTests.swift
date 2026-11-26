import Cocoa
import XCTest
@testable import ChatRowGeometryHarness

private final class AccessoryContentSpy: CandidateChatRowView {
    var calls = 0
    override func contentFrame(_ item: ChatRowItem) -> NSRect {
        calls += 1
        return super.contentFrame(item)
    }
}

private final class AccessoryGetterSpy: ChatRowItem {
    var bubbleReads = 0
    var additionReads = 0
    var nameReads = 0
    var topReads = 0
    var innerReads = 0
    override var bubbleContentInset: CGFloat {
        get { bubbleReads += 1; return super.bubbleContentInset }
        set { super.bubbleContentInset = newValue }
    }
    override var additionBubbleInset: CGFloat {
        get { additionReads += 1; return super.additionBubbleInset }
        set { super.additionBubbleInset = newValue }
    }
    override var forwardNameInset: NSPoint {
        get { nameReads += 1; return super.forwardNameInset }
        set { super.forwardNameInset = newValue }
    }
    override var defaultContentTopOffset: CGFloat {
        get { topReads += 1; return super.defaultContentTopOffset }
        set { super.defaultContentTopOffset = newValue }
    }
    override var defaultContentInnerInset: CGFloat {
        get { innerReads += 1; return super.defaultContentInnerInset }
        set { super.defaultContentInnerInset = newValue }
    }
}

final class AccessoryGeometryTests: XCTestCase {
    func testUnusedComputedGeometryRemainsLazy() {
        let row = CandidateChatRowView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        let item = AccessoryGetterSpy()
        item.isBubbled = false
        _ = row.forwardNamePoint(item)
        XCTAssertEqual(item.bubbleReads, 0)
        XCTAssertEqual(item.additionReads, 0)
        for (kind, nameReads, topReads) in [(ForwardItemType.ShortHeader, 1, 1), (.FullHeader, 1, 0), (.Inside, 0, 0), (.Bottom, 0, 1)] {
            item.forwardType = kind
            item.nameReads = 0
            item.topReads = 0
            _ = row.forwardLineRect(item)
            XCTAssertEqual(item.nameReads, nameReads)
            XCTAssertEqual(item.topReads, topReads)
        }
        item.isBubbled = true
        item.nameReads = 0
        item.topReads = 0
        XCTAssertEqual(row.forwardLineRect(item), .zero)
        XCTAssertEqual(item.nameReads, 0)
        XCTAssertEqual(item.topReads, 0)
        let caption = ChatRowItem.RowCaption()
        item.invertMedia = true
        _ = row.captionFrame(item, caption: caption)
        XCTAssertEqual(item.innerReads, 0)
        item.invertMedia = false
        _ = row.captionFrame(item, caption: caption)
        XCTAssertEqual(item.innerReads, 1)
    }

    func testAccessoryFramesAndPointsMatchOriginalAcrossAllStates() {
        let fixture = GeometryTests()
        let kinds: [ForwardItemType?] = [nil, .ShortHeader, .FullHeader, .Inside, .Bottom]
        var comparisons = 0
        for flags in 0..<4096 {
            for kind in kinds {
                for width in [CGFloat(220.5), 401, 1280.25] {
                    let item = fixture.fixture(kind: flags % 3, flags: flags & 7, seed: flags)
                    item.isSharable = flags & 8 != 0
                    item.hasSource = flags & 16 != 0
                    item.commentsBubbleDataOverlay = flags & 32 != 0 ? 1 : nil
                    item.authorText = flags & 64 != 0 ? GeometryText(layoutSize: NSSize(width: 83.5, height: 18.25)) : nil
                    item.replyModel = flags & 128 != 0 ? GeometryAccessory(size: NSSize(width: 140.5, height: 34.25)) : nil
                    item.topicLinkLayout = flags & 256 != 0 ? GeometryAccessory(size: NSSize(width: 98.75, height: 27.5)) : nil
                    item.forwardHeader = flags & 512 != 0 ? GeometryText(layoutSize: NSSize(width: 144.25, height: 17.5)) : nil
                    item.invertMedia = flags & 1024 != 0
                    item.forwardType = kind
                    let frame = NSRect(x: 12, y: 5, width: width, height: 400.25)
                    let before = LegacyChatRowView(frame: frame), after = CandidateChatRowView(frame: frame)
                    if flags & 2048 != 0 {
                        let accessory = GeometryView(frame: NSRect(x: 0, y: 0, width: 87.25, height: 40))
                        before.forwardAccessory = accessory
                        after.forwardAccessory = accessory
                    }
                    let caption = ChatRowItem.RowCaption()
                    caption.offset.y = CGFloat(flags % 17) + 0.25
                    XCTAssertEqual(before.avatarFrame(item), after.avatarFrame(item))
                    XCTAssertEqual(before.captionFrame(item, caption: caption), after.captionFrame(item, caption: caption))
                    XCTAssertEqual(before.replyFrame(item), after.replyFrame(item))
                    XCTAssertEqual(before.topicLinkFrame(item), after.topicLinkFrame(item))
                    XCTAssertEqual(before.namePoint(item), after.namePoint(item))
                    XCTAssertEqual(before.forwardNamePoint(item), after.forwardNamePoint(item))
                    XCTAssertEqual(before.forwardHeaderRect(item), after.forwardHeaderRect(item))
                    XCTAssertEqual(before.forwardLineRect(item), after.forwardLineRect(item))
                    comparisons += 8
                }
            }
        }
        XCTAssertEqual(comparisons, 491_520)
        print("ACCESSORY_PARITY 61440 cases, \(comparisons) exact comparisons")
    }

    func testCaptionSizeIsReadOnceLessInBothMediaOrders() {
        let item = ChatRowItem()
        let caption = ChatRowItem.RowCaption()
        let frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        for inverted in [false, true] {
            item.invertMedia = inverted
            caption.layout.sizeReads = 0
            let old = LegacyChatRowView(frame: frame).captionFrame(item, caption: caption)
            let before = caption.layout.sizeReads
            caption.layout.sizeReads = 0
            let new = CandidateChatRowView(frame: frame).captionFrame(item, caption: caption)
            XCTAssertEqual(old, new)
            XCTAssertEqual(before, inverted ? 3 : 2)
            XCTAssertEqual(caption.layout.sizeReads, inverted ? 2 : 1)
        }
    }

    func testAbsentAccessoriesDoNotConstructContentGeometry() {
        let item = ChatRowItem()
        item.isBubbled = false
        let row = AccessoryContentSpy(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        XCTAssertEqual(row.replyFrame(item), .zero)
        XCTAssertEqual(row.topicLinkFrame(item), .zero)
        XCTAssertEqual(row.forwardHeaderRect(item), .zero)
        _ = row.forwardNamePoint(item)
        XCTAssertEqual(row.calls, 0)
        item.isBubbled = true
        item.hasBubble = false
        _ = row.forwardNamePoint(item)
        XCTAssertEqual(row.calls, 0)
        row.forwardAccessory = GeometryView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        _ = row.forwardNamePoint(item)
        XCTAssertEqual(row.calls, 1)
    }
}
