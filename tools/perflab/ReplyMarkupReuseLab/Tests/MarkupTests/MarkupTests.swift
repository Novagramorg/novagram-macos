import Cocoa
import XCTest
import TGUIKit

final class MarkupTests: XCTestCase {
    override func setUp() {
        TGUIKitTestBootstrap.install()
        GeneralRowsHooks.shared = GeneralRowsHooks()
        TelegramUtilsHooks.shared = TelegramUtilsHooks()
    }
    private func rows(_ count: Int, action: ReplyMarkupButton.Action = .callback, prefix: String = "Button", embedded: Bool = false) -> [ReplyMarkupRow] {
        [.init(buttons: (0..<count).map { .init(title: "\(prefix) \($0)", action: action, embedded: embedded) })]
    }
    private func bind(_ rows: [ReplyMarkupRow], _ host: View, _ interactions: ReplyMarkupInteractions, radius: CGFloat = 0, top: Bool = true, theme: TelegramPresentationTheme = .init(), input: Bool = false, width: CGFloat = 300) -> CandidateReplyMarkupNode {
        let node = CandidateReplyMarkupNode(rows, [], interactions, theme, host, input, outerCornerRadius: radius, roundsTopCorners: top)
        node.measureSize(width)
        node.redraw()
        node.layout()
        host.setFrameSize(NSSize(width: width, height: node.size.height))
        host.layoutSubtreeIfNeeded()
        return node
    }
    func testRepeatedRedrawRetainsButtonsIconsAndInlineRenderer() throws {
        let host = ReplyMarkupContainerView()
        let interactions = ReplyMarkupInteractions()
        var renderers = 0
        GeneralRowsHooks.shared.makeInlineTextRenderer = { renderers += 1; return RendererFixture() }
        let node = bind(rows(3, action: .url("https://example.com"), embedded: true), host, interactions)
        let buttons = host.subviews
        let icons = buttons.map { $0.subviews.first { $0 is ImageView }! }
        for _ in 0..<100 { node.redraw(); node.layout() }
        XCTAssertEqual(renderers, 3)
        for i in 0..<3 {
            XCTAssertTrue(host.subviews[i] === buttons[i])
            XCTAssertTrue(host.subviews[i].subviews.first { $0 is ImageView } === icons[i])
        }
    }
    func testNewModelChangesActionAndRemovesObsoleteButtons() throws {
        let host = ReplyMarkupContainerView()
        let interactions = ReplyMarkupInteractions()
        let old = bind(rows(3, action: .copyText, prefix: "Old"), host, interactions, radius: 16, top: false)
        let buttons = host.subviews as! [InteractiveTextView]
        let next = bind(rows(2, prefix: "New"), host, interactions)
        XCTAssertTrue(host.subviews[0] === buttons[0])
        XCTAssertEqual(host.subviews.count, 2)
        XCTAssertTrue(buttons[0].subviews.filter { $0 is ImageView }.isEmpty)
        XCTAssertNil(buttons[0].layer?.mask)
        XCTAssertEqual(buttons[0].layer?.cornerRadius, .cornerRadius)
        buttons[0].send(event: .Click)
        buttons[2].send(event: .Click)
        XCTAssertEqual(interactions.actions, ["New 0"])
        XCTAssertNil(buttons[2].superview)
        withExtendedLifetime([old, next]) {}
    }
    func testAccountChangeReplacesButtonsButSameAccountContextReuses() {
        let host = ReplyMarkupContainerView()
        let account = FixtureAccount()
        let first = bind(rows(1), host, ReplyMarkupInteractions(FixtureContext(account: account)))
        let original = host.subviews[0]
        let second = bind(rows(1), host, ReplyMarkupInteractions(FixtureContext(account: account)))
        XCTAssertTrue(host.subviews[0] === original)
        let third = bind(rows(1), host, ReplyMarkupInteractions())
        XCTAssertFalse(host.subviews[0] === original)
        withExtendedLifetime([first, second, third]) {}
    }
    func testPressedAndAnimatingButtonsAreReplaced() {
        let host = ReplyMarkupContainerView()
        let interactions = ReplyMarkupInteractions()
        let first = bind(rows(2), host, interactions)
        let buttons = host.subviews as! [InteractiveTextView]
        buttons[0].controlState = .Highlight
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.duration = 10
        buttons[1].layer?.add(animation, forKey: "pending")
        let next = bind(rows(2, prefix: "New"), host, interactions)
        for i in 0..<2 { XCTAssertFalse(host.subviews[i] === buttons[i]); buttons[i].send(event: .Click) }
        XCTAssertTrue(interactions.actions.isEmpty)
        withExtendedLifetime([first, next]) {}
    }
    func testPlainHostStillReconstructsAndEmptyMarkupClears() {
        let host = View()
        let interactions = ReplyMarkupInteractions()
        let node = bind(rows(2), host, interactions)
        let first = host.subviews[0]
        node.redraw()
        XCTAssertFalse(host.subviews[0] === first)
        let empty = bind([], host, interactions)
        XCTAssertTrue(host.subviews.isEmpty)
        withExtendedLifetime([node, empty]) {}
    }
    func testRendererClearsOnPlainAndLiteStateRefreshes() {
        let host = ReplyMarkupContainerView()
        let context = FixtureContext()
        let interactions = ReplyMarkupInteractions(context)
        let recorder = RendererFixture()
        GeneralRowsHooks.shared.makeInlineTextRenderer = { recorder }
        let initial = bind(rows(1, embedded: true), host, interactions)
        context.lite = true
        initial.redraw()
        XCTAssertTrue((host.subviews[0] as! InteractiveTextView).isLite)
        let plain = bind(rows(1), host, interactions)
        XCTAssertGreaterThan(recorder.clears, 0)
        XCTAssertNil(recorder.lastLayout)
        withExtendedLifetime([initial, plain]) {}
    }
    func testGeometryAndPixelsMatchAfterRebinding() {
        let interactions = ReplyMarkupInteractions()
        for scale: CGFloat in [1, 2, 3] {
            for mode in 0..<3 {
                let oldHost = View()
                let newHost = ReplyMarkupContainerView()
                let previous = bind(rows(4, action: .copyText), newHost, interactions, radius: 18, top: false)
                let data = [ReplyMarkupRow(buttons: [.init(title: "مرحبا بالعالم", action: .url("link")), .init(title: "👋 Hello", action: .callback)]), ReplyMarkupRow(buttons: [.init(title: "你好 世界", action: .copyText, style: .blue)])]
                let theme = TelegramPresentationTheme()
                let radius: CGFloat = mode == 0 ? 0 : 16
                let native = ReferenceReplyMarkupNode(data, [], interactions, theme, oldHost, mode == 1, outerCornerRadius: radius, roundsTopCorners: mode == 1)
                native.measureSize(280)
                native.redraw()
                native.layout()
                oldHost.setFrameSize(NSSize(width: 280, height: native.size.height))
                let candidate = bind(data, newHost, interactions, radius: radius, top: mode == 1, theme: theme, input: mode == 1, width: 280)
                XCTAssertEqual(oldHost.subviews.map(\.frame), newHost.subviews.map(\.frame))
                let a = ViewSnapshot.render(oldHost, scale: scale)
                let b = ViewSnapshot.render(newHost, scale: scale)
                XCTAssertEqual(a.differingPixels(from: b, tolerance: 0), 0, "mode \(mode), scale \(scale)")
                XCTAssertTrue(b.bytes.contains { $0 != 0 })
                withExtendedLifetime([previous, candidate, native]) {}
            }
        }
    }
    func testGrowthAndIconTransitionsReuseOnlyExistingSlots() {
        let host = ReplyMarkupContainerView()
        let interactions = ReplyMarkupInteractions()
        let first = bind(rows(1), host, interactions)
        let button = host.subviews[0]
        let second = bind(rows(4, action: .copyText), host, interactions)
        XCTAssertTrue(host.subviews[0] === button)
        XCTAssertEqual(host.subviews.count, 4)
        XCTAssertEqual(button.subviews.filter { $0 is ImageView }.count, 1)
        second.redraw()
        XCTAssertEqual(button.subviews.filter { $0 is ImageView }.count, 1)
        let last = bind([], host, interactions)
        XCTAssertTrue(host.subviews.isEmpty)
        withExtendedLifetime([first, second, last]) {}
    }
    func testBlurAndStyledBackgroundTransitions() {
        let host = ReplyMarkupContainerView()
        let interactions = ReplyMarkupInteractions()
        var theme = TelegramPresentationTheme()
        theme.shouldBlurService = true
        let first = bind(rows(1), host, interactions, theme: theme)
        let button = host.subviews[0] as! InteractiveTextView
        XCTAssertTrue(button.hasBackground)
        let styled = [ReplyMarkupRow(buttons: [.init(title: "Styled", action: .callback, style: .blue)])]
        let second = bind(styled, host, interactions, theme: theme)
        XCTAssertTrue(host.subviews[0] === button)
        XCTAssertFalse(button.hasBackground)
        XCTAssertEqual(button.backgroundColor, .blue)
        let third = bind(rows(1), host, interactions, theme: theme)
        XCTAssertTrue(button.hasBackground)
        XCTAssertEqual(button.backgroundColor, .clear)
        withExtendedLifetime([first, second, third]) {}
    }
    func testAttachedRendererSurvivesReuseAndStopsWhenRemoved() {
        let host = ReplyMarkupContainerView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView!.addSubview(host)
        let interactions = ReplyMarkupInteractions()
        let recorder = RendererFixture()
        GeneralRowsHooks.shared.makeInlineTextRenderer = { recorder }
        let first = bind(rows(1, embedded: true), host, interactions)
        let button = host.subviews[0]
        let calls = recorder.playbackCalls
        let second = bind(rows(1, embedded: true), host, interactions)
        XCTAssertTrue(host.subviews[0] === button)
        XCTAssertGreaterThan(recorder.playbackCalls, calls)
        recorder.playable = true
        let empty = bind([], host, interactions)
        XCTAssertFalse(recorder.playable)
        XCTAssertNil(button.window)
        window.close()
        withExtendedLifetime([first, second, empty]) {}
    }
    func testRemovedNodeAndButtonsRelease() {
        weak var weakNode: CandidateReplyMarkupNode?
        weak var weakButton: NSView?
        autoreleasepool {
            let host = ReplyMarkupContainerView()
            let interactions = ReplyMarkupInteractions()
            var node: CandidateReplyMarkupNode? = bind(rows(1), host, interactions)
            weakNode = node
            weakButton = host.subviews[0]
            node = nil
            let empty = bind([], host, interactions)
            CATransaction.flush()
            withExtendedLifetime(empty) {}
        }
        XCTAssertNil(weakNode)
        XCTAssertNil(weakButton)
    }
}
