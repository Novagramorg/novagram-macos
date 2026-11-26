import XCTest
import AppKit
import TGUIKit
@testable import ChatListUI

final class ChatListAccessibilityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
        applyMacEnglishStrings()
    }

    func testLabelIsTheNameWithUnreadCount() {
        XCTAssertEqual(ChatListRowItem.accessibilityLabel(title: "Alice", unreadCount: 0), "Alice")
        XCTAssertEqual(ChatListRowItem.accessibilityLabel(title: "Alice", unreadCount: 3), "Alice\n3 unread messages")
        XCTAssertEqual(ChatListRowItem.accessibilityLabel(title: "Alice", unreadCount: 1), "Alice\n1 unread message")
        XCTAssertNil(ChatListRowItem.accessibilityLabel(title: "", unreadCount: 2))
    }

    func testIncomingGroupMessageNamesTheSender() {
        let value = ChatListRowItem.accessibilityValue(isArchive: false, hasMessage: true, incoming: true, author: "Bob ", read: false, preview: "See you at 6")
        XCTAssertEqual(value, "Message\nFrom: Bob\nSee you at 6")
    }

    func testOutgoingReadMessage() {
        let value = ChatListRowItem.accessibilityValue(isArchive: false, hasMessage: true, incoming: false, author: "You", read: true, preview: "Photo")
        XCTAssertEqual(value, "Outgoing Message\nRead\nPhoto")
    }

    func testEmptyChatAndArchive() {
        XCTAssertEqual(ChatListRowItem.accessibilityValue(isArchive: false, hasMessage: false, incoming: false, author: nil, read: false, preview: nil), "Empty")
        XCTAssertEqual(ChatListRowItem.accessibilityValue(isArchive: true, hasMessage: true, incoming: true, author: nil, read: false, preview: "Channel A, Group B"), "Channel A, Group B")
        XCTAssertNil(ChatListRowItem.accessibilityValue(isArchive: true, hasMessage: false, incoming: false, author: nil, read: false, preview: ""))
    }
}
