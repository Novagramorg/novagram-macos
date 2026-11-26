import Cocoa
import XCTest
import TGUIKit
import InputView
import InputTextView
import TelegramContext
import InlineStickerLayer
@testable import FoldingViewHarness
@testable import ChatLayerEngine

final class LiveInlineEmojiTests: XCTestCase {
    typealias Sticker = InlineStickerLayer.InlineStickerItem
    typealias MediaLayer = InlineStickerLayer.InlineStickerItemLayer

    final class KeyWindow: NSWindow {
        var active = true
        override var isKeyWindow: Bool { active }
    }

    final class Host {
        let window = KeyWindow(contentRect: CGRect(x: 0, y: 0, width: 360, height: 180), styleMask: [.borderless], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 360, height: 180))
        let document = View(frame: CGRect(x: 0, y: 0, width: 360, height: 1000))
        init(_ row: NSView) {
            window.isReleasedWhenClosed = false
            window.contentView = scroll
            scroll.documentView = document
            scroll.contentView.postsBoundsChangedNotifications = true
            document.postsFrameChangedNotifications = true
            document.addSubview(row)
        }
        deinit { window.close() }
    }

    override func setUp() {
        TGUIKitTestBootstrap.install()
        System.updateScaleFactor(2)
        MediaLayer.onCreate = nil
    }

    override func tearDown() {
        MediaLayer.onCreate = nil
        System.updateScaleFactor(2)
    }

    func sticker(_ id: Int64 = 1, tint: NSColor? = nil, policy: InlineStickerLayer.PlayPolicy? = nil) -> Sticker {
        Sticker(source: .attribute(ChatTextCustomEmojiAttribute(fileId: id, color: tint)), playPolicy: policy)
    }

    func item(_ id: Int = 1, context: BlockContext, stickers: [Sticker], rawIds: [Int64]? = nil, quoted: Bool = false, spoiler: Bool = false, streaming: Bool = false, textColor: NSColor = .black, prefix: String = "prefix ") -> FoldingViewHarness.ChatMessageItem {
        let full = NSMutableAttributedString(string: "")
        var texts: [TextViewLayout] = [], ranges: [NSRange] = []
        for (index, sticker) in stickers.enumerated() {
            let value = NSMutableAttributedString(string: prefix + "🦆 tail", attributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: textColor])
            let range = NSRange(location: (prefix as NSString).length, length: 2)
            value.addAttribute(TextInputAttributes.embedded, value: sticker, range: range)
            if let rawIds { value.addAttribute(TextInputAttributes.customEmoji, value: TextInputTextCustomEmojiAttribute(fileId: rawIds[index]), range: range) }
            if quoted { value.addAttribute(TextInputAttributes.quote, value: TextViewBlockQuoteData(id: index, colors: .init(main: .blue), collapsable: false), range: value.range) }
            if spoiler { value.addAttribute(TextInputAttributes.spoiler, value: NSNumber(value: true), range: range) }
            ranges.append(NSRange(location: full.length, length: value.length))
            full.append(value)
            texts.append(TextViewLayout(value))
        }
        let layout = FoldingViewHarness.FoldingTextLayout(attributedString: full, blocks: texts, blockRanges: ranges, context: context, revealed: [], appendingAnimation: streaming)
        layout.measure(width: 240)
        return FoldingViewHarness.ChatMessageItem(id: id, layout: layout)
    }

    func layers(_ view: NSView) -> [MediaLayer] {
        var visited = Set<ObjectIdentifier>()
        func collect(_ layer: CALayer) -> [MediaLayer] {
            guard visited.insert(ObjectIdentifier(layer)).inserted else { return [] }
            if let media = layer as? MediaLayer { return [media] }
            return layer.sublayers?.flatMap(collect) ?? []
        }
        func visit(_ view: NSView) -> [MediaLayer] {
            let own = view.layer.map(collect) ?? []
            return own + view.subviews.flatMap(visit)
        }
        return visit(view)
    }

    func caption(_ id: Int, item: FoldingViewHarness.ChatMessageItem, offset: NSPoint = .zero) -> FoldingViewHarness.ChatRowItem.RowCaption {
        .init(messageId: id, id: UInt32(id), layout: item.textLayout, offset: offset)
    }

    func testCoordinatedHostReuseRefreshesEachEmojiOnce() throws {
        let context = BlockContext()
        let row = LayerChatTextRow(frame: CGRect(x: 0, y: 0, width: 320, height: 160))
        let model = item(context: context, stickers: [sticker(), sticker(2)], rawIds: [1, 2])
        row.bind(model)
        row.finishLayout()
        let attached = Host(row)
        let host = try XCTUnwrap(row.layerText)
        host.layoutSubtreeIfNeeded()
        let media = layers(host)
        XCTAssertEqual(media.count, 2)
        XCTAssertTrue(media.allSatisfy { $0.isPlayable == true })
        let presentation = try XCTUnwrap(ChatLayerMessageTextPresentation.simpleText(model.textLayout))
        let identity = ChatLayerMessageTextView.Identity(messageId: model.stableId, accountId: ObjectIdentifier(context))
        for _ in 0..<3 {
            let assignments = media.map { $0.playbackAssignments }
            XCTAssertTrue(host.update(presentation, identity: identity, context: context))
            for (index, layer) in media.enumerated() {
                XCTAssertEqual(layer.playbackAssignments, assignments[index] + 1)
                XCTAssertEqual(layer.isPlayable, true)
                XCTAssertFalse(layer.isVisibleForFetching)
                XCTAssertTrue(layer.superview === host)
            }
            XCTAssertEqual(layers(host).map(ObjectIdentifier.init), media.map(ObjectIdentifier.init))
        }
        withExtendedLifetime(attached) {}
    }

    func testBodyAndCaptionEmojiUseOneViewAndMatchNativePlacementPixels() throws {
        let context = BlockContext()
        var comparisons = 0
        for scale: CGFloat in [1, 2, 3] {
            System.updateScaleFactor(scale)
            for isCaption in [false, true] {
                let model = item(context: context, stickers: [sticker(tint: .red), sticker(2, tint: .blue)], rawIds: [1, 2], prefix: "مرحبا ")
                let row: View
                let host: ChatLayerMessageTextView
                if isCaption {
                    let captionRow = LayerCaptionRow(frame: CGRect(x: 0, y: 0, width: 320, height: 160))
                    captionRow.bind(ChatRowItem([caption(1, item: model, offset: NSPoint(x: 17, y: 23))]))
                    captionRow.finishLayout()
                    row = captionRow
                    host = try XCTUnwrap(captionRow.captionViews.first?.layerView)
                } else {
                    let textRow = LayerChatTextRow(frame: CGRect(x: 0, y: 0, width: 320, height: 160))
                    model.textOrigin = NSPoint(x: 17, y: 23)
                    textRow.bind(model)
                    textRow.finishLayout()
                    row = textRow
                    host = try XCTUnwrap(textRow.layerText)
                }
                let attached = Host(row)
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(viewTreeCount(host), 1)
                XCTAssertEqual(layers(host).count, 2)
                let reference = View(frame: host.bounds)
                for (index, block) in model.textLayout.blocks.enumerated() {
                    let text = TextView()
                    text.disableBackgroundDrawing = true
                    text.update(block.text)
                    text.frame = host.body.textNodes[index].frame
                    reference.addSubview(text)
                    for embedded in block.text.embeddedItems {
                        let source = try XCTUnwrap(embedded.value as? Sticker)
                        guard case let .attribute(emoji) = source.source else { return XCTFail() }
                        let media = MediaLayer(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: emoji, size: embedded.rect.size, textColor: .black)
                        media.frame = embedded.rect
                        text.addEmbeddedLayer(media)
                    }
                }
                XCTAssertEqual(ViewSnapshot.render(host, scale: scale).differingPixels(from: ViewSnapshot.render(reference, scale: scale), tolerance: 0), 0)
                comparisons += 1
                withExtendedLifetime(attached) {}
            }
        }
        XCTAssertEqual(comparisons, 6)
    }

    func testBodyReusePreservesOccurrenceAndSelectionButInvalidatesTintAndAccount() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let first = item(context: context, stickers: [sticker(), sticker()], rawIds: [1, 1])
        row.bind(first)
        let host = try XCTUnwrap(row.layerText), original = layers(host)
        XCTAssertEqual(original.count, 2)
        XCTAssertFalse(original[0] === original[1])
        host.body.textNodes[0].setExternalSelection(NSRange(location: 0, length: first.textLayout.blocks[0].text.attributedString.length))
        let same = item(context: context, stickers: [sticker(), sticker()], rawIds: [1, 1])
        row.bind(same)
        XCTAssertTrue(row.layerText === host)
        XCTAssertTrue(zip(original, layers(host)).allSatisfy { $0 === $1 })
        XCTAssertEqual(same.textLayout.blocks[0].text.selectedRange.range, first.textLayout.blocks[0].text.selectedRange.range)
        var copied: NSAttributedString?
        host.body.textNodes[0].copyText = { copied = $0 }
        XCTAssertEqual(host.body.textNodes[0].onCommand?(#selector(ChatLayerSceneView.copy(_:))), true)
        let copiedEmoji = try XCTUnwrap(copied?.attribute(TextInputAttributes.customEmoji, at: 7, effectiveRange: nil) as? TextInputTextCustomEmojiAttribute)
        XCTAssertEqual(copiedEmoji.fileId, 1)
        XCTAssertNotNil(copied?.attribute(TextInputAttributes.embedded, at: 7, effectiveRange: nil) as? Sticker)
        XCTAssertEqual(host.body.textNodes[0].accessibilityValue as? String, same.textLayout.blocks[0].text.string)
        XCTAssertTrue(host.body.textNodes.allSatisfy { $0.children.isEmpty })
        row.bind(item(2, context: context, stickers: [sticker(tint: .black)]))
        let explicit = try XCTUnwrap(layers(host).first)
        XCTAssertFalse(explicit === original[0])
        XCTAssertNil(original[0].superlayer)
        XCTAssertEqual(original[0].isPlayable, false)
        XCTAssertEqual(host.body.textNodes.count, 1)
        XCTAssertEqual(host.body.textNodes[0].textLayout?.selectedRange.range.location, NSNotFound)
        row.bind(item(2, context: context, stickers: [sticker(tint: .black)]))
        XCTAssertTrue(layers(host).first === explicit)
        context.account = TelegramContext.Account()
        row.bind(item(2, context: context, stickers: [sticker(tint: .black)]))
        XCTAssertFalse(layers(host).first === explicit)
        XCTAssertNil(explicit.superlayer)
    }

    func testCaptionReorderPreservesMediaAndRemovalStopsBeforeAnimationCompletes() throws {
        let context = BlockContext(), row = LayerCaptionRow(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let first = caption(1, item: item(context: context, stickers: [sticker()])), second = caption(2, item: item(2, context: context, stickers: [sticker(2)]), offset: NSPoint(x: 12, y: 55))
        row.bind(ChatRowItem([first, second]))
        let a = try XCTUnwrap(row.captionViews[0].layerView), b = try XCTUnwrap(row.captionViews[1].layerView)
        let mediaA = try XCTUnwrap(layers(a).first), mediaB = try XCTUnwrap(layers(b).first)
        let attached = Host(row)
        row.finishLayout()
        row.bind(ChatRowItem([second, first]))
        row.finishLayout()
        XCTAssertTrue(row.captionViews[0].layerView === b)
        XCTAssertTrue(row.captionViews[1].layerView === a)
        XCTAssertTrue(layers(a).first === mediaA)
        XCTAssertTrue(layers(b).first === mediaB)
        row.bind(ChatRowItem([second]), animated: true)
        XCTAssertNil(mediaA.superlayer)
        XCTAssertNil(mediaA.superview)
        XCTAssertEqual(mediaA.isPlayable, false)
        let assignments = mediaA.playbackAssignments
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: attached.window)
        XCTAssertEqual(mediaA.playbackAssignments, assignments)
        XCTAssertTrue(layers(b).first === mediaB)
    }

    func testObserverTracksScrollWindowLiteHiddenAndAncestorMovement() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        row.bind(item(context: context, stickers: [sticker()]))
        let host = try XCTUnwrap(row.layerText), media = try XCTUnwrap(layers(host).first)
        let attached = Host(row)
        row.finishLayout()
        row.updateAnimatableContent()
        XCTAssertEqual(media.isPlayable, true)
        attached.scroll.contentView.scroll(to: NSPoint(x: 0, y: 300))
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: attached.scroll.contentView)
        XCTAssertEqual(media.isPlayable, false)
        attached.scroll.contentView.scroll(to: .zero)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: attached.scroll.contentView)
        XCTAssertEqual(media.isPlayable, true)
        attached.window.active = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: attached.window)
        XCTAssertEqual(media.isPlayable, false)
        attached.window.active = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: attached.window)
        XCTAssertEqual(media.isPlayable, true)
        context.lite = true
        row.updateAnimatableContent()
        XCTAssertEqual(media.isPlayable, false)
        context.lite = false
        row.updateAnimatableContent()
        XCTAssertEqual(media.isPlayable, true)
        host.isHidden = true
        XCTAssertEqual(media.isPlayable, false)
        host.isHidden = false
        XCTAssertEqual(media.isPlayable, true)
        host.alphaValue = 0
        XCTAssertEqual(media.isPlayable, false)
        host.alphaValue = 1
        XCTAssertEqual(media.isPlayable, true)
        row.frame.origin.y = 350
        row.updateAnimatableContent()
        XCTAssertEqual(media.isPlayable, false)
        row.frame.origin.y = 0
        row.updateAnimatableContent()
        XCTAssertEqual(media.isPlayable, true)
        row.removeFromSuperview()
        XCTAssertEqual(media.isPlayable, false)
        let detachedAssignments = media.playbackAssignments
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: attached.window)
        XCTAssertEqual(media.playbackAssignments, detachedAssignments)
        attached.document.addSubview(row)
        XCTAssertEqual(media.isPlayable, true)
        XCTAssertTrue(layers(host).first === media)
    }

    func testCaptionObserverRebindsWindowAndReceivesRowLiteUpdates() throws {
        let context = BlockContext(), row = LayerCaptionRow(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        row.bind(ChatRowItem([caption(1, item: item(context: context, stickers: [sticker()]))]))
        let host = try XCTUnwrap(row.captionViews.first?.layerView), media = try XCTUnwrap(layers(host).first)
        let first = Host(row)
        row.finishLayout()
        row.updateAnimatableContent()
        XCTAssertEqual(media.isPlayable, true)
        context.lite = true
        row.updateAnimatableContent()
        XCTAssertEqual(media.isPlayable, false)
        context.lite = false
        row.updateAnimatableContent()
        XCTAssertEqual(media.isPlayable, true)
        let second = Host(row)
        row.updateAnimatableContent()
        let assignments = media.playbackAssignments
        first.window.active = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: first.window)
        XCTAssertEqual(media.playbackAssignments, assignments)
        XCTAssertEqual(media.isPlayable, true)
        second.window.active = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: second.window)
        XCTAssertEqual(media.isPlayable, false)
        second.window.active = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: second.window)
        XCTAssertEqual(media.isPlayable, true)
    }

    func testPlainReplacementAndPrepareForRemovalReleaseObservationAndMedia() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let attached = Host(row)
        row.bind(item(context: context, stickers: [sticker()]))
        let host = try XCTUnwrap(row.layerText), old = try XCTUnwrap(layers(host).first)
        row.bind(ChatTextReuseTests().item(2, context: context, text: "ordinary text"))
        XCTAssertTrue(row.layerText === host)
        XCTAssertTrue(layers(host).isEmpty)
        XCTAssertNil(old.superlayer)
        XCTAssertEqual(old.isPlayable, false)
        let count = old.playbackAssignments
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: attached.window)
        XCTAssertEqual(old.playbackAssignments, count)
        row.bind(item(3, context: context, stickers: [sticker(3)]))
        let next = try XCTUnwrap(layers(host).first)
        XCTAssertTrue(host.prepareForRemoval())
        XCTAssertNil(next.superlayer)
        XCTAssertNil(next.superview)
        XCTAssertEqual(next.isPlayable, false)
        XCTAssertTrue(host.isEventLess)
        let removedCount = next.playbackAssignments
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: attached.scroll.contentView)
        XCTAssertEqual(next.playbackAssignments, removedCount)
    }

    func testUnsupportedAndUnmappedEmojiKeepNativeBodyAndCaptionPaths() {
        let context = BlockContext()
        var fixtures = [
            item(context: context, stickers: [sticker()], rawIds: [9]),
            item(context: context, stickers: [sticker(policy: .once)]),
            item(context: context, stickers: [Sticker(source: .avatar(1))]),
            item(context: context, stickers: [sticker()], quoted: true),
            item(context: context, stickers: [sticker()], spoiler: true),
            item(context: context, stickers: [sticker()], streaming: true)
        ]
        let unmapped = ChatTextReuseTests().item(1, context: context, text: "raw emoji")
        (unmapped.textLayout.blocks[0].text.attributedString as! NSMutableAttributedString).addAttribute(TextInputAttributes.customEmoji, value: TextInputTextCustomEmojiAttribute(fileId: 1), range: NSRange(location: 0, length: 3))
        fixtures.append(unmapped)
        let emojiBlock = item(context: context, stickers: [sticker()]).textLayout.blocks[0].text
        let quoteBlock = ChatTextReuseTests().item(1, quoted: true, context: context, text: "one\ntwo\nthree\nfour\nfive", collapsable: true).textLayout.blocks[0].text
        let mixedText = NSMutableAttributedString(attributedString: emojiBlock.attributedString)
        mixedText.append(quoteBlock.attributedString)
        let mixed = FoldingViewHarness.FoldingTextLayout(attributedString: mixedText, blocks: [emojiBlock, quoteBlock], blockRanges: [NSRange(location: 0, length: emojiBlock.attributedString.length), NSRange(location: emojiBlock.attributedString.length, length: quoteBlock.attributedString.length)], context: context, revealed: [])
        mixed.measure(width: 240)
        fixtures.append(FoldingViewHarness.ChatMessageItem(id: 1, layout: mixed))
        for fixture in fixtures {
            let row = LayerChatTextRow(frame: .zero)
            row.bind(fixture)
            XCTAssertNil(row.layerText)
            XCTAssertNotNil(row.text)
            let captionRow = LayerCaptionRow(frame: .zero)
            captionRow.bind(ChatRowItem([caption(1, item: fixture)]))
            XCTAssertNil(captionRow.captionViews.first?.layerView)
            XCTAssertNotNil(captionRow.captionViews.first?.nativeView)
            let blocks = fixture.textLayout.blocks.map { InputTextView.FoldingTextLayout.ViewLayout(text: $0.text, isRevealed: $0.isRevealed, size: $0.size) }
            let presentation = ChatLayerMessageTextPresentation(InputTextView.FoldingTextLayout(blocks: blocks, appendingAnimation: fixture.textLayout.appendingAnimation))
            XCTAssertFalse(ChatLayerMessageTextView.supports(presentation))
        }
    }

    func testOuterBodyBindingReentryKeepsNewestIdentityAndCleansStaleMedia() throws {
        for hasPrevious in [false, true] {
            let context = BlockContext(), row = LayerChatTextRow(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
            let attached = Host(row)
            if hasPrevious { row.bind(item(context: context, stickers: [sticker()])) }
            let previousHost = row.layerText
            let previousMedia = previousHost.flatMap { layers($0).first }
            let obsolete = item(2, context: context, stickers: [sticker(2)], prefix: "obsolete ")
            let newest = item(3, context: context, stickers: [sticker(3)], prefix: "newest ")
            newest.textOrigin = NSPoint(x: 19, y: 27)
            var staleMedia: MediaLayer?
            MediaLayer.onCreate = { media in
                MediaLayer.onCreate = nil
                staleMedia = media
                row.bind(newest)
            }
            row.bind(obsolete)
            row.finishLayout()
            let host = try XCTUnwrap(row.layerText)
            XCTAssertTrue(row.item === newest)
            XCTAssertTrue(host.body.textNodes.first?.textLayout === newest.textLayout.blocks[0].text)
            XCTAssertEqual(layers(host).map { $0.source.fileId }, [3])
            XCTAssertEqual(layers(row).map { $0.source.fileId }, [3])
            XCTAssertEqual(host.frame.origin, newest.textOrigin)
            XCTAssertNil(row.text)
            XCTAssertEqual(row.subviews.count, 1)
            if hasPrevious { XCTAssertTrue(host === previousHost) }
            let stale = try XCTUnwrap(staleMedia)
            XCTAssertNil(stale.superlayer)
            XCTAssertNil(stale.superview)
            XCTAssertEqual(stale.isPlayable, false)
            if let previousMedia {
                XCTAssertNil(previousMedia.superlayer)
                XCTAssertNil(previousMedia.superview)
                XCTAssertEqual(previousMedia.isPlayable, false)
            }
            let assignments = stale.playbackAssignments
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: attached.window)
            XCTAssertEqual(stale.playbackAssignments, assignments)
        }
    }

    func testOuterCaptionBindingQueuesNewestIdentityAndCleansStaleMedia() throws {
        for hasPrevious in [false, true] {
            let context = BlockContext(), row = LayerCaptionRow(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
            let attached = Host(row)
            if hasPrevious { row.bind(ChatRowItem([caption(1, item: item(context: context, stickers: [sticker()]))])) }
            let previousHost = row.captionViews.first?.layerView
            let previousMedia = previousHost.flatMap { layers($0).first }
            let obsoleteModel = item(2, context: context, stickers: [sticker(2)], prefix: "obsolete ")
            let newestModel = item(3, context: context, stickers: [sticker(3)], prefix: "newest ")
            let obsolete = ChatRowItem([caption(2, item: obsoleteModel)])
            let newest = ChatRowItem([caption(3, item: newestModel, offset: NSPoint(x: 11, y: 29))])
            var staleMedia: MediaLayer?
            MediaLayer.onCreate = { media in
                MediaLayer.onCreate = nil
                staleMedia = media
                row.bind(newest)
            }
            row.bind(obsolete)
            row.finishLayout()
            let host = try XCTUnwrap(row.captionViews.first?.layerView)
            XCTAssertTrue(row.item === newest)
            XCTAssertEqual(row.ids, [3])
            XCTAssertEqual(row.captionViews.count, 1)
            XCTAssertTrue(host.body.textNodes.first?.textLayout === newestModel.textLayout.blocks[0].text)
            XCTAssertEqual(layers(host).map { $0.source.fileId }, [3])
            XCTAssertEqual(layers(row).map { $0.source.fileId }, [3])
            XCTAssertEqual(host.frame.origin, NSPoint(x: 11, y: 29))
            XCTAssertEqual(row.rowView.subviews.count, 2)
            host.body.revealBlockAtIndex?(0)
            XCTAssertEqual(newest.revealed.map { $0.1 }, [3])
            XCTAssertTrue(obsolete.revealed.isEmpty)
            let stale = try XCTUnwrap(staleMedia)
            XCTAssertNil(stale.superlayer)
            XCTAssertNil(stale.superview)
            XCTAssertEqual(stale.isPlayable, false)
            if let previousMedia {
                XCTAssertNil(previousMedia.superlayer)
                XCTAssertNil(previousMedia.superview)
                XCTAssertEqual(previousMedia.isPlayable, false)
            }
            let assignments = stale.playbackAssignments
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: attached.window)
            XCTAssertEqual(stale.playbackAssignments, assignments)
        }
    }

    func testConstructorReentryKeepsNewestMediaAndTextBinding() throws {
        let context = BlockContext(), host = ChatLayerMessageTextView(frame: CGRect(x: 0, y: 0, width: 240, height: 100))
        let identity = ChatLayerMessageTextView.Identity(messageId: 1, accountId: ObjectIdentifier(context))
        let first = try XCTUnwrap(ChatLayerMessageTextPresentation.simpleText(item(context: context, stickers: [sticker()]).textLayout))
        XCTAssertTrue(host.update(first, identity: identity, context: context))
        let obsolete = try XCTUnwrap(ChatLayerMessageTextPresentation.simpleText(item(context: context, stickers: [sticker(2)]).textLayout))
        let newest = try XCTUnwrap(ChatLayerMessageTextPresentation.simpleText(item(context: context, stickers: [sticker(3)]).textLayout))
        var didReenter = false
        MediaLayer.onCreate = { _ in
            MediaLayer.onCreate = nil
            didReenter = true
            XCTAssertTrue(host.update(newest, identity: identity, context: context))
        }
        XCTAssertFalse(host.update(obsolete, identity: identity, context: context))
        XCTAssertTrue(didReenter)
        XCTAssertTrue(host.body.textNodes[0].textLayout === newest.blocks[0].layout)
        XCTAssertEqual(layers(host).map { $0.source.fileId }, [3])
        XCTAssertTrue(host.prepareForRemoval())
        XCTAssertTrue(layers(host).isEmpty)
    }
}
