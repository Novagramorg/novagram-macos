import Cocoa
import XCTest
import TGUIKit
import Darwin
@testable import BadgeLab

private final class BadgeDisplaySpy: View {
    var requests = 0
    override func setNeedsDisplay() { requests += 1; super.setNeedsDisplay() }
}

final class BadgeTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    private func field<T>(_ object: Any, _ name: String, as: T.Type = T.self) -> T? {
        Mirror(reflecting: object).children.first(where: { $0.label == name })?.value as? T
    }

    func testAroundFillChangesRequestDisplayExactlyOnce() {
        let badge = BadgeNode(NSAttributedString(string: "7"), .blue)
        let view = BadgeDisplaySpy(frame: badge.size.bounds)
        badge.view = view
        view.requests = 0
        badge.aroundFill = .red
        XCTAssertEqual(view.requests, 1)
        badge.aroundFill = .red
        XCTAssertEqual(view.requests, 1)
        badge.aroundFill = nil
        XCTAssertEqual(view.requests, 2)
        badge.aroundFill = nil
        XCTAssertEqual(view.requests, 2)
    }

    func testNormalAndArchiveItemsDeferCompactBadges() {
        for archive in [false, true] {
            let item = CandidateItem()
            if archive { item.setupArchive(10) } else { item.setupNormal(ReadState(count: 10)) }
            XCTAssertNotNil(item.badgeNode)
            XCTAssertNil(item.shortBadgeNode)
            let short = item.ctxShortBadgeNode
            XCTAssertNotNil(short)
            XCTAssertTrue(item.ctxShortBadgeNode === short)
            XCTAssertFalse(item.badgeNode === short)
        }
    }

    func testCompactAndFullBadgesShareTextLayoutOnly() throws {
        let item = CandidateItem()
        item.setupNormal(ReadState(count: 7))
        let normal = try XCTUnwrap(item.ctxBadgeNode), short = try XCTUnwrap(item.ctxShortBadgeNode)
        let first: (TextNodeLayout, TextNode) = try XCTUnwrap(field(normal, "textLayout"))
        let second: (TextNodeLayout, TextNode) = try XCTUnwrap(field(short, "textLayout"))
        XCTAssertTrue(first.0 === second.0)
        XCTAssertTrue(first.1 === second.1)
        XCTAssertFalse(normal === short)
        XCTAssertEqual(normal.size, short.size)
        normal.fillColor = .red; short.aroundFill = .green
        XCTAssertNotEqual(normal.fillColor, short.fillColor)
        XCTAssertNil(normal.aroundFill)
    }

    func testSelectedBadgesShareRegardlessOfAccessOrder() throws {
        for compactFirst in [false, true] {
            let item = CandidateItem()
            item.setupNormal(ReadState(count: 12)); item.isActiveSelected = true
            if compactFirst { _ = item.ctxShortBadgeNode } else { _ = item.ctxBadgeNode }
            let normal = try XCTUnwrap(item.ctxBadgeNode), short = try XCTUnwrap(item.ctxShortBadgeNode)
            let first: (TextNodeLayout, TextNode) = try XCTUnwrap(field(normal, "textLayout"))
            let second: (TextNodeLayout, TextNode) = try XCTUnwrap(field(short, "textLayout"))
            XCTAssertTrue(first.0 === second.0)
            XCTAssertTrue(first.1 === second.1)
            XCTAssertFalse(normal === short)
        }
    }

    func testViewDoesNotRequestCompactBadgeWhenUnused() {
        for hidden in [false, true] {
            for live in [false, true] {
                let item = GateItem()
                item.badge = BadgeNode(NSAttributedString(string: "1"), .blue)
                item.shouldHideContent = hidden; item.hasLiveItems = live
                XCTAssertEqual(candidateGate(item), hidden && !live)
                XCTAssertEqual(item.reads, hidden && !live ? 1 : 0)
            }
        }
    }
    func testConstructionAndSelectionKeepReferenceAppearance() throws {
        var comparisons = 0
        for count in [0, 1, 7, 99, 9999] {
            for archive in [false, true] {
                let current = CandidateItem(), reference = ReferenceItem()
                if archive {
                    current.setupArchive(count); reference.setupArchive(count)
                } else {
                    current.setupNormal(ReadState(count: count), isMuted: count == 7, isUnreadMarked: count == 0)
                    reference.setupNormal(ReadState(count: count), isMuted: count == 7, isUnreadMarked: count == 0)
                }
                for selected in [false, true] {
                    current.isActiveSelected = selected; reference.isActiveSelected = selected
                    for compact in [false, true] {
                        let actual = compact ? current.ctxShortBadgeNode : current.ctxBadgeNode
                        let expected = compact ? reference.ctxShortBadgeNode : reference.ctxBadgeNode
                        XCTAssertEqual(actual?.size, expected?.size)
                        XCTAssertEqual(actual?.fillColor, expected?.fillColor)
                        guard let actual, let expected else { XCTAssertNil(actual); XCTAssertNil(expected); continue }
                        actual.aroundFill = compact ? .systemGreen : nil
                        expected.aroundFill = actual.aroundFill
                        for scale in [1, 2] {
                            XCTAssertEqual(try render(actual, scale: scale), try render(expected, scale: scale))
                            comparisons += 1
                        }
                    }
                }
            }
        }
        XCTAssertEqual(comparisons, 72)
    }

    func testSharedTextSupportsIndependentPaddingAndColors() throws {
        for text in ["", "9", "100K", "🚀", "שלום", "1\n2"] {
            for size: CGFloat in [10, 13, 18] {
                let value = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.white])
                let source = BadgeNode(value, .blue)
                let shared = BadgeNode(textFrom: source, .red, aroundFill: .green, additionSize: NSSize(width: 13, height: 9))
                let reference = BadgeNode(value, .red, aroundFill: .green, additionSize: NSSize(width: 13, height: 9))
                XCTAssertEqual(shared.size, reference.size)
                for scale in [1, 2] { XCTAssertEqual(try render(shared, scale: scale), try render(reference, scale: scale)) }
                XCTAssertEqual(source.fillColor, .blue)
                XCTAssertNil(source.aroundFill)
            }
        }
    }

    func testSharedBadgesHaveIndependentViewsAndReadiness() {
        let source = BadgeNode(NSAttributedString(string: "7"), .blue)
        let copy = BadgeNode(textFrom: source, .red)
        let first = BadgeDisplaySpy(frame: source.size.bounds), second = BadgeDisplaySpy(frame: copy.size.bounds)
        source.view = first; copy.view = second
        XCTAssertFalse(source.nodeReady === copy.nodeReady)
        first.requests = 0; second.requests = 0
        source.fillColor = .green
        XCTAssertEqual(first.requests, 1)
        XCTAssertEqual(second.requests, 0)
        copy.aroundFill = .blue
        XCTAssertEqual(first.requests, 1)
        XCTAssertEqual(second.requests, 1)
        XCTAssertTrue(first.displayDelegate === source)
        XCTAssertTrue(second.displayDelegate === copy)
    }

    func testSharedLayoutDoesNotRetainSourceAndReleasesWithLastBadge() throws {
        weak var releasedSource: BadgeNode?
        weak var releasedLayout: TextNodeLayout?
        weak var releasedText: TextNode?
        var copy: BadgeNode?
        try autoreleasepool {
            let source = BadgeNode(NSAttributedString(string: "shared"), .blue)
            let pair: (TextNodeLayout, TextNode) = try XCTUnwrap(field(source, "textLayout"))
            releasedSource = source; releasedLayout = pair.0; releasedText = pair.1
            copy = BadgeNode(textFrom: source, .red)
        }
        XCTAssertNil(releasedSource)
        XCTAssertNotNil(releasedLayout); XCTAssertNotNil(releasedText)
        XCTAssertNotNil(copy)
        copy = nil
        XCTAssertNil(releasedLayout); XCTAssertNil(releasedText)
    }

    func testConcurrentCopiesOnlyReadTheMeasuredLayout() throws {
        let source = BadgeNode(NSAttributedString(string: "42"), .blue)
        let lock = NSLock()
        var copies: [BadgeNode] = []
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            let copy = BadgeNode(textFrom: source, .red)
            lock.lock(); copies.append(copy); lock.unlock()
        }
        let expected: (TextNodeLayout, TextNode) = try XCTUnwrap(field(source, "textLayout"))
        for copy in copies {
            let pair: (TextNodeLayout, TextNode) = try XCTUnwrap(field(copy, "textLayout"))
            XCTAssertTrue(pair.0 === expected.0); XCTAssertTrue(pair.1 === expected.1)
            XCTAssertNil(copy.view)
        }
        XCTAssertEqual(copies.count, 64)
    }

    func testNoBadgeStatesAndSelectionRoundTrip() {
        for show in [false, true] {
            for gram in [false, true] {
                let current = CandidateItem(), reference = ReferenceItem()
                current.setupNormal(ReadState(count: 1), mentionsCount: 1, showBadge: show, hasGramBadge: gram)
                reference.setupNormal(ReadState(count: 1), mentionsCount: 1, showBadge: show, hasGramBadge: gram)
                for selected in [false, true, false] {
                    current.isActiveSelected = selected; reference.isActiveSelected = selected
                    XCTAssertEqual(current.ctxBadgeNode?.size, reference.ctxBadgeNode?.size)
                    XCTAssertEqual(current.ctxShortBadgeNode?.size, reference.ctxShortBadgeNode?.size)
                }
            }
        }
    }

    func testUnreadAndGramConditionsPreserveReferenceResults() {
        for count: Int? in [nil, 0, 1, 2, 99] {
            for gram in [false, true] {
                for marked in [false, true] {
                    for mentions: Int? in [nil, 1, 2] {
                        let current = CandidateItem(), reference = ReferenceItem()
                        let state = count.map { ReadState(count: $0) }
                        current.setupNormal(state, isUnreadMarked: marked, mentionsCount: mentions, hasGramBadge: gram)
                        reference.setupNormal(state, isUnreadMarked: marked, mentionsCount: mentions, hasGramBadge: gram)
                        for selected in [false, true, false] {
                            current.isActiveSelected = selected; reference.isActiveSelected = selected
                            XCTAssertEqual(current.ctxBadgeNode?.size, reference.ctxBadgeNode?.size)
                            XCTAssertEqual(current.ctxShortBadgeNode?.size, reference.ctxShortBadgeNode?.size)
                            XCTAssertEqual(current.ctxBadgeNode?.fillColor, reference.ctxBadgeNode?.fillColor)
                        }
                    }
                }
            }
        }
    }

    func testSourceTextMutationDoesNotSeparateSharedAndOriginalRendering() throws {
        let value = NSMutableAttributedString(string: "42", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white])
        let source = BadgeNode(value, .blue), reference = BadgeNode(value, .blue)
        let shared = BadgeNode(textFrom: source, .blue)
        value.replaceCharacters(in: NSRange(location: 0, length: value.length), with: "99")
        value.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 0, length: value.length))
        for scale in [1, 2] { XCTAssertEqual(try render(shared, scale: scale), try render(reference, scale: scale)) }
    }

    func testRetainedObjectsAndConstructionBenchmark() throws {
        guard ProcessInfo.processInfo.environment["BADGE_BENCHMARK"] != nil else { throw XCTSkip("Opt-in badge construction benchmark") }
        var report: [String: Any] = [:]
        for selected in [false, true] {
            for compact in [false, true] {
                var before: [Double] = [], after: [Double] = []
                var checksum: CGFloat = 0
                for batch in 0..<9 {
                    for candidate in batch % 2 == 0 ? [false, true] : [true, false] {
                        let elapsed = autoreleasepool { () -> Double in
                            let start = CACurrentMediaTime()
                            for index in 0..<1000 {
                                if candidate {
                                    let item = CandidateItem(); item.setupNormal(ReadState(count: index % 200 + 1)); item.isActiveSelected = selected
                                    checksum += item.ctxBadgeNode!.size.width
                                    if compact { checksum += item.ctxShortBadgeNode!.size.width }
                                } else {
                                    let item = ReferenceItem(); item.setupNormal(ReadState(count: index % 200 + 1)); item.isActiveSelected = selected
                                    checksum += item.ctxBadgeNode!.size.width
                                    if compact { checksum += item.ctxShortBadgeNode!.size.width }
                                }
                            }
                            return (CACurrentMediaTime() - start) * 1000
                        }
                        if candidate { after.append(elapsed) } else { before.append(elapsed) }
                    }
                }
                let current = CandidateItem(), reference = ReferenceItem()
                current.setupNormal(ReadState(count: 7)); reference.setupNormal(ReadState(count: 7))
                current.isActiveSelected = selected; reference.isActiveSelected = selected
                _ = current.ctxBadgeNode; _ = reference.ctxBadgeNode
                if compact { _ = current.ctxShortBadgeNode; _ = reference.ctxShortBadgeNode }
                report["selected=\(selected),compact=\(compact)"] = ["baseline_ms_per_1000": before, "candidate_ms_per_1000": after, "baseline_objects": try objects(reference), "candidate_objects": try objects(current)]
                XCTAssertGreaterThan(checksum, 0)
            }
        }
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/badge-benchmark.json"))
    }

    private func objects(_ item: ItemEnvironment) throws -> [String: Int] {
        let badges = [item.badgeNode, item.shortBadgeNode, item.badgeSelectedNode, item.shortBadgeSelectedNode].compactMap { $0 }
        var unique: [ObjectIdentifier: AnyObject] = [:]
        var layouts = Set<ObjectIdentifier>()
        for badge in badges {
            let pair: (TextNodeLayout, TextNode) = try XCTUnwrap(field(badge, "textLayout"))
            layouts.insert(ObjectIdentifier(pair.0))
            for object: AnyObject in [badge, pair.0, pair.1, badge.nodeReady] { unique[ObjectIdentifier(object)] = object }
        }
        return ["badges": badges.count, "text_layouts": layouts.count, "direct_object_bytes": unique.values.reduce(0) { $0 + malloc_size(Unmanaged.passUnretained($1).toOpaque()) }]
    }

    private func render(_ badge: BadgeNode, scale: Int) throws -> Data {
        let view = View(frame: badge.size.bounds)
        badge.view = view
        let layer = CALayer(); layer.bounds = badge.size.bounds
        let width = Int(ceil(badge.size.width * CGFloat(scale))), height = Int(ceil(badge.size.height * CGFloat(scale)))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        badge.draw(layer, in: context)
        let bytes = Data(bytes: try XCTUnwrap(context.data), count: width * height * 4)
        XCTAssertTrue(bytes.contains { $0 != 0 })
        withExtendedLifetime(view) {}
        return bytes
    }

}
