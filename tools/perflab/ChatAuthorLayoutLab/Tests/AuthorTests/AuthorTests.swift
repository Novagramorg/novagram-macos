import Cocoa
import XCTest
@testable import TGUIKit

final class AuthorTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    private func layout(_ text: String, forward: Bool = false, lines: Int32 = 1) -> TextViewLayout {
        let value = NSMutableAttributedString(attributedString: .initialize(string: text, color: .blue, font: .medium(13)))
        if !text.isEmpty { value.addAttribute(.link, value: "peer:123", range: NSRange(location: 0, length: value.length)) }
        let result = TextViewLayout(value, maximumNumberOfLines: lines, alwaysStaticItems: forward)
        if !forward { result.mayItems = false }
        return result
    }

    func testRepeatedAuthorRetainsCoreTextLine() throws {
        let item = CandidateAuthor()
        item.authorText = layout("Alice via @example_bot")
        item.measureAuthor(250, cachedRightSize: .zero)
        let line = try XCTUnwrap(item.authorText?.lines.first?.line)
        for _ in 0..<5 {
            item.measureAuthor(250, cachedRightSize: .zero)
            XCTAssertTrue(item.authorText?.lines.first?.line === line)
        }
    }

    func testRepeatedForwardRetainsCoreTextLineAtWidthCap() throws {
        let item = CandidateAuthor()
        item.forwardNameLayout = layout("Forwarded message from Alice", forward: true, lines: 2)
        item.measureForward(600, widthForContent: 250)
        let line = try XCTUnwrap(item.forwardNameLayout?.lines.first?.line)
        for width: CGFloat in [300, 400, 500, 250] {
            item.measureForward(600, widthForContent: width)
            XCTAssertTrue(item.forwardNameLayout?.lines.first?.line === line)
        }
    }

    func testAuthorMatchesOriginalAcrossBadgesModesAndWidths() throws {
        let item = CandidateAuthor(), original = ReferenceAuthor()
        for text in ["Alice", "Alice via @example_bot with a long name", "رسالة من أحمد", "日本語の長い名前", ""] {
            for fixture in [item as AuthorEnvironment, original] { fixture.authorText = layout(text) }
            for bubble in [true, false] {
                for badges in [false, true] {
                    for fixture in [item as AuthorEnvironment, original] {
                        fixture.isBubbled = bubble
                        fixture.adminBadge = badges ? layout("admin") : nil
                        fixture.boostBadge = badges ? layout("3") : nil
                        fixture.adminBadge?.measure(width: 100)
                        fixture.boostBadge?.measure(width: 100)
                    }
                    for width: CGFloat in [90, 300, 90, 300] {
                        let right = NSSize(width: 40, height: 15)
                        item.measureAuthor(width, cachedRightSize: right)
                        original.measureAuthor(width, cachedRightSize: right)
                        try compare(item.authorText!, original.authorText!, allowEmpty: text.isEmpty)
                    }
                }
            }
        }
    }

    func testForwardMatchesOriginalAcrossAccessoryModes() throws {
        let item = CandidateAuthor(), original = ReferenceAuthor()
        for text in ["Forwarded from Alice", "Forwarded from a very long name with many words and emoji 🦆", "إعادة توجيه رسالة من أحمد"] {
            for lines: Int32 in [1, 2] {
                for fixture in [item as AuthorEnvironment, original] { fixture.forwardNameLayout = layout(text, forward: true, lines: lines) }
                for bubble in [true, false] {
                    for hasBubble in [true, false] {
                        for vertical in [true, false] {
                            for fixture in [item as AuthorEnvironment, original] {
                                fixture.isBubbled = bubble
                                fixture.hasBubble = hasBubble
                                fixture.monoforumState = vertical ? .vertical : .horizontal
                            }
                            for width: CGFloat in [300, 600, 300] {
                                item.measureForward(width, widthForContent: width - 200)
                                original.measureForward(width, widthForContent: width - 200)
                                try compare(item.forwardNameLayout!, original.forwardNameLayout!)
                            }
                        }
                    }
                }
            }
        }
    }

    func testSideReplyMaintainsSizingCallsAndOffset() throws {
        let item = CandidateAuthor(), original = ReferenceAuthor()
        for fixture in [item as AuthorEnvironment, original] {
            fixture.authorText = layout("Alice via @example_bot")
            fixture.replyModel = ReplyFixture()
            fixture.canFillAuthorName = false
            fixture.adminBadge = layout("admin")
            fixture.adminBadge?.measure(width: 100)
        }
        for width: CGFloat in [200, 200, 90, 300] {
            item.replyModel!.size.width = width
            original.replyModel!.size.width = width
            item.measureAuthor(600, cachedRightSize: .zero)
            original.measureAuthor(600, cachedRightSize: .zero)
            try compare(item.authorText!, original.authorText!)
            XCTAssertEqual(item.replyModel?.topOffset, original.replyModel?.topOffset)
            XCTAssertEqual(item.replyModel!.calls.map { $0.0 }, original.replyModel!.calls.map { $0.0 })
            XCTAssertEqual(item.replyModel!.calls.map { $0.1 }, original.replyModel!.calls.map { $0.1 })
            XCTAssertEqual(item.replyModel!.calls.map { $0.2 }, original.replyModel!.calls.map { $0.2 })
        }
        XCTAssertEqual(item.replyModel!.calls.count, 4)
    }

    func testDroppedAndReplacedLayoutsRemeasure() throws {
        let item = CandidateAuthor(), original = ReferenceAuthor()
        for fixture in [item as AuthorEnvironment, original] {
            fixture.authorText = layout("Alice")
            fixture.forwardNameLayout = layout("Forwarded from Alice", forward: true, lines: 2)
        }
        for pass in 0..<3 {
            if pass == 1 {
                item.authorText?.dropLayoutSize(); item.forwardNameLayout?.dropLayoutSize()
            } else if pass == 2 {
                for fixture in [item as AuthorEnvironment, original] {
                    fixture.authorText = layout("Different author")
                    fixture.forwardNameLayout = layout("Different forwarded message", forward: true, lines: 2)
                }
            }
            item.measureAuthor(100, cachedRightSize: .zero); original.measureAuthor(100, cachedRightSize: .zero)
            item.measureForward(600, widthForContent: 100); original.measureForward(600, widthForContent: 100)
            try compare(item.authorText!, original.authorText!)
            try compare(item.forwardNameLayout!, original.forwardNameLayout!)
        }
    }

    func testZeroAndNegativeConstraintsKeepOriginalSemantics() throws {
        let item = CandidateAuthor(), original = ReferenceAuthor()
        for fixture in [item as AuthorEnvironment, original] {
            fixture.authorText = layout("Alice")
            fixture.forwardNameLayout = layout("Forwarded from Alice", forward: true, lines: 2)
        }
        for width: CGFloat in [200, 0, -10, 1, 200] {
            item.measureAuthor(width, cachedRightSize: .zero); original.measureAuthor(width, cachedRightSize: .zero)
            item.measureForward(600, widthForContent: width); original.measureForward(600, widthForContent: width)
            try compare(item.authorText!, original.authorText!, allowEmpty: width <= 1)
            try compare(item.forwardNameLayout!, original.forwardNameLayout!, allowEmpty: width <= 1)
            XCTAssertEqual(item.authorText?.constrainedWidth, original.authorText?.constrainedWidth)
        }
    }

    private final class PeerLink: NSObject {
        var openCount = 0
    }

    func testOpaquePeerLinkAndSideReplyReuse() throws {
        let item = CandidateAuthor()
        let peer = PeerLink()
        let text = NSMutableAttributedString(attributedString: .initialize(string: "Alice via @example_bot", color: .blue, font: .medium(13)))
        text.addAttribute(.link, value: peer, range: NSRange(location: 0, length: text.length))
        item.authorText = TextViewLayout(text, maximumNumberOfLines: 1)
        item.authorText?.mayItems = false
        item.authorText?.interactions.processURL = { value in (value as? PeerLink)?.openCount += 1 }
        item.canFillAuthorName = false
        item.replyModel = ReplyFixture()
        item.measureAuthor(600, cachedRightSize: .zero)
        let line = try XCTUnwrap(item.authorText?.lines.first?.line)
        for _ in 0..<5 {
            item.measureAuthor(600, cachedRightSize: .zero)
            XCTAssertTrue(item.authorText?.lines.first?.line === line)
            let link = try XCTUnwrap(item.authorText?.link(at: NSPoint(x: 5, y: 5)))
            XCTAssertTrue(link.0 as? PeerLink === peer)
            item.authorText?.interactions.processURL(link.0)
        }
        XCTAssertEqual(peer.openCount, 5)
        XCTAssertEqual(item.replyModel?.calls.count, 6)
    }

    func testAbsentLayoutsAndReplyBranches() {
        let item = CandidateAuthor()
        item.canFillAuthorName = false
        item.replyModel = ReplyFixture()
        item.measureAuthor(200, cachedRightSize: .zero)
        item.measureForward(600, widthForContent: 200)
        XCTAssertTrue(item.replyModel!.calls.isEmpty)
        item.authorText = layout("Alice")
        item.replyModel?.isSideAccessory = false
        item.measureAuthor(200, cachedRightSize: .zero)
        XCTAssertTrue(item.replyModel!.calls.isEmpty)
        XCTAssertGreaterThan(item.authorText!.layoutSize.width, 0)
        item.replyModel?.isSideAccessory = true
        item.canFillAuthorName = true
        item.measureAuthor(200, cachedRightSize: .zero)
        XCTAssertTrue(item.replyModel!.calls.isEmpty)
    }

    func testAuthorBenchmark() throws {
        guard ProcessInfo.processInfo.environment["CHAT_AUTHOR_BENCHMARK"] != nil else { throw XCTSkip("Opt-in author benchmark") }
        let item = CandidateAuthor(), original = ReferenceAuthor()
        let peer = PeerLink()
        func make(_ text: String, forward: Bool) -> TextViewLayout {
            let result = layout(text, forward: forward, lines: forward ? 2 : 1)
            let attributed = NSMutableAttributedString(attributedString: result.attributedString)
            attributed.addAttribute(.link, value: peer, range: NSRange(location: 0, length: attributed.length))
            result.setAttributedString(attributed)
            return result
        }
        for fixture in [item as AuthorEnvironment, original] {
            fixture.authorText = make("Alice via @example_bot", forward: false)
            fixture.forwardNameLayout = make("Forwarded message from Alice with a long name", forward: true)
        }
        let iterations = 10000
        func measure(_ action: (Int) -> Void) -> Double {
            let start = CFAbsoluteTimeGetCurrent()
            for index in 0..<iterations { autoreleasepool { action(index) } }
            return (CFAbsoluteTimeGetCurrent() - start) * 1000000 / Double(iterations)
        }
        let cases: [(String, (Int) -> Void, (Int) -> Void)] = [
            ("author-repeated", { _ in original.measureAuthor(250, cachedRightSize: .zero) }, { _ in item.measureAuthor(250, cachedRightSize: .zero) }),
            ("forward-repeated", { _ in original.measureForward(600, widthForContent: 250) }, { _ in item.measureForward(600, widthForContent: 250) }),
            ("combined-repeated", { _ in original.measureAuthor(250, cachedRightSize: .zero); original.measureForward(600, widthForContent: 250) }, { _ in item.measureAuthor(250, cachedRightSize: .zero); item.measureForward(600, widthForContent: 250) }),
            ("combined-resizing", { index in let width: CGFloat = index % 2 == 0 ? 100 : 250; original.measureAuthor(width, cachedRightSize: .zero); original.measureForward(600, widthForContent: width) }, { index in let width: CGFloat = index % 2 == 0 ? 100 : 250; item.measureAuthor(width, cachedRightSize: .zero); item.measureForward(600, widthForContent: width) }),
            ("combined-new-layouts", { _ in original.authorText = make("Alice via @example_bot", forward: false); original.forwardNameLayout = make("Forwarded message from Alice with a long name", forward: true); original.measureAuthor(250, cachedRightSize: .zero); original.measureForward(600, widthForContent: 250) }, { _ in item.authorText = make("Alice via @example_bot", forward: false); item.forwardNameLayout = make("Forwarded message from Alice with a long name", forward: true); item.measureAuthor(250, cachedRightSize: .zero); item.measureForward(600, widthForContent: 250) })
        ]
        var report: [String: Any] = [:]
        for (name, before, after) in cases {
            for index in 0..<200 { before(index); after(index) }
            var old: [Double] = [], new: [Double] = []
            for batch in 0..<9 {
                if batch % 2 == 0 { old.append(measure(before)); new.append(measure(after)) }
                else { new.append(measure(after)); old.append(measure(before)) }
            }
            report[name] = ["baseline_us": old, "candidate_us": new, "baseline_median_us": old.sorted()[4], "candidate_median_us": new.sorted()[4]]
            print("AUTHOR \(name): \(old.sorted()[4]) -> \(new.sorted()[4]) us")
        }
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-author-benchmark.json"))
    }

    private func compare(_ actual: TextViewLayout, _ expected: TextViewLayout, allowEmpty: Bool = false, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(actual.layoutSize, expected.layoutSize, file: file, line: line)
        XCTAssertEqual(actual.lines.map { $0.frame }, expected.lines.map { $0.frame }, file: file, line: line)
        XCTAssertEqual(actual.lines.map { $0.range }, expected.lines.map { $0.range }, file: file, line: line)
        for y in stride(from: CGFloat(0), to: actual.layoutSize.height, by: 3) {
            for x in stride(from: CGFloat(0), to: actual.layoutSize.width, by: 7) {
                let point = NSPoint(x: x, y: y)
                let lhs = actual.link(at: point), rhs = expected.link(at: point)
                XCTAssertEqual(lhs?.0 as? String, rhs?.0 as? String, file: file, line: line)
                XCTAssertEqual(lhs?.2, rhs?.2, file: file, line: line)
                XCTAssertEqual(lhs?.3, rhs?.3, file: file, line: line)
            }
        }
        for scale: CGFloat in [1, 2] {
            XCTAssertEqual(try render(actual, scale: scale, allowEmpty: allowEmpty), try render(expected, scale: scale, allowEmpty: allowEmpty), file: file, line: line)
        }
    }

    private func render(_ layout: TextViewLayout, scale: CGFloat, allowEmpty: Bool) throws -> Data {
        try autoreleasepool {
            let view = TextView()
            view.isSelectable = false
            view.update(layout)
            let width = 800, height = 160
            let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.scaleBy(x: scale, y: scale)
            view.draw(view.drawingLayer, in: context)
            let data = Data(bytes: try XCTUnwrap(context.data), count: width * height * 4)
            if !allowEmpty { XCTAssertTrue(data.contains { $0 != 0 }) }
            return data
        }
    }
}
