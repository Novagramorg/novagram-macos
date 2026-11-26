import XCTest
import AppKit
import TGUIKit
@testable import ChatUI

final class ChatRowViewTreeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
        if !ChatMediaUIHooks.isInstalled {
            ChatMediaUIHooks.install(.placeholder)
        }
    }

    func testMessageRowStartsWithoutTheSwipeHolder() {
        let row = ChatRowView(frame: NSMakeRect(0, 0, 400, 60))
        XCTAssertEqual(row.subviews.count, 1)
        XCTAssertTrue(row.subviews.first === row.rowView)
    }

    func testRevealWithoutAnItemKeepsTheSwipeHolderDetached() {
        let row = ChatRowView(frame: NSMakeRect(0, 0, 400, 60))
        row.initRevealState()
        row.moveReveal(delta: -30)
        row.completeReveal(direction: .none)
        XCTAssertEqual(row.subviews.count, 1)
        XCTAssertFalse(row.hasRevealState)
    }

    func testServiceRowStartsWithItsTextOnly() {
        let row = ChatServiceRowView(frame: NSMakeRect(0, 0, 400, 40))
        XCTAssertEqual(viewClassNames(row.subviews), ["TextView"])
    }

    func testServiceRowRevealWithoutAnItemKeepsTheSwipeHolderDetached() {
        let row = ChatServiceRowView(frame: NSMakeRect(0, 0, 400, 40))
        row.initRevealState()
        XCTAssertEqual(viewClassNames(row.subviews), ["TextView"])
    }

    func testAvatarHoldsOnlyTheAvatarControl() {
        let avatar = ChatAvatarView(frame: NSMakeRect(0, 0, 36, 36))
        XCTAssertEqual(viewClassNames(avatar.subviews), ["AvatarStoryControl"])
    }

    func testVoiceContentSkipsTheUnusedTextView() {
        let content = ChatVoiceContentView(frame: NSMakeRect(0, 0, 240, 40))
        XCTAssertFalse(content.subviews.contains(where: { $0 === content.textView }))
        XCTAssertTrue(content.subviews.contains(where: { $0 === content.durationView }))
        XCTAssertTrue(content.subviews.contains(where: { $0 === content.progressView }))
        XCTAssertTrue(content.subviews.contains(where: { $0 === content.waveformView }))
    }

    func testMusicContentKeepsItsTextView() {
        let content = ChatMusicContentView(frame: NSMakeRect(0, 0, 240, 40))
        XCTAssertTrue(content.subviews.contains(where: { $0 === content.textView }))
    }
}
