import Cocoa
import XCTest
import TGUIKit
import InputTextView
@testable import FoldingBlocksHarness

final class FoldingPlaybackTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func layout(quoted: Bool, media: Int = 0) -> FoldingTextLayout.ViewLayout {
        let value = NSMutableAttributedString(string: "🦆 hello مرحبا", attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.black])
        if media != 0 {
            let item = InlineStickerItem(media == 1 ? .attribute(Emoji(fileId: 1)) : media == 2 ? .avatar(Peer(id: PeerId(value: 1))) : .unsupported)
            value.addAttribute(TextInputAttributes.embedded, value: item, range: NSRange(location: 0, length: 2))
        }
        if quoted {
            value.addAttribute(TextInputAttributes.quote, value: TextViewBlockQuoteData(id: 1, colors: .init(main: .blue)), range: NSRange(location: 0, length: value.length))
        }
        let text = TextViewLayout(value)
        text.measure(width: 240)
        return FoldingTextLayout.ViewLayout(text: text)
    }

    final class PlaybackWindow: Window {
        var active = false
        override var isKeyWindow: Bool { active }
    }

    final class Host {
        let window = PlaybackWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        let document = View(frame: NSRect(x: 0, y: 0, width: 300, height: 1400))
        init() {
            window.isReleasedWhenClosed = false
            scroll.documentView = document
            window.contentView = scroll
        }
        func attach(_ block: BlockHarness) { document.addSubview(block.view); block.updateListeners() }
        func post() { NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView) }
        deinit { window.contentView = nil; window.close() }
    }

    func testPlainAndQuotedTextDoNotReceivePlaybackNotifications() {
        for quoted in [false, true] {
            let host = Host()
            let old = makeLegacyBlock(quoted: quoted)
            old.update(layout(quoted: quoted))
            host.attach(old)
            PlaybackCounters.calls = 0
            host.post()
            XCTAssertEqual(PlaybackCounters.calls, 1)
            old.view.removeFromSuperview(); old.updateListeners()
            let current = makeCurrentBlock(quoted: quoted)
            current.update(layout(quoted: quoted))
            host.attach(current)
            PlaybackCounters.calls = 0
            for _ in 0..<100 { host.post() }
            XCTAssertEqual(PlaybackCounters.calls, 0)
        }
    }

    func testMediaReplacementReattachesAndClearsObserversWithoutDuplicates() {
        for quoted in [false, true] {
            let host = Host(), block = makeCurrentBlock(quoted: quoted)
            block.update(layout(quoted: quoted))
            host.attach(block)
            for media in [1, 1, 2, 0, 3, 1, 0, 2] {
                block.update(layout(quoted: quoted, media: media))
                let expected = media == 1 || media == 2 ? 1 : 0
                XCTAssertEqual(block.mediaLayers.count, expected)
                PlaybackCounters.calls = 0
                PlaybackCounters.layers = 0
                host.post()
                XCTAssertEqual(PlaybackCounters.calls, expected, "quoted=\(quoted), media=\(media)")
                XCTAssertEqual(PlaybackCounters.layers, expected)
                for _ in 0..<5 { block.updateListeners() }
                PlaybackCounters.calls = 0
                host.post()
                XCTAssertEqual(PlaybackCounters.calls, expected)
            }
            block.view.removeFromSuperview(); block.updateListeners()
            PlaybackCounters.calls = 0
            host.post()
            XCTAssertEqual(PlaybackCounters.calls, 0)
        }
    }

    func testPlaybackTracksVisibilityKeyWindowAndLiteMode() throws {
        for quoted in [false, true] {
            let host = Host(), block = makeCurrentBlock(quoted: quoted)
            block.update(layout(quoted: quoted, media: 1))
            host.attach(block)
            host.document.layoutSubtreeIfNeeded()
            let layer = try XCTUnwrap(block.mediaLayers.first as? InlineStickerItemLayer)
            XCTAssertFalse(layer.isPlayable)
            host.window.active = true
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: host.window)
            XCTAssertTrue(layer.isPlayable)
            host.scroll.contentView.scroll(to: NSPoint(x: 0, y: 800))
            host.post()
            XCTAssertFalse(layer.isPlayable)
            host.scroll.contentView.scroll(to: .zero)
            host.post()
            XCTAssertTrue(layer.isPlayable)
            block.context.lite = true
            block.update(layout(quoted: quoted, media: 1))
            XCTAssertFalse(layer.isPlayable)
            block.context.lite = false
            block.update(layout(quoted: quoted, media: 1))
            XCTAssertTrue(layer.isPlayable)
            host.window.active = false
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: host.window)
            XCTAssertFalse(layer.isPlayable)
        }
    }

    func testNoObserverIsAllocatedForBlocksWithoutMedia() {
        for quoted in [false, true] {
            let current = makeCurrentBlock(quoted: quoted)
            func hasObserver() -> Bool {
                let value = Mirror(reflecting: current.owner).children.first { $0.label == "animatableContentObserver" }!.value
                return !Mirror(reflecting: value).children.isEmpty
            }
            current.update(layout(quoted: quoted))
            XCTAssertFalse(hasObserver())
            current.update(layout(quoted: quoted, media: 1))
            XCTAssertTrue(hasObserver())
            current.update(layout(quoted: quoted))
            XCTAssertFalse(hasObserver())
        }
    }

    func testReparentingAndDestructionStopOldWindowCallbacks() {
        for quoted in [false, true] {
            let first = Host(), second = Host()
            weak var owner: AnyObject?
            autoreleasepool {
                var block: BlockHarness? = makeCurrentBlock(quoted: quoted)
                block!.update(layout(quoted: quoted, media: 1))
                first.attach(block!)
                second.attach(block!)
                PlaybackCounters.calls = 0
                first.post()
                XCTAssertEqual(PlaybackCounters.calls, 0)
                second.post()
                XCTAssertEqual(PlaybackCounters.calls, 1)
                owner = block!.owner
                block!.view.removeFromSuperview(); block!.updateListeners()
                block = nil
            }
            XCTAssertNil(owner)
            PlaybackCounters.calls = 0
            first.post(); second.post()
            XCTAssertEqual(PlaybackCounters.calls, 0)
        }
    }
}
