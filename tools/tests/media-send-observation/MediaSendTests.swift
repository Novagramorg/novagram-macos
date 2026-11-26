import Foundation
import XCTest
import SwiftSignalKit

struct PeerId: Equatable { let namespace: Int32 }
enum Namespaces { enum Peer { static let SecretChat: Int32 = -1, CloudUser: Int32 = 1 } }
typealias MessageId = Int
typealias ItemCollectionId = Int
typealias EngineMessageReplySubject = Int
typealias StoryId = Int
typealias StarsAmount = Int
protocol MessageAttribute {}
struct ParsingType: OptionSet {
    let rawValue: Int
    static let Hashtags = Self(rawValue: 1), Links = Self(rawValue: 2)
}
struct TextEntitiesMessageAttribute: MessageAttribute {
    let entities: [Int]
    init(entities: [Int]) { self.entities = entities }
}
struct NotificationInfoMessageAttribute: MessageAttribute {
    struct Flags: OptionSet { let rawValue: Int; static let muted = Self(rawValue: 1) }
    let flags: Flags
}
struct OutgoingScheduleInfoMessageAttribute: MessageAttribute { let scheduleTime: Int32; let repeatPeriod: Int32? }
struct SendAsMessageAttribute: MessageAttribute { let peerId: PeerId }
struct EmojiSearchQueryMessageAttribute: MessageAttribute { let query: String }
struct PaidStarsMessageAttribute: MessageAttribute { let stars: StarsAmount; let postponeSending: Bool }
struct MediaSpoilerMessageAttribute: MessageAttribute {}
struct EffectMessageAttribute: MessageAttribute { let id: Int }
struct InvertMediaMessageAttribute: MessageAttribute {}
enum AvailableMessageEffects { struct MessageEffect { let id: Int } }
enum ChatInterfaceState { struct ChannelSuggestPost { let attribute: MessageAttribute? } }
final class Media { let isInteractiveMedia: Bool; init(_ interactive: Bool = false) { isInteractiveMedia = interactive } }
enum AnyMediaReference { case standalone(media: Media) }
struct ChatTextInputState {
    let inputText: String
    var attributes: [Int] = []
    var inlineMedia: [Int: Int] = [:]
    var upstairCollections: [Int] = []
    init(inputText: String = "") { self.inputText = inputText }
    func messageTextEntities(_ parsing: ParsingType, extractDates: Bool) -> [Int] { [] }
    func subInputState(from range: NSRange) -> Self { Self(inputText: (inputText as NSString).substring(with: range)) }
}
extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var length: Int { (self as NSString).length }
}
func cut_long_message(_ text: String, _ limit: Int) -> [String] {
    stride(from: 0, to: text.length, by: limit).map { (text as NSString).substring(with: NSRange(location: $0, length: min(limit, text.length - $0))) }
}
struct EnqueueMessage {
    let text: String
    let attributes: [MessageAttribute]
    let media: AnyMediaReference?
    let group: UInt64?
    let reply: EngineMessageReplySubject?
    let story: StoryId?
    let thread: Int64?
    static func message(text: String, attributes: [MessageAttribute], inlineStickers: [Int: Int], mediaReference: AnyMediaReference?, threadId: Int64?, replyToMessageId: EngineMessageReplySubject?, replyToStoryId: StoryId?, localGroupingKey: UInt64?, correlationId: Int64?, bubbleUpEmojiOrStickersets: [Int]) -> Self {
        Self(text: text, attributes: attributes, media: mediaReference, group: localGroupingKey, reply: replyToMessageId, story: replyToStoryId, thread: threadId)
    }
}
struct StickerSettings { var dynamicPackOrder = false }
final class Account {}
protocol AccountContextProtocol { var account: Account { get }; var stickerSettings: StickerSettings { get } }
final class AccountContext: AccountContextProtocol { let account = Account(); let stickerSettings = StickerSettings() }
protocol ChatCustomContentsProtocol { func enqueueMessages(messages: [EnqueueMessage]) -> Signal<[MessageId?], NoError> }
final class CustomContents: ChatCustomContentsProtocol {
    var messages: [EnqueueMessage] = []
    var result: Signal<[MessageId?], NoError> = .complete()
    func enqueueMessages(messages: [EnqueueMessage]) -> Signal<[MessageId?], NoError> { self.messages = messages; return result }
}
enum FastSettings { static func isChannelMessagesMuted(_ id: PeerId) -> Bool { false } }
func arc4random64() -> UInt64 { 19 }
enum Backend {
    static var messages: [EnqueueMessage] = []
    static var result: Signal<[MessageId?], NoError> = .complete()
    static var calls = 0
}
func enqueueMessages(account: Account, peerId: PeerId, messages: [EnqueueMessage]) -> Signal<[MessageId?], NoError> {
    Backend.calls += 1; Backend.messages = messages; return Backend.result
}
enum Sender {
__MEDIA_SEND__
}
final class MediaSendTests: XCTestCase {
    let context = AccountContext()
    let peer = PeerId(namespace: 1)
    override func setUp() { Backend.messages = []; Backend.calls = 0; Backend.result = .complete() }
    func testAlbumCaptionAndSplitAdditionalTextDetermineExpectedCount() {
        Backend.result = .single([1, 2, 3, 4, 5])
        var count: Int?, ids: [MessageId?] = []
        let disposable = Sender.enqueue(media: [Media(), Media(), Media()], caption: .init(inputText: "caption"), context: context, peerId: peer, replyId: 7, threadId: 9, isCollage: true, additionText: .init(inputText: String(repeating: "x", count: 4100)), observedResult: { count = $0; ids = $1 }).start()
        XCTAssertEqual(count, 5); XCTAssertEqual(ids, [1, 2, 3, 4, 5])
        XCTAssertEqual(Backend.messages.map { $0.text.length }, [4096, 4, 0, 0, 7])
        XCTAssertTrue(Backend.messages.prefix(2).allSatisfy { $0.group == nil })
        XCTAssertTrue(Backend.messages.suffix(3).allSatisfy { $0.group == 19 })
        XCTAssertTrue(Backend.messages.allSatisfy { $0.reply == 7 && $0.thread == 9 }); disposable.dispose()
    }
    func testPartialAndMismatchedResultsKeepExpectedCount() {
        for result: [MessageId?] in [[1, nil], [1], [], [1, 2, 3]] {
            Backend.result = .single(result)
            var expected: Int?, actual: [MessageId?]?
            let disposable = Sender.enqueue(media: [Media(), Media()], caption: .init(), context: context, peerId: peer, replyId: nil, threadId: nil, observedResult: { expected = $0; actual = $1 }).start()
            XCTAssertEqual(expected, 2); XCTAssertEqual(actual!, result); disposable.dispose()
        }
    }
    func testDuplicateMetadataResultsAreObservedOnlyOnce() {
        var subscriber: Subscriber<[MessageId?], NoError>?
        Backend.result = Signal { subscriber = $0; return EmptyDisposable }
        var observations = 0
        let disposable = Sender.enqueue(media: Media(), context: context, peerId: peer, replyId: nil, threadId: nil, observedResult: { _, _ in observations += 1 }).start()
        subscriber?.putNext([1]); subscriber?.putNext([2]); subscriber = nil
        XCTAssertEqual(observations, 1); disposable.dispose()
    }
    func testNoResultAndDisposalDoNotInventCallback() {
        var observed = false
        let empty = Sender.enqueue(media: [Media()], caption: .init(), context: context, peerId: peer, replyId: nil, threadId: nil, observedResult: { _, _ in observed = true }).start()
        var subscriber: Subscriber<[MessageId?], NoError>?
        Backend.result = Signal { subscriber = $0; return EmptyDisposable }
        let pending = Sender.enqueue(media: [Media()], caption: .init(), context: context, peerId: peer, replyId: nil, threadId: nil, observedResult: { _, _ in observed = true }).start()
        pending.dispose(); subscriber?.putNext([1]); subscriber = nil; empty.dispose()
        XCTAssertFalse(observed)
    }
    func testSingleMediaOverloadsPreserveRecurrenceAndReplyFields() {
        Backend.result = .single([1])
        for observed in [false, true] {
            let signal: Signal<[MessageId?], NoError>
            if observed {
                signal = Sender.enqueue(media: Media(), context: context, peerId: peer, replyId: 7, threadId: 9, replyStoryId: 11, silent: true, atDate: Date(timeIntervalSince1970: 100), repeatPeriod: 60, observedResult: { count, ids in XCTAssertEqual(count, 1); XCTAssertEqual(ids, [1]) })
            } else {
                signal = Sender.enqueue(media: Media(), context: context, peerId: peer, replyId: 7, threadId: 9, replyStoryId: 11, silent: true, atDate: Date(timeIntervalSince1970: 100), repeatPeriod: 60)
            }
            let disposable = signal.start()
            let message = Backend.messages[0]
            let schedule = message.attributes.compactMap { $0 as? OutgoingScheduleInfoMessageAttribute }.first
            XCTAssertEqual(schedule?.repeatPeriod, 60); XCTAssertEqual(schedule?.scheduleTime, 100)
            XCTAssertEqual(message.reply, 7); XCTAssertEqual(message.story, 11); XCTAssertEqual(message.thread, 9)
            XCTAssertTrue(message.attributes.contains { $0 is NotificationInfoMessageAttribute }); disposable.dispose()
        }
    }
    func testLegacyArrayOverloadPreservesPayloadAndResult() {
        Backend.result = .single([1, 2])
        var received: [MessageId?]?
        let disposable = Sender.enqueue(media: [Media(), Media()], caption: .init(inputText: "caption"), context: context, peerId: peer, replyId: nil, threadId: nil, isCollage: true, silent: true, atDate: Date(timeIntervalSince1970: 100), repeatPeriod: 60, sendAsPeerId: peer, query: "synthetic", collectionId: 1, isSpoiler: true, messageEffect: .init(id: 3), leadingText: true, sendPaidMessageStars: 4).start(next: { received = $0 })
        XCTAssertEqual(received!, [1, 2]); XCTAssertEqual(Backend.messages.last?.text, "caption")
        XCTAssertTrue(Backend.messages[0].attributes.contains { $0 is MediaSpoilerMessageAttribute })
        XCTAssertTrue(Backend.messages[0].attributes.contains { $0 is EffectMessageAttribute })
        XCTAssertTrue(Backend.messages[0].attributes.contains { $0 is InvertMediaMessageAttribute }); disposable.dispose()
    }
    func testInteractiveMediaConsumesCaptionOnce() {
        Backend.result = .single([1, 2])
        let disposable = Sender.enqueue(media: [Media(true), Media()], caption: .init(inputText: "caption"), context: context, peerId: peer, replyId: nil, threadId: nil).start()
        XCTAssertEqual(Backend.messages.map { $0.text }, ["caption", ""]); disposable.dispose()
    }
    func testCustomContentsUsesOwnBackendWithActualExpectedCount() {
        let custom = CustomContents(); custom.result = .single([1, 2])
        var expected: Int?
        let disposable = Sender.enqueue(media: [Media()], caption: .init(), context: context, peerId: peer, replyId: nil, threadId: nil, additionText: .init(inputText: "extra"), customChatContents: custom, observedResult: { count, _ in expected = count }).start()
        XCTAssertEqual(Backend.calls, 0); XCTAssertEqual(custom.messages.count, 2); XCTAssertEqual(expected, 2); disposable.dispose()
    }
    func testEmptyBatchReportsZeroExpectedWithoutCreatingMedia() {
        Backend.result = .single([]); var expected: Int?
        let disposable = Sender.enqueue(media: [], caption: .init(), context: context, peerId: peer, replyId: nil, threadId: nil, observedResult: { count, _ in expected = count }).start()
        XCTAssertEqual(expected, 0); XCTAssertTrue(Backend.messages.isEmpty); disposable.dispose()
    }
}
