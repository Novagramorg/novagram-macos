import XCTest
import AppKit
@testable import ChatUI

final class ChatMessageAccessibilityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
        applyMacEnglishStrings()
    }

    private func make(_ kind: ChatMessageAccessibility.Kind, incoming: Bool = true, author: String? = "Bob", group: Bool = false, caption: String? = nil, status: ChatMessageAccessibility.Status = .none, reply: ChatMessageAccessibility.Reply? = nil, forward: ChatMessageAccessibility.Forward? = nil, selected: Bool? = nil) -> ChatMessageAccessibility {
        return ChatMessageAccessibility(kind: kind, isIncoming: incoming, authorName: author, announceAuthor: group, caption: caption, date: "Oct 10, 2026 at 10:00", status: status, reply: reply, forward: forward, isSelected: selected, pluralRecipients: group)
    }

    func testTextMessageReadsAuthorTextAndDate() {
        let message = make(.text("Hello"))
        XCTAssertEqual(message.label, "Bob")
        XCTAssertEqual(message.value, "Hello\nOct 10, 2026 at 10:00")
        XCTAssertNil(message.help)
    }

    func testOutgoingTextIsYourMessageWithStatus() {
        let message = make(.text("Hi"), incoming: false, status: .sent(read: true, played: nil))
        XCTAssertEqual(message.label, "Your message")
        XCTAssertEqual(message.value, "Hi\nOct 10, 2026 at 10:00\nSeen by recipient")
        XCTAssertEqual(make(.text("Hi"), incoming: false, status: .sending).value, "Hi\nOct 10, 2026 at 10:00\nSending")
        XCTAssertEqual(make(.text("Hi"), incoming: false, status: .failed).value, "Hi\nOct 10, 2026 at 10:00\nFailed to send")
    }

    func testMediaKindsNameTheSenderOnlyInGroups() {
        XCTAssertEqual(make(.photo, group: true).label, "Photo, from: Bob")
        XCTAssertEqual(make(.photo).label, "Photo")
        XCTAssertEqual(make(.photo, incoming: false).label, "Your photo")
        XCTAssertEqual(make(.photo, caption: "Sunset").value, "Caption: Sunset\nOct 10, 2026 at 10:00")
    }

    func testVoiceMessageReadsDurationPlayStateAndHint() {
        let message = make(.voice(duration: 65), incoming: false, status: .sent(read: true, played: false))
        XCTAssertEqual(message.label, "Your voice message")
        XCTAssertTrue(message.value.hasPrefix("Duration: 1 minute, 5 seconds\n"))
        XCTAssertTrue(message.value.hasSuffix("Seen by recipient, Not played by recipient"))
        XCTAssertEqual(message.help, "Press to play")
    }

    func testFileMusicAndSticker() {
        XCTAssertEqual(make(.file(name: "report.pdf", size: 2_048_000)).value.components(separatedBy: "\n").first, "report.pdf. Size: 2 MB")
        XCTAssertEqual(make(.music(title: "Song", performer: nil, duration: nil)).value.components(separatedBy: "\n").first, "Song, by Unknown")
        XCTAssertEqual(make(.sticker(emoji: "😀")).label, "Sticker")
        XCTAssertEqual(make(.sticker(emoji: "😀")).value.components(separatedBy: "\n").first, "😀")
    }

    func testPollReadsQuestionOptionsAndVotes() {
        let options = [ChatMessageAccessibility.PollOption(text: "Yes", selected: true, percent: 75), ChatMessageAccessibility.PollOption(text: "No", selected: false, percent: 25)]
        let message = make(.poll(question: "Lunch?", anonymous: true, options: options, votes: 4, closed: true))
        XCTAssertEqual(message.label, "Anonymous poll")
        XCTAssertEqual(message.value.components(separatedBy: "\n").first, "Title: Lunch?. 2 options: Yes, selected, 75%, No, 25%. 4 votes. Final results")
        XCTAssertEqual(make(.poll(question: "Q", anonymous: false, options: [], votes: 0, closed: false)).label, "Poll")
    }

    func testReplyAndForwardPrefixes() {
        let reply = ChatMessageAccessibility.Reply(authorName: "Alice", isIncoming: true, text: "Where?")
        let message = make(.text("Here"), reply: reply, forward: .from("News"))
        XCTAssertEqual(message.label, "Forwarded from: News. Reply to message from: Alice. Bob")
        XCTAssertTrue(message.value.hasSuffix("In reply to message: Where?"))
        XCTAssertEqual(make(.text("x"), reply: .init(authorName: nil, isIncoming: false, text: "y")).label, "Reply to your message. Bob")
        XCTAssertEqual(make(.text("x"), forward: .you).label, "Forwarded from you. Bob")
    }

    func testSelectionStateIsReadFirstAndHidesHints() {
        let message = make(.voice(duration: 5), selected: true)
        XCTAssertEqual(message.value.components(separatedBy: "\n").first, "Selected")
        XCTAssertNil(message.help)
    }
}
