import Cocoa
import QuartzCore
import XCTest
@testable import ChatRowGeometryHarness

final class GeometryBenchmarkTests: XCTestCase {
    func testFrameCalculationBenchmarks() throws {
        guard ProcessInfo.processInfo.environment["CHAT_GEOMETRY_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release geometry benchmark") }
        let fixture = GeometryTests()
        let items = (0..<1024).map { index -> ChatRowItem in
            let item = fixture.fixture(kind: index % 3, flags: index, seed: index)
            item.replyModel = GeometryAccessory(size: NSSize(width: 120, height: 40))
            item.topicLinkLayout = GeometryAccessory(size: NSSize(width: 100, height: 30))
            item.authorText = GeometryText(layoutSize: NSSize(width: 100, height: 18))
            item.forwardHeader = GeometryText(layoutSize: NSSize(width: 140, height: 18))
            item.forwardType = index % 2 == 0 ? .FullHeader : .ShortHeader
            item.invertMedia = index % 2 == 0
            item.isSharable = index % 3 == 0
            return item
        }
        let frame = NSRect(x: 0, y: 0, width: 500, height: 300)
        let before = LegacyChatRowView(frame: frame), after = CandidateChatRowView(frame: frame)
        var sink: CGFloat = 0
        var results: [String: [[Double]]] = [:]
        func record(_ name: String, count: Int, before: (Int) -> Void, after: (Int) -> Void) {
            var values = [[Double](), [Double]()]
            for i in 0..<2000 { before(i); after(i) }
            for batch in 0..<11 {
                for kind in batch % 2 == 0 ? [0, 1] : [1, 0] {
                    let start = CACurrentMediaTime()
                    for i in 0..<count {
                        if kind == 0 { before(i) } else { after(i) }
                    }
                    values[kind].append((CACurrentMediaTime() - start) * 1_000_000_000 / Double(count))
                }
            }
            results[name] = values
        }
        record("layout_refresh", count: 100000, before: { i in
            let item = items[i % items.count]
            before.invalidateFrameCache()
            sink += before.rightFrame(item).minX + before.bubbleFrame(item).width + before.cachedContentFrame(item).height
        }, after: { i in
            let item = items[i % items.count]
            after.invalidateFrameCache()
            sink += after.rightFrame(item).minX + after.bubbleFrame(item).width + after.cachedContentFrame(item).height
        })
        let item = items[7]
        before.invalidateFrameCache(); after.invalidateFrameCache()
        record("cached_frames", count: 100000, before: { _ in
            sink += before.rightFrame(item).minX + before.bubbleFrame(item).width + before.cachedContentFrame(item).height
        }, after: { _ in
            sink += after.rightFrame(item).minX + after.bubbleFrame(item).width + after.cachedContentFrame(item).height
        })
        let caption = ChatRowItem.RowCaption()
        record("accessory_layout", count: 100000, before: { i in
            let item = items[i % items.count]
            before.invalidateFrameCache()
            sink += before.avatarFrame(item).minY + before.captionFrame(item, caption: caption).minY
            sink += before.replyFrame(item).minX + before.topicLinkFrame(item).minX + before.namePoint(item).x
            sink += before.forwardNamePoint(item).x + before.forwardLineRect(item).height + before.forwardHeaderRect(item).width
        }, after: { i in
            let item = items[i % items.count]
            after.invalidateFrameCache()
            sink += after.avatarFrame(item).minY + after.captionFrame(item, caption: caption).minY
            sink += after.replyFrame(item).minX + after.topicLinkFrame(item).minX + after.namePoint(item).x
            sink += after.forwardNamePoint(item).x + after.forwardLineRect(item).height + after.forwardHeaderRect(item).width
        })
        XCTAssertTrue(sink.isFinite)
        XCTAssertGreaterThan(sink, 0)
        let data = try JSONSerialization.data(withJSONObject: ["unit": "nanoseconds_per_operation", "operations": ["layout_refresh": "three core frames after invalidation", "cached_frames": "three cached core frames", "accessory_layout": "eight accessory positions after invalidation"], "batches": results, "sink": sink], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/chat-row-geometry-benchmark.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
