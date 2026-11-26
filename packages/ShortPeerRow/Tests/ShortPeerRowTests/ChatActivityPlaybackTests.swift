import XCTest
import AppKit
import TGUIKit
import TelegramTheme
@testable import ShortPeerRow

final class ChatActivityPlaybackTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    func testTypingIndicatorFreezesOutsideAKeyWindow() {
        let view = ChatActivitiesView()
        view.setFrameSize(NSSize(width: 100, height: 20))
        view.startAnimation(.text, theme: ActivitiesTheme(textColor: .black, backgroundColor: .white))

        let window = NSWindow(contentRect: NSMakeRect(0, 0, 200, 40), styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = NSView(frame: NSMakeRect(0, 0, 200, 40))
        window.contentView?.addSubview(view)
        XCTAssertTrue(view.isIndicatorPlaying)

        view.removeFromSuperview()
        XCTAssertFalse(view.isIndicatorPlaying)

        let titled = NSWindow(contentRect: NSMakeRect(0, 0, 200, 40), styleMask: [.titled], backing: .buffered, defer: true)
        titled.contentView?.addSubview(view)
        XCTAssertFalse(titled.isKeyWindow)
        XCTAssertFalse(view.isIndicatorPlaying)
    }

    func testStoppedIndicatorCanRestartWithSameTypeAndTheme() {
        let view = ChatActivitiesView()
        view.setFrameSize(NSSize(width: 100, height: 20))
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 200, 40), styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView?.addSubview(view)
        let theme = ActivitiesTheme(textColor: .black, backgroundColor: .white)
        view.startAnimation(.text, theme: theme)
        XCTAssertTrue(view.isIndicatorPlaying)
        view.stopAnimation()
        XCTAssertFalse(view.isIndicatorPlaying)
        view.startAnimation(.text, theme: theme)
        XCTAssertTrue(view.isIndicatorPlaying)
        view.removeFromSuperview()
    }
}
