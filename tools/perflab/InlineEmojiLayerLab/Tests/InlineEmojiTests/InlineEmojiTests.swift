import Cocoa
import XCTest
import TGUIKit
import TelegramContext
import InputView
import InlineStickerLayer
@testable import InlineEmojiHelper

final class InlineEmojiTests: XCTestCase {
    private static var images: [NSImage] = []
    override func setUp() {
        _ = NSApplication.shared
        System.updateScaleFactor(2)
        System.liquidGlass = false
        if Self.images.isEmpty {
            for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"] {
                let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                    NSColor.black.setFill()
                    rect.insetBy(dx: 4, dy: 4).fill()
                    return true
                }
                _ = image.setName(name)
                Self.images.append(image)
            }
        }
    }

    final class TestWindow: NSWindow {
        var active = true
        override var isKeyWindow: Bool { active }
    }

    final class Host {
        let window = TestWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 160), styleMask: [.borderless], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 160))
        let document = View(frame: CGRect(x: 0, y: 0, width: 320, height: 1000))
        let scene = View(frame: CGRect(x: 0, y: 0, width: 320, height: 1000))
        let node = SimpleLayer(frame: CGRect(x: 30, y: 40, width: 240, height: 100))
        init() {
            window.isReleasedWhenClosed = false
            window.contentView = scroll
            scroll.documentView = document
            document.addSubview(scene)
            scene.layer!.addSublayer(node)
            document.layoutSubtreeIfNeeded()
        }
        deinit { window.contentView = nil; window.close() }
    }

    private func emoji(_ id: Int64 = 1, tint: NSColor? = nil, revision: Int? = nil, policy: PlayPolicy? = nil) -> InlineStickerItem {
        InlineStickerItem(source: .attribute(ChatTextCustomEmojiAttribute(fileId: id, file: revision.map { EmojiFile(revision: $0) }, color: tint)), playPolicy: policy)
    }

    private func layout(_ items: [InlineStickerItem], textColor: NSColor = .black, fontSize: CGFloat = 16, prefix: String = "") -> TextViewLayout {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: textColor]
        let text = NSMutableAttributedString(string: prefix, attributes: attributes)
        for item in items {
            let start = text.length
            text.append(NSAttributedString(string: "🦆 ", attributes: attributes))
            text.addAttribute(TextInputAttributes.embedded, value: item, range: NSRange(location: start, length: 2))
        }
        let value = TextViewLayout(text)
        value.measure(width: 300)
        return value
    }

    private func layers(_ helper: ChatLayerInlineEmoji) -> [InlineStickerItemLayer] {
        (helper.container.sublayers ?? []).compactMap { $0 as? InlineStickerItemLayer }
    }

    private func bind(_ helper: ChatLayerInlineEmoji, _ value: TextViewLayout, _ context: TestContext, _ host: Host) {
        XCTAssertTrue(helper.update(value, context: context, fallbackTextColor: .black))
        helper.attach(to: host.node, host: host.scene)
    }

    private struct SeededGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 33
        }
        mutating func value(_ range: ClosedRange<CGFloat>) -> CGFloat {
            return range.lowerBound + CGFloat(next() % 10_000) / 10_000 * (range.upperBound - range.lowerBound)
        }
        mutating func chance(_ probability: Double) -> Bool {
            return Double(next() % 10_000) / 10_000 < probability
        }
    }

    func testSharedContainerRegionMatchesPerLayerWalkOnRandomTrees() throws {
        let host = Host(), context = TestContext()
        var generator = SeededGenerator(state: 0x5eed)
        var compared = 0, playing = 0, paused = 0
        for _ in 0 ..< 600 {
            let helper = ChatLayerInlineEmoji()
            var parent: CALayer = host.scene.layer!
            var chain: [CALayer] = []
            for _ in 0 ..< Int(generator.next() % 4) {
                let layer = SimpleLayer()
                layer.anchorPoint = generator.chance(0.5) ? .zero : CGPoint(x: 0.5, y: 0.5)
                layer.frame = CGRect(x: generator.value(-40 ... 120), y: generator.value(-60 ... 500), width: generator.value(10 ... 320), height: generator.value(10 ... 400))
                layer.masksToBounds = generator.chance(0.4)
                if generator.chance(0.15) {
                    let mask = CALayer()
                    mask.frame = CGRect(x: generator.value(-20 ... 80), y: generator.value(-20 ... 200), width: generator.value(0 ... 260), height: generator.value(0 ... 260))
                    mask.backgroundColor = NSColor.black.cgColor
                    layer.mask = mask
                }
                if generator.chance(0.06) { layer.isHidden = true }
                if generator.chance(0.06) { layer.opacity = 0 }
                if generator.chance(0.1) { layer.transform = CATransform3DMakeScale(1.5, 0.75, 1) }
                if generator.chance(0.1) { layer.sublayerTransform = CATransform3DMakeTranslation(13, -9, 0) }
                if generator.chance(0.1) { layer.isGeometryFlipped = true }
                if generator.chance(0.1) { layer.bounds.origin = CGPoint(x: 5, y: -7) }
                parent.addSublayer(layer)
                chain.append(layer)
                parent = layer
            }
            let count = 2 + Int(generator.next() % 5)
            XCTAssertTrue(helper.update(layout((0 ..< count).map { emoji(Int64($0 + 1)) }), context: context, fallbackTextColor: .black))
            helper.attach(to: parent, host: host.scene)
            helper.container.position = CGPoint(x: generator.value(-50 ... 150), y: generator.value(-80 ... 300))
            for layer in layers(helper) {
                if generator.chance(0.08) { layer.isHidden = true }
                if generator.chance(0.08) { layer.transform = CATransform3DMakeScale(2, 2, 1) }
                if generator.chance(0.08) {
                    let mask = CALayer()
                    mask.frame = CGRect(x: generator.value(-5 ... 10), y: generator.value(-5 ... 10), width: generator.value(0 ... 20), height: generator.value(0 ... 20))
                    layer.mask = mask
                }
            }
            host.scroll.contentView.scroll(to: CGPoint(x: 0, y: generator.value(0 ... 800)))
            host.scroll.reflectScrolledClipView(host.scroll.contentView)
            let sibling = SimpleLayer()
            host.scene.layer!.addSublayer(sibling)
            switch generator.next() % 4 {
            case 0:
                helper.updateVisibility()
            case 1:
                helper.updateVisibility(ChatLayerInlineEmoji.visibility(in: host.scene, anchor: sibling), from: host.scene)
            default:
                let anchor = chain.isEmpty ? host.scene.layer! : chain[Int(generator.next() % UInt64(chain.count))]
                helper.updateVisibility(ChatLayerInlineEmoji.visibility(in: host.scene, anchor: anchor), from: host.scene)
            }
            sibling.removeFromSuperlayer()
            for layer in layers(helper) {
                let expected = ChatLayerInlineEmoji.isVisible(layer, in: host.scene)
                XCTAssertEqual(layer.isPlayable, expected, "Shared region must match the per-layer walk")
                compared += 1
                if expected { playing += 1 } else { paused += 1 }
            }
            helper.detach()
            chain.first?.removeFromSuperlayer()
        }
        XCTAssertGreaterThan(compared, 2000)
        XCTAssertGreaterThan(playing, 100)
        XCTAssertGreaterThan(paused, 100)
    }

    func testDeferredVisibilityStillPausesReplacedAndDetachedLayersImmediately() throws {
        let host = Host(), context = TestContext(), helper = ChatLayerInlineEmoji()
        XCTAssertTrue(helper.update(layout([emoji()]), context: context, fallbackTextColor: .black, refreshVisibility: false))
        let first = try XCTUnwrap(layers(helper).first)
        helper.attach(to: host.node, host: host.scene, refreshVisibility: false)
        XCTAssertEqual(first.isPlayable, false)
        XCTAssertFalse(first.isVisibleForFetching)
        XCTAssertTrue(first.superview === host.scene)
        helper.updateVisibility()
        XCTAssertEqual(first.isPlayable, true)
        XCTAssertFalse(first.isVisibleForFetching)

        XCTAssertTrue(helper.update(layout([emoji(2)]), context: context, fallbackTextColor: .black, refreshVisibility: false))
        let replacement = try XCTUnwrap(layers(helper).first)
        XCTAssertFalse(replacement === first)
        XCTAssertNil(first.superlayer)
        XCTAssertNil(first.superview)
        XCTAssertEqual(first.isPlayable, false)
        XCTAssertFalse(first.isVisibleForFetching)
        XCTAssertEqual(replacement.isPlayable, false)
        helper.attach(to: host.node, host: host.scene, refreshVisibility: false)
        XCTAssertEqual(replacement.isPlayable, false)
        helper.updateVisibility()
        XCTAssertEqual(replacement.isPlayable, true)
        helper.detach()
        XCTAssertNil(replacement.superlayer)
        XCTAssertNil(replacement.superview)
        XCTAssertEqual(replacement.isPlayable, false)
        XCTAssertFalse(replacement.isVisibleForFetching)
    }

    func testIdenticalSourceAndMovedGeometryReuseWithoutLosingTint() throws {
        let host = Host(), context = TestContext(), helper = ChatLayerInlineEmoji()
        bind(helper, layout([emoji(tint: .red)]), context, host)
        let first = try XCTUnwrap(layers(helper).first)
        let originalFrame = first.frame
        let next = layout([emoji(tint: .red)], prefix: "prefix ")
        bind(helper, next, context, host)
        XCTAssertTrue(layers(helper).first === first)
        XCTAssertNotEqual(first.frame.origin, originalFrame.origin)
        XCTAssertEqual(first.frame, next.embeddedItems[0].rect)
        XCTAssertEqual(first.textColor, .black)
        XCTAssertEqual(first.color, .red)
        XCTAssertTrue(first.superview === host.scene)
    }

    func testSourceColorAndSizeChangesReplaceAndPauseOldLayer() throws {
        let host = Host(), context = TestContext(), helper = ChatLayerInlineEmoji()
        bind(helper, layout([emoji()]), context, host)
        var previous = try XCTUnwrap(layers(helper).first)
        let changes = [
            layout([emoji(tint: .black)]),
            layout([emoji()]),
            layout([emoji(tint: .red)]),
            layout([emoji(tint: .red)], textColor: .blue),
            layout([emoji(2, tint: .red)], textColor: .blue),
            layout([emoji(2, tint: .red, revision: 1)], textColor: .blue),
            layout([emoji(2, tint: .red, revision: 2)], textColor: .blue),
            layout([emoji(2, tint: .red, revision: 2)], textColor: .blue, fontSize: 24)
        ]
        for value in changes {
            bind(helper, value, context, host)
            let current = try XCTUnwrap(layers(helper).first)
            XCTAssertFalse(current === previous)
            XCTAssertNil(previous.superlayer)
            XCTAssertNil(previous.superview)
            XCTAssertEqual(previous.isPlayable, false)
            XCTAssertFalse(previous.isVisibleForFetching)
            previous = current
        }
    }

    func testAccountAndContextChangesDiscardPreviousLayers() throws {
        let host = Host(), context = TestContext(), helper = ChatLayerInlineEmoji()
        let value = layout([emoji()])
        bind(helper, value, context, host)
        var previous = try XCTUnwrap(layers(helper).first)
        context.account = Account()
        bind(helper, value, context, host)
        var current = try XCTUnwrap(layers(helper).first)
        XCTAssertFalse(current === previous)
        XCTAssertEqual(current.accountId, ObjectIdentifier(context.account))
        XCTAssertNil(previous.superview)
        previous = current
        let nextContext = TestContext(account: context.account)
        bind(helper, value, nextContext, host)
        current = try XCTUnwrap(layers(helper).first)
        XCTAssertFalse(current === previous)
        XCTAssertNil(previous.superlayer)
    }

    func testReleasedContextCannotMatchNewContextForSameAccount() throws {
        let host = Host(), account = Account(), helper = ChatLayerInlineEmoji()
        var previousContext: TestContext? = TestContext(account: account)
        let value = layout([emoji()])
        bind(helper, value, previousContext!, host)
        let previousLayer = try XCTUnwrap(layers(helper).first)
        weak var releasedContext = previousContext
        previousContext = nil
        XCTAssertNil(releasedContext)
        XCTAssertFalse(helper.isEmpty)
        let nextContext = TestContext(account: account)
        bind(helper, value, nextContext, host)
        let current = try XCTUnwrap(layers(helper).first)
        XCTAssertFalse(current === previousLayer)
        XCTAssertEqual(current.accountId, previousLayer.accountId)
        XCTAssertNil(previousLayer.superlayer)
        XCTAssertNil(previousLayer.superview)
        XCTAssertEqual(previousLayer.isPlayable, false)
        XCTAssertTrue(current.superview === host.scene)
    }

    func testDuplicateOccurrencesKeepSeparateLayersAndRemoveTail() throws {
        let host = Host(), context = TestContext(), helper = ChatLayerInlineEmoji()
        bind(helper, layout([emoji(), emoji()]), context, host)
        let original = layers(helper)
        XCTAssertEqual(original.count, 2)
        XCTAssertFalse(original[0] === original[1])
        bind(helper, layout([emoji(), emoji()]), context, host)
        XCTAssertTrue(layers(helper)[0] === original[0])
        XCTAssertTrue(layers(helper)[1] === original[1])
        bind(helper, layout([emoji()]), context, host)
        XCTAssertTrue(layers(helper).first === original[0])
        XCTAssertNil(original[1].superlayer)
        XCTAssertEqual(original[1].isPlayable, false)
        bind(helper, layout([]), context, host)
        XCTAssertTrue(helper.isEmpty)
        XCTAssertNil(original[0].superlayer)
    }

    func testOccurrenceReorderingCannotReuseWrongSource() throws {
        let host = Host(), context = TestContext(), helper = ChatLayerInlineEmoji()
        bind(helper, layout([emoji(1), emoji(2)]), context, host)
        let original = layers(helper)
        bind(helper, layout([emoji(2), emoji(1)]), context, host)
        XCTAssertEqual(layers(helper).map { $0.source.fileId }, [2, 1])
        XCTAssertFalse(layers(helper)[0] === original[0])
        XCTAssertFalse(layers(helper)[1] === original[1])
        XCTAssertTrue(original.allSatisfy { $0.superlayer == nil && $0.superview == nil && $0.isPlayable == false })
    }

    func testVisibilityConvertsBlockOffsetsAndNestedClipping() throws {
        let host = Host(), context = TestContext(), helper = ChatLayerInlineEmoji()
        bind(helper, layout([emoji()]), context, host)
        let current = try XCTUnwrap(layers(helper).first)
        XCTAssertEqual(current.isPlayable, true)
        host.node.frame.origin.y = 400
        helper.updateVisibility()
        XCTAssertEqual(current.isPlayable, false)
        host.node.frame.origin.y = 40
        host.node.masksToBounds = true
        host.node.bounds.origin.x = 100
        helper.updateVisibility()
        XCTAssertEqual(current.isPlayable, false)
        host.node.bounds.origin.x = 0
        helper.updateVisibility()
        XCTAssertEqual(current.isPlayable, true)
        let clip = SimpleLayer(frame: CGRect(x: 30, y: 40, width: 100, height: 100))
        clip.masksToBounds = true
        host.scene.layer!.addSublayer(clip)
        host.node.removeFromSuperlayer()
        clip.addSublayer(host.node)
        host.node.frame.origin = CGPoint(x: 200, y: 0)
        helper.updateVisibility()
        XCTAssertEqual(current.isPlayable, false)
        host.node.frame.origin = .zero
        helper.updateVisibility()
        XCTAssertEqual(current.isPlayable, true)
        let mask = SimpleLayer(frame: CGRect(x: 80, y: 0, width: 20, height: 100))
        clip.mask = mask
        helper.updateVisibility()
        XCTAssertEqual(current.isPlayable, false)
        clip.mask = nil
        helper.updateVisibility()
        XCTAssertEqual(current.isPlayable, true)
    }

    func testVisibilityTracksHiddenAlphaScrollKeyAndLiteState() throws {
        let host = Host(), context = TestContext(), helper = ChatLayerInlineEmoji()
        bind(helper, layout([emoji()]), context, host)
        let current = try XCTUnwrap(layers(helper).first)
        XCTAssertEqual(current.isPlayable, true)
        host.node.isHidden = true
        helper.updateVisibility()
        XCTAssertEqual(current.isPlayable, false)
        host.node.isHidden = false
        host.node.opacity = 0
        helper.updateVisibility()
        XCTAssertEqual(current.isPlayable, false)
        host.node.opacity = 1
        host.document.alphaValue = 0
        helper.updateVisibility()
        XCTAssertEqual(current.isPlayable, false)
        host.document.alphaValue = 1
        host.document.isHidden = true
        helper.updateVisibility()
        XCTAssertEqual(current.isPlayable, false)
        host.document.isHidden = false
        host.scroll.contentView.scroll(to: CGPoint(x: 0, y: 400))
        host.scroll.reflectScrolledClipView(host.scroll.contentView)
        helper.updateVisibility()
        XCTAssertEqual(current.isPlayable, false)
        host.scroll.contentView.scroll(to: .zero)
        helper.updateVisibility()
        XCTAssertEqual(current.isPlayable, true)
        host.window.active = false
        helper.updateVisibility()
        XCTAssertEqual(current.isPlayable, false)
        XCTAssertFalse(current.isVisibleForFetching)
        host.window.active = true
        context.lite = true
        helper.updateVisibility()
        XCTAssertEqual(current.isPlayable, false)
        context.lite = false
        helper.updateVisibility()
        XCTAssertEqual(current.isPlayable, true)
    }

    func testDetachAndOwnerReleaseRemoveAllOwnedMedia() throws {
        let host = Host(), context = TestContext()
        var helper: ChatLayerInlineEmoji?
        weak var releasedLayer: InlineStickerItemLayer?
        try autoreleasepool {
            CATransaction.begin()
            defer { CATransaction.commit(); CATransaction.flush() }
            helper = ChatLayerInlineEmoji()
            bind(helper!, layout([emoji()]), context, host)
            let current = try XCTUnwrap(layers(helper!).first)
            releasedLayer = current
            helper!.detach()
            XCTAssertNil(current.superlayer)
            XCTAssertNil(current.superview)
            XCTAssertEqual(current.isPlayable, false)
            XCTAssertFalse(current.isVisibleForFetching)
            XCTAssertTrue(helper!.isEmpty)
            XCTAssertNil(helper!.container.superlayer)
        }
        assertReleased { releasedLayer == nil }
        weak var releasedContainer: CALayer?
        try autoreleasepool {
            CATransaction.begin()
            defer { CATransaction.commit(); CATransaction.flush() }
            bind(helper!, layout([emoji()]), context, host)
            let current = try XCTUnwrap(layers(helper!).first)
            releasedLayer = current
            releasedContainer = helper!.container
            helper = nil
            XCTAssertNil(current.superlayer)
            XCTAssertNil(current.superview)
            XCTAssertEqual(current.isPlayable, false)
            XCTAssertFalse(current.isVisibleForFetching)
            XCTAssertNil(releasedContainer?.superlayer)
        }
        assertReleased { releasedLayer == nil && releasedContainer == nil }
    }

    func testPauseRetainsVisualLayerAndResumeUsesCurrentVisibility() throws {
        let host = Host(), context = TestContext(), helper = ChatLayerInlineEmoji()
        bind(helper, layout([emoji()]), context, host)
        let current = try XCTUnwrap(layers(helper).first)
        helper.pause()
        XCTAssertEqual(current.isPlayable, false)
        XCTAssertNotNil(current.superlayer)
        helper.updateVisibility()
        XCTAssertEqual(current.isPlayable, true)
        host.scene.removeFromSuperview()
        helper.updateVisibility()
        XCTAssertEqual(current.isPlayable, false)
        XCTAssertFalse(current.isVisibleForFetching)
        host.document.addSubview(host.scene)
        helper.updateVisibility()
        XCTAssertEqual(current.isPlayable, true)
    }

    func testWeakContextAndHostDoNotKeepOwnersAlive() throws {
        let host = Host(), helper = ChatLayerInlineEmoji()
        var context: TestContext? = TestContext()
        bind(helper, layout([emoji()]), context!, host)
        let current = try XCTUnwrap(layers(helper).first)
        weak var releasedContext = context
        context = nil
        XCTAssertNil(releasedContext)
        helper.updateVisibility()
        XCTAssertEqual(current.isPlayable, false)
        weak var releasedHost: View?
        autoreleasepool {
            CATransaction.begin()
            defer { CATransaction.commit(); CATransaction.flush() }
            let temporaryHost = View(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
            releasedHost = temporaryHost
            helper.attach(to: temporaryHost.layer!, host: temporaryHost)
            XCTAssertEqual(current.isPlayable, false)
        }
        assertReleased { releasedHost == nil }
        XCTAssertNil(current.superview)
        helper.updateVisibility()
        XCTAssertEqual(current.isPlayable, false)
    }

    func testUnsupportedSourceAndPolicyRejectAndReleasePreviousContent() throws {
        let host = Host(), context = TestContext(), helper = ChatLayerInlineEmoji()
        let pixels = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let unsupported = [InlineStickerItem(source: .avatar(1)), InlineStickerItem(source: .reference(2)), InlineStickerItem(source: .rendered(pixels.makeImage()!)), emoji(policy: .once)]
        for item in unsupported {
            weak var previous: InlineStickerItemLayer?
            try autoreleasepool {
                CATransaction.begin()
                defer { CATransaction.commit(); CATransaction.flush() }
                bind(helper, layout([emoji()]), context, host)
                let current = try XCTUnwrap(layers(helper).first)
                previous = current
                let value = layout([emoji(), item])
                XCTAssertFalse(ChatLayerInlineEmoji.supports(value))
                XCTAssertFalse(helper.update(value, context: context, fallbackTextColor: .black))
                XCTAssertTrue(helper.isEmpty)
                XCTAssertNil(current.superlayer)
                XCTAssertNil(current.superview)
                XCTAssertEqual(current.isPlayable, false)
                XCTAssertFalse(current.isVisibleForFetching)
            }
            assertReleased { previous == nil }
        }
    }

    func testTinyMeasuredItemsAndForeignEmbeddedValues() throws {
        let host = Host(), context = TestContext(), helper = ChatLayerInlineEmoji()
        weak var previous: InlineStickerItemLayer?
        try autoreleasepool {
            CATransaction.begin()
            defer { CATransaction.commit(); CATransaction.flush() }
            bind(helper, layout([emoji()]), context, host)
            let current = try XCTUnwrap(layers(helper).first)
            previous = current
            let tiny = layout([emoji()], fontSize: 2)
            XCTAssertLessThanOrEqual(try XCTUnwrap(tiny.embeddedItems.first).rect.width, 10)
            bind(helper, tiny, context, host)
            XCTAssertTrue(helper.isEmpty)
            XCTAssertNil(current.superlayer)
            XCTAssertNil(current.superview)
            XCTAssertEqual(current.isPlayable, false)
            XCTAssertFalse(current.isVisibleForFetching)
        }
        assertReleased { previous == nil }
        let foreign = NSMutableAttributedString(string: "🦆 ", attributes: [.font: NSFont.systemFont(ofSize: 16)])
        foreign.addAttribute(TextInputAttributes.embedded, value: NSString(string: "foreign"), range: NSRange(location: 0, length: 2))
        let value = TextViewLayout(foreign)
        value.measure(width: 240)
        XCTAssertFalse(value.embeddedItems.isEmpty)
        XCTAssertFalse(ChatLayerInlineEmoji.supports(value))
    }

    func testDeterministicFramesMatchNativeEmbeddedCoordinates() throws {
        let host = Host(), context = TestContext()
        for scale: CGFloat in [1, 2, 3] {
            System.updateScaleFactor(scale)
            for prefix in ["prefix ", "مرحبا "] {
                let value = layout([emoji(1, tint: .red), emoji(2, tint: .blue)], prefix: prefix)
                let current = TextView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
                let native = TextView(frame: current.frame)
                host.scene.addSubview(current)
                host.scene.addSubview(native)
                current.update(value)
                native.update(value)
                let helper = ChatLayerInlineEmoji()
                XCTAssertTrue(helper.update(value, context: context, fallbackTextColor: .black))
                helper.attach(to: current.layer!, host: current)
                for item in value.embeddedItems {
                    let source = try XCTUnwrap(item.value as? InlineStickerItem)
                    guard case let .attribute(attribute) = source.source else { return XCTFail("Unexpected source") }
                    let layer = InlineStickerItemLayer(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: attribute, size: item.rect.size, textColor: .black)
                    layer.frame = item.rect
                    native.addEmbeddedLayer(layer)
                }
                current.layout()
                native.layout()
                XCTAssertEqual(snapshot(current, scale: scale), snapshot(native, scale: scale), "scale=\(scale), prefix=\(prefix)")
                helper.detach()
                current.removeFromSuperview()
                native.removeFromSuperview()
            }
        }
        System.updateScaleFactor(2)
    }

    private func assertReleased(file: StaticString = #filePath, line: UInt = #line, _ released: () -> Bool) {
        let deadline = CACurrentMediaTime() + 2
        while !released(), CACurrentMediaTime() < deadline {
            autoreleasepool {
                CATransaction.flush()
                _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
                CATransaction.flush()
            }
        }
        XCTAssertTrue(released(), "Object survived transaction and autorelease draining", file: file, line: line)
    }

    private func snapshot(_ view: NSView, scale: CGFloat) -> Data {
        let width = Int(view.bounds.width * scale), height = Int(view.bounds.height * scale)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        func display(_ layer: CALayer) {
            layer.displayIfNeeded()
            layer.sublayers?.forEach(display)
        }
        display(view.layer!)
        view.layer!.render(in: context)
        return Data(bytes: context.data!, count: width * height * 4)
    }
}
