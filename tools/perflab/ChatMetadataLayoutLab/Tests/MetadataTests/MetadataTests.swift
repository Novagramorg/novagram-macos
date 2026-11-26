import Cocoa
import XCTest
@testable import TGUIKit

final class MetadataTests: XCTestCase {
    override func setUp() {
        TGUIKitTestBootstrap.install()
        theme = MetadataPresentation()
        metadataStrings = MetadataStrings()
    }

    private func count(_ text: String) -> TextViewLayout {
        TextViewLayout(.initialize(string: text, color: .black, font: .normal(11)), maximumNumberOfLines: 1)
    }

    private final class EmbeddedMarker: NSObject {}
    private let embeddedMarker = EmbeddedMarker()

    private func badge() -> TextViewLayout {
        let text = NSMutableAttributedString(string: "🤡", attributes: [TextInputAttributes.embedded: embeddedMarker])
        text.append(.initialize(string: "Only visible to you and @example_receiver", color: theme.colors.greenUI, font: .medium(12)))
        let layout = TextViewLayout(text, maximumNumberOfLines: 1, truncationType: .end, alignment: .left)
        layout.mayItems = false
        layout.measure(width: .greatestFiniteMagnitude)
        layout.generateAutoBlock(backgroundColor: theme.colors.greenUI.withAlphaComponent(0.15), minusHeight: 0, yInset: 1)
        return layout
    }

    func testRepeatedBubbleCountsReuseMeasuredLines() throws {
        let item = CandidateMetadata()
        item.channelViews = count("12.4K")
        item.replyCount = count("245")
        item.measureCounters(600)
        let viewsLine = try XCTUnwrap(item.channelViews?.lines.first?.line)
        let repliesLine = try XCTUnwrap(item.replyCount?.lines.first?.line)
        for width: CGFloat in [600, 800, 450, 600] {
            item.measureCounters(width)
            XCTAssertTrue(item.channelViews?.lines.first?.line === viewsLine)
            XCTAssertTrue(item.replyCount?.lines.first?.line === repliesLine)
        }
    }

    func testCountsMatchOriginalAcrossModesAndWidths() throws {
        let item = CandidateMetadata(), original = ReferenceMetadata()
        for text in ["1", "12.4K", "١٢٣٤", "999999999999999999999999", ""] {
            item.channelViews = count(text); original.channelViews = count(text)
            item.replyCount = count(text); original.replyCount = count(text)
            for bubble in [true, false, true] {
                item.hasBubble = bubble; original.hasBubble = bubble
                for width: CGFloat in [300, 450, 700, 450, 300] {
                    item.measureCounters(width); original.measureCounters(width)
                    try assertLayout(item.channelViews!, original.channelViews!, allowEmpty: text.isEmpty)
                    try assertLayout(item.replyCount!, original.replyCount!, allowEmpty: text.isEmpty)
                }
            }
        }
    }

    func testCountsRecoverFromDroppedSizeAndNewLayout() throws {
        let item = CandidateMetadata()
        item.channelViews = count("345")
        item.measureCounters(600)
        let expected = try XCTUnwrap(item.channelViews?.layoutSize)
        item.channelViews?.dropLayoutSize()
        item.measureCounters(600)
        XCTAssertEqual(item.channelViews?.layoutSize, expected)
        item.channelViews = count("99999")
        item.measureCounters(600)
        XCTAssertGreaterThan(item.channelViews?.layoutSize.width ?? 0, 0)
    }

    func testUnchangedForwardHeaderKeepsLayout() throws {
        let item = CandidateMetadata()
        item.measureHeader()
        let first = try XCTUnwrap(item.forwardHeader)
        for _ in 0..<5 {
            item.measureHeader()
            XCTAssertTrue(item.forwardHeader === first)
        }
    }

    func testForwardHeaderChangesAndVisibilityMatchOriginal() throws {
        let item = CandidateMetadata(), original = ReferenceMetadata()
        for forward in [MetadataForwardType.FullHeader, .ShortHeader, .none] {
            for entryType in [MetadataRenderType.list, .bubble] {
                for renderType in [MetadataRenderType.list, .bubble] {
                    for psa in [nil, "health", "security"] as [String?] {
                        for fixture in [item as MetadataEnvironment, original] {
                            fixture.forwardType = forward
                            fixture.entry.renderType = entryType
                            fixture.renderType = renderType
                            fixture.message = MetadataMessage(forwardInfo: MetadataForwardInfo(psaType: psa))
                        }
                        item.measureHeader(); original.measureHeader()
                        XCTAssertEqual(item.forwardHeader == nil, original.forwardHeader == nil)
                        if let current = item.forwardHeader, let reference = original.forwardHeader {
                            try assertLayout(current, reference)
                        }
                    }
                }
            }
        }
    }

    func testBadgeExpandsAfterNarrowing() throws {
        let item = CandidateMetadata()
        item.guestChatBadge = badge()
        let originalWidth = item.guestChatBadge!.layoutSize.width
        item.measureBadge(90)
        XCTAssertLessThan(item.guestChatBadge!.layoutSize.width, originalWidth)
        item.measureBadge(600)
        try assertLayout(item.guestChatBadge!, badge())
    }

    func testBadgeRepeatedSizingDoesNotAccumulatePadding() throws {
        let item = CandidateMetadata()
        item.guestChatBadge = badge()
        item.measureBadge(100)
        let size = item.guestChatBadge!.layoutSize
        let frames = item.guestChatBadge!.lines.map { $0.frame }
        for _ in 0..<20 { item.measureBadge(100) }
        XCTAssertEqual(item.guestChatBadge!.layoutSize, size)
        XCTAssertEqual(item.guestChatBadge!.lines.map { $0.frame }, frames)
    }

    func testListCountsReuseOnlyMatchingWidths() throws {
        let item = CandidateMetadata(), original = ReferenceMetadata()
        for fixture in [item as MetadataEnvironment, original] {
            fixture.hasBubble = false
            fixture.channelViews = count("999999999999999999999999999999999999999999999")
        }
        item.measureCounters(450)
        let initial = try XCTUnwrap(item.channelViews?.lines.first?.line)
        item.measureCounters(450)
        XCTAssertTrue(item.channelViews?.lines.first?.line === initial)
        for width: CGFloat in [800, 300, 450, 800] {
            item.measureCounters(width); original.measureCounters(width)
            try assertLayout(item.channelViews!, original.channelViews!)
        }
    }

    func testForwardHeaderInvalidationAndRelease() throws {
        let item = CandidateMetadata(), original = ReferenceMetadata()
        item.measureHeader()
        weak var first = item.forwardHeader
        let size = item.forwardHeader!.layoutSize
        item.forwardHeader?.dropLayoutSize()
        item.measureHeader()
        XCTAssertEqual(item.forwardHeader?.layoutSize, size)
        XCTAssertTrue(item.forwardHeader === first)
        for text in ["Forwarded message", "Weitergeleitete Nachricht", "転送されたメッセージ", "رسالة مُعاد توجيهها"] {
            metadataStrings.messagesForwardHeader = text
            for color in [NSColor.red, .blue] {
                for fixture in [item as MetadataEnvironment, original] {
                    fixture.hasBubble = false
                    fixture.presentation.colors.grayText = color
                }
                item.measureHeader(); original.measureHeader()
                try assertLayout(item.forwardHeader!, original.forwardHeader!)
            }
        }
        XCTAssertNil(first)
        weak var final = item.forwardHeader
        item.forwardType = .none
        item.measureHeader()
        XCTAssertNil(item.forwardHeader)
        XCTAssertNil(final)
        item.forwardType = .ShortHeader
        item.measureHeader()
        XCTAssertNotNil(item.forwardHeader)
    }

    func testBadgeMatchesFreshLayoutAcrossResizeSequence() throws {
        let item = CandidateMetadata()
        item.guestChatBadge = badge()
        let naturalWidth = item.guestChatBadge!.layoutSize.width
        for width: CGFloat in [90, 150, 600, 200, 100, 100, 601, naturalWidth - 1, naturalWidth, naturalWidth + 1, 600] {
            let expected = badge()
            if expected.layoutSize.width > width {
                expected.measure(width: max(1, width - 10))
                expected.generateAutoBlock(backgroundColor: theme.colors.greenUI.withAlphaComponent(0.15), minusHeight: 0, yInset: 1)
            }
            item.measureBadge(width)
            try assertLayout(item.guestChatBadge!, expected)
        }
    }

    func testBadgeTinyWidthsAndDroppedSizeRecover() throws {
        let item = CandidateMetadata()
        item.guestChatBadge = badge()
        for width: CGFloat in [10, 0, -10, 11, 40, 600] {
            item.measureBadge(width)
            XCTAssertTrue(item.guestChatBadge!.layoutSize.width.isFinite)
            XCTAssertTrue(item.guestChatBadge!.layoutSize.height.isFinite)
            XCTAssertGreaterThan(item.guestChatBadge!.constrainedWidth, 0)
        }
        item.measureBadge(100)
        let expected = item.guestChatBadge!.layoutSize
        item.guestChatBadge?.dropLayoutSize()
        item.measureBadge(100)
        XCTAssertEqual(item.guestChatBadge?.layoutSize, expected)
        item.measureBadge(600)
        try assertLayout(item.guestChatBadge!, badge())
    }

    private func blockImage(_ layout: TextViewLayout) -> CGImage? {
        (Mirror(reflecting: layout).children.first { $0.label == "blockImage" }?.value as? (CGPoint, CGImage?))?.1
    }

    func testBadgeReuseKeepsLinesAndBlockImage() throws {
        let item = CandidateMetadata()
        item.guestChatBadge = badge()
        for width: CGFloat in [600, 100] {
            item.measureBadge(width)
            let layout = item.guestChatBadge!
            let line = try XCTUnwrap(layout.lines.first?.line)
            let image = try XCTUnwrap(blockImage(layout))
            for _ in 0..<10 {
                item.measureBadge(width)
                XCTAssertTrue(layout.lines.first?.line === line)
                XCTAssertTrue(blockImage(layout) === image)
            }
        }
    }

    func testUnmeasuredMetadataAtMatchingConstraint() throws {
        let item = CandidateMetadata()
        item.channelViews = TextViewLayout(.initialize(string: "123", color: .black, font: .normal(11)), constrainedWidth: 60, maximumNumberOfLines: 1)
        item.measureCounters(600)
        XCTAssertGreaterThan(item.channelViews!.layoutSize.width, 0)
        item.forwardHeader = TextViewLayout(.initialize(string: strings().messagesForwardHeader, color: item.presentation.chat.gray, font: .normal(.text)), constrainedWidth: .greatestFiniteMagnitude, maximumNumberOfLines: 1)
        item.measureHeader()
        XCTAssertGreaterThan(item.forwardHeader!.layoutSize.width, 0)
    }

    func testMetadataBenchmark() throws {
        guard ProcessInfo.processInfo.environment["CHAT_METADATA_BENCHMARK"] != nil else { throw XCTSkip("Opt-in metadata benchmark") }
        let item = CandidateMetadata(), original = ReferenceMetadata()
        for fixture in [item as MetadataEnvironment, original] {
            fixture.channelViews = count("12.4K")
            fixture.replyCount = count("245")
            fixture.guestChatBadge = badge()
        }
        item.measureCounters(600); original.measureCounters(600)
        item.measureHeader(); original.measureHeader()
        item.measureBadge(100); original.measureBadge(100)
        var report: [String: Any] = [:]
        let cases: [(String, (Int) -> Void, (Int) -> Void)] = [
            ("bubble-counts", { _ in original.measureCounters(600) }, { _ in item.measureCounters(600) }),
            ("forward-header", { _ in original.measureHeader() }, { _ in item.measureHeader() }),
            ("stable-badge", { _ in original.measureBadge(100) }, { _ in item.measureBadge(100) }),
            ("combined", { _ in original.measureCounters(600); original.measureHeader(); original.measureBadge(100) }, { _ in item.measureCounters(600); item.measureHeader(); item.measureBadge(100) }),
            ("changing-list-counts", { index in original.hasBubble = false; original.measureCounters(index % 2 == 0 ? 400 : 800) }, { index in item.hasBubble = false; item.measureCounters(index % 2 == 0 ? 400 : 800) })
        ]
        let iterations = 10000
        func measure(_ action: (Int) -> Void) -> Double {
            let start = CFAbsoluteTimeGetCurrent()
            for index in 0..<iterations { autoreleasepool { action(index) } }
            return (CFAbsoluteTimeGetCurrent() - start) * 1000000 / Double(iterations)
        }
        for (name, before, after) in cases {
            for index in 0..<200 { before(index); after(index) }
            var old: [Double] = [], new: [Double] = []
            for batch in 0..<9 {
                if batch % 2 == 0 { old.append(measure(before)); new.append(measure(after)) }
                else { new.append(measure(after)); old.append(measure(before)) }
            }
            report[name] = ["baseline_us": old, "candidate_us": new, "baseline_median_us": old.sorted()[4], "candidate_median_us": new.sorted()[4]]
            print("METADATA \(name): \(old.sorted()[4]) -> \(new.sorted()[4]) us")
        }
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-metadata-benchmark.json"))
    }

    private func assertLayout(_ actual: TextViewLayout, _ expected: TextViewLayout, allowEmpty: Bool = false, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(actual.layoutSize, expected.layoutSize, file: file, line: line)
        XCTAssertEqual(actual.lines.map { $0.frame }, expected.lines.map { $0.frame }, file: file, line: line)
        XCTAssertEqual(actual.attributedString, expected.attributedString, file: file, line: line)
        XCTAssertEqual(actual.embeddedItems.map { $0.rect }, expected.embeddedItems.map { $0.rect }, file: file, line: line)
        for scale: CGFloat in [1, 2] {
            XCTAssertEqual(try render(actual, allowEmpty: allowEmpty, scale: scale), try render(expected, allowEmpty: allowEmpty, scale: scale), file: file, line: line)
        }
    }

    private func render(_ layout: TextViewLayout, allowEmpty: Bool, scale: CGFloat) throws -> Data {
        return try autoreleasepool {
            let view = TextView()
            view.isSelectable = false
            view.disableBackgroundDrawing = true
            view.update(layout)
            let width = 1200, height = 100
            let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.scaleBy(x: scale, y: scale)
            view.draw(view.drawingLayer, in: context)
            let data = Data(bytes: try XCTUnwrap(context.data), count: width * height * 4)
            if !allowEmpty { XCTAssertTrue(data.contains { $0 != 0 }) }
            return data
        }
    }
}
