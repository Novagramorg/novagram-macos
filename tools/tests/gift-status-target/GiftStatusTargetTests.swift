import Foundation
import SwiftSignalKit
import XCTest

typealias PeerId = Int
struct FileId { let id: Int64 }
final class TelegramMediaFile { let fileId: FileId; let mimeType: String; init(_ id: Int64 = 10, mime: String = "emoji") { fileId = .init(id: id); mimeType = mime } }
struct PeerEmojiStatus {
    enum Content { case emoji(fileId: Int64); case starGift(id: Int64, fileId: Int64, title: String, slug: String, patternFileId: Int64, innerColor: Int32, outerColor: Int32, patternColor: Int32, textColor: Int32) }
    let content: Content
    var fileId: Int64 { switch content { case let .emoji(id): return id; case let .starGift(_, id, _, _, _, _, _, _, _): return id } }
}
class Peer { let id: PeerId; init(_ id: PeerId) { self.id = id } }
final class TelegramUser: Peer { var emojiStatus: PeerEmojiStatus?; init(_ id: PeerId = 1, status: PeerEmojiStatus? = nil) { emojiStatus = status; super.init(id) } }
final class TelegramChannel: Peer { var emojiStatus: PeerEmojiStatus?; init(_ id: PeerId = 20, status: PeerEmojiStatus? = nil) { emojiStatus = status; super.init(id) } }
struct EnginePeer { let peer: Peer; init(_ peer: Peer) { self.peer = peer }; func _asPeer() -> Peer { peer }; var emojiStatus: PeerEmojiStatus? { (peer as? TelegramUser)?.emojiStatus ?? (peer as? TelegramChannel)?.emojiStatus } }
enum StarGift { struct UniqueGift { let id: Int64; let file: TelegramMediaFile? } }
struct Gift { let unique: StarGift.UniqueGift? }
struct ProfileGift { let gift: Gift }
struct Settings { var focusIntentStatusEnabled = true; var focusIntentStatusFallback: Int? = 1 }
final class Postbox { var settings = Settings(); var writes = 0 }
func updateSomeSettingsInteractively(postbox: Postbox, _ update: @escaping (Settings) -> Settings) -> Signal<Void, NoError> { Signal { subscriber in postbox.settings = update(postbox.settings); postbox.writes += 1; subscriber.putCompletion(); return EmptyDisposable } }
struct Call: Equatable { let peerId: PeerId; let fileId: Int64?; let giftId: Int64?; let expirationDate: Int32? }
final class Account { let peerId = 1; let postbox = Postbox() }
final class AccountData {
    var calls: [Call] = []
    func setEmojiStatus(file: TelegramMediaFile?, expirationDate: Int32?) -> Signal<Never, NoError> { Signal { subscriber in self.calls.append(.init(peerId: 1, fileId: file?.fileId.id, giftId: nil, expirationDate: expirationDate)); subscriber.putCompletion(); return EmptyDisposable } }
    func setStarGiftStatus(starGift: StarGift.UniqueGift, expirationDate: Int32?) -> Signal<Never, NoError> { Signal { subscriber in self.calls.append(.init(peerId: 1, fileId: starGift.file?.fileId.id, giftId: starGift.id, expirationDate: expirationDate)); subscriber.putCompletion(); return EmptyDisposable } }
}
final class Peers {
    var calls: [Call] = []
    func updatePeerEmojiStatus(peerId: PeerId, fileId: Int64?, expirationDate: Int32?) -> Signal<Never, NoError> { Signal { subscriber in self.calls.append(.init(peerId: peerId, fileId: fileId, giftId: nil, expirationDate: expirationDate)); subscriber.putCompletion(); return EmptyDisposable } }
    func updatePeerStarGiftStatus(peerId: PeerId, starGift: StarGift.UniqueGift, expirationDate: Int32?) -> Signal<Never, NoError> { Signal { subscriber in self.calls.append(.init(peerId: peerId, fileId: starGift.file?.fileId.id, giftId: starGift.id, expirationDate: expirationDate)); subscriber.putCompletion(); return EmptyDisposable } }
}
final class Engine { let account = Account(); let accountData = AccountData(); let peers = Peers() }
final class Reactions {
    let engine = Engine()
    struct InteractiveStatus { let fileId: Int64?; let previousFileId: Int64?; let rect: NSRect? }
    let _interactiveStatus = Atomic<InteractiveStatus?>(value: nil)
    __REACTIONS__
}
final class Context { let reactions = Reactions(); var timestamp: Int32 = 1_700_000_000 }
enum Source { case quickLook(EnginePeer, StarGift.UniqueGift), previewWear(EnginePeer, StarGift.UniqueGift), other }
struct State {
    var owner: EnginePeer?; var gift: Gift; var source: Source = .other; var converted = false
    __WEARED__
}
struct ListState { let peer: EnginePeer? }
final class Resettable { func reset() {} }
func toggleNft(context: Context, stateValue: Atomic<State>, gift: StarGift.UniqueGift) {
    let wearAction = Resettable()
    let updateState: (@escaping (State) -> State) -> Void = { update in _ = stateValue.modify(update) }
    let action: (StarGift.UniqueGift) -> Void = __NFT_TOGGLE__
    action(gift)
}
func toggleList(context: Context, stateValue: Atomic<ListState>, option: ProfileGift) {
    let action: (ProfileGift) -> Void = __LIST_TOGGLE__
    action(option)
}
func menuWorn(unique: StarGift.UniqueGift, state: ListState) -> Bool {
    __MENU__
}
func status(_ giftId: Int64, file: Int64 = 10) -> PeerEmojiStatus { .init(content: .starGift(id: giftId, fileId: file, title: "gift", slug: "slug", patternFileId: 20, innerColor: 0, outerColor: 0, patternColor: 0, textColor: 0)) }
func gift(_ id: Int64 = 100, file: Int64 = 10) -> StarGift.UniqueGift { .init(id: id, file: TelegramMediaFile(file)) }

final class GiftStatusTargetTests: XCTestCase {
    func apply(_ reactions: Reactions, peer: Peer, gift: StarGift.UniqueGift? = nil, file: TelegramMediaFile = TelegramMediaFile(), timeout: Int32? = nil, timestamp: Int32 = 1_700_000_000, interactive: Bool = true) { reactions.setStatus(file, peer: peer, timestamp: timestamp, timeout: timeout, fromRect: nil, handleInteractive: interactive, starGift: gift) }
    func testDifferentCollectibleWithSameArtworkIsApplied() { let r = Reactions(); apply(r, peer: TelegramUser(status: status(100)), gift: gift(200)); XCTAssertEqual(r.engine.accountData.calls.last?.giftId, 200) }
    func testSameCollectibleWithDifferentArtworkIsRemoved() { let r = Reactions(); apply(r, peer: TelegramUser(status: status(100, file: 99)), gift: gift()); XCTAssertNil(r.engine.accountData.calls.last?.fileId); XCTAssertNil(r.engine.accountData.calls.last?.giftId); XCTAssertEqual(r.engine.accountData.calls.count, 1) }
    func testPlainEmojiWithSameArtworkDoesNotRemoveGift() { let r = Reactions(); apply(r, peer: TelegramUser(status: .init(content: .emoji(fileId: 10))), gift: gift()); XCTAssertEqual(r.engine.accountData.calls.last?.giftId, 100) }
    func testNormalEmojiCanReplaceCollectibleWithSameArtwork() { let r = Reactions(); apply(r, peer: TelegramUser(status: status(100))); XCTAssertEqual(r.engine.accountData.calls.last?.fileId, 10); XCTAssertNil(r.engine.accountData.calls.last?.giftId) }
    func testCollectibleInputIsNotTreatedAsBundleClearItem() { let r = Reactions(); apply(r, peer: TelegramUser(), gift: gift(), file: TelegramMediaFile(mime: "bundle/test")); XCTAssertEqual(r.engine.accountData.calls.last?.giftId, 100) }
    func testSameNormalEmojiTogglesOff() { let r = Reactions(); apply(r, peer: TelegramUser(status: .init(content: .emoji(fileId: 10)))); XCTAssertEqual(r.engine.accountData.calls.count, 1); XCTAssertNil(r.engine.accountData.calls.last?.fileId) }
    func testForeignUserCannotChangeOwnAccount() { let r = Reactions(); apply(r, peer: TelegramUser(30), gift: gift()); XCTAssertTrue(r.engine.accountData.calls.isEmpty); XCTAssertTrue(r.engine.peers.calls.isEmpty); XCTAssertEqual(r.engine.account.postbox.writes, 0); XCTAssertNil(r._interactiveStatus.with { $0 }) }
    func testUnsupportedPeerCannotChangeOwnAccount() { let r = Reactions(); apply(r, peer: Peer(1)); XCTAssertTrue(r.engine.accountData.calls.isEmpty); XCTAssertEqual(r.engine.account.postbox.writes, 0) }
    func testChannelGiftUsesChannelApi() { let r = Reactions(); apply(r, peer: TelegramChannel(20), gift: gift()); XCTAssertEqual(r.engine.peers.calls.last?.peerId, 20); XCTAssertEqual(r.engine.peers.calls.last?.giftId, 100); XCTAssertTrue(r.engine.accountData.calls.isEmpty) }
    func testChannelTakeOffDoesNotChangePersonalStatusOrFocus() { let r = Reactions(); apply(r, peer: TelegramChannel(20, status: status(100)), gift: gift()); XCTAssertEqual(r.engine.peers.calls.count, 1); XCTAssertNil(r.engine.peers.calls.last?.fileId); XCTAssertNil(r.engine.peers.calls.last?.giftId); XCTAssertTrue(r.engine.accountData.calls.isEmpty); XCTAssertEqual(r.engine.account.postbox.writes, 0); XCTAssertTrue(r.engine.account.postbox.settings.focusIntentStatusEnabled); XCTAssertNil(r._interactiveStatus.with { $0 }) }
    func testDifferentChannelGiftWithSameArtworkIsSet() { let r = Reactions(); apply(r, peer: TelegramChannel(20, status: status(100)), gift: gift(200)); XCTAssertEqual(r.engine.peers.calls.last?.giftId, 200) }
    func testChannelNormalEmojiUsesChannelApi() { let r = Reactions(); apply(r, peer: TelegramChannel(20)); XCTAssertEqual(r.engine.peers.calls.last?.fileId, 10); XCTAssertTrue(r.engine.accountData.calls.isEmpty) }
    func testChannelNormalEmojiToggleClearsChannel() { let r = Reactions(); apply(r, peer: TelegramChannel(20, status: .init(content: .emoji(fileId: 10)))); XCTAssertEqual(r.engine.peers.calls.count, 1); XCTAssertNil(r.engine.peers.calls.last?.fileId); XCTAssertTrue(r.engine.accountData.calls.isEmpty) }
    func testZeroTimeoutMeansIndefinite() { let r = Reactions(); apply(r, peer: TelegramUser(), timeout: 0); XCTAssertNil(r.engine.accountData.calls.last?.expirationDate) }
    func testPositiveTimeoutAddsOnce() { let r = Reactions(); apply(r, peer: TelegramUser(), timeout: 60); XCTAssertEqual(r.engine.accountData.calls.last?.expirationDate, 1_700_000_060) }
    func testInvalidTimeoutDoesNotMutate() { for timeout: Int32 in [-1, Int32.max] { let r = Reactions(); apply(r, peer: TelegramUser(), timeout: timeout); XCTAssertTrue(r.engine.accountData.calls.isEmpty); XCTAssertEqual(r.engine.account.postbox.writes, 0) } }
    func testMaximumExpirationIsSafe() { let r = Reactions(); apply(r, peer: TelegramUser(), timeout: 60, timestamp: Int32.max - 60); XCTAssertEqual(r.engine.accountData.calls.last?.expirationDate, Int32.max) }
    func testClearOmitsExpiry() { let r = Reactions(); apply(r, peer: TelegramUser(status: status(100)), gift: gift(), timeout: 60); XCTAssertNil(r.engine.accountData.calls.last?.expirationDate) }
    func testBundleClearKeepsPersonalAnimation() { let r = Reactions(); apply(r, peer: TelegramUser(status: status(100)), file: TelegramMediaFile(mime: "bundle/test")); XCTAssertNil(r.engine.accountData.calls.last?.fileId); XCTAssertNil(r._interactiveStatus.with { $0?.fileId }); XCTAssertEqual(r._interactiveStatus.with { $0?.previousFileId }, 10) }
    func testNonInteractiveChoiceDoesNotChangeAnimation() { let r = Reactions(); _ = r._interactiveStatus.swap(.init(fileId: 42, previousFileId: nil, rect: nil)); apply(r, peer: TelegramUser(), interactive: false); XCTAssertEqual(r._interactiveStatus.with { $0?.fileId }, 42) }
    func testOwnChoicePreservesFocusDisableBehavior() { let r = Reactions(); apply(r, peer: TelegramUser(), gift: gift()); XCTAssertFalse(r.engine.account.postbox.settings.focusIntentStatusEnabled); XCTAssertNil(r.engine.account.postbox.settings.focusIntentStatusFallback) }
    func testDetailsRequireMatchingCollectibleId() { let s = State(owner: EnginePeer(TelegramUser(status: status(100))), gift: .init(unique: gift(200))); XCTAssertFalse(s.weared) }
    func testDetailsRecognizeMatchingGiftDespiteArtworkDifference() { let s = State(owner: EnginePeer(TelegramUser(status: status(100, file: 99))), gift: .init(unique: gift())); XCTAssertTrue(s.weared) }
    func testDetailsWithoutOwnerOrGiftAreNotWorn() { XCTAssertFalse(State(owner: nil, gift: .init(unique: nil)).weared) }
    func testMenuUsesGiftIdInsteadOfArtwork() { let s = ListState(peer: EnginePeer(TelegramUser(status: status(100)))); XCTAssertFalse(menuWorn(unique: gift(200), state: s)); XCTAssertTrue(menuWorn(unique: gift(100, file: 99), state: s)) }
    func testMenuDoesNotConfuseNormalEmojiWithCollectible() { XCTAssertFalse(menuWorn(unique: gift(), state: .init(peer: EnginePeer(TelegramUser(status: .init(content: .emoji(fileId: 10))))))) }
    func testListActionSafelyIgnoresIncompleteGift() { let c = Context(); let s = Atomic(value: ListState(peer: EnginePeer(TelegramUser()))); toggleList(context: c, stateValue: s, option: .init(gift: .init(unique: nil))); toggleList(context: c, stateValue: s, option: .init(gift: .init(unique: .init(id: 1, file: nil)))); XCTAssertTrue(c.reactions.engine.accountData.calls.isEmpty) }
    func testListActionTargetsChannel() { let c = Context(); let s = Atomic(value: ListState(peer: EnginePeer(TelegramChannel(20, status: status(100))))); toggleList(context: c, stateValue: s, option: .init(gift: .init(unique: gift()))); XCTAssertEqual(c.reactions.engine.peers.calls.count, 1); XCTAssertNil(c.reactions.engine.peers.calls.last?.giftId); XCTAssertTrue(c.reactions.engine.accountData.calls.isEmpty) }
    func testDetailsTakeOffTargetsChannel() { let c = Context(); let s = Atomic(value: State(owner: EnginePeer(TelegramChannel(20, status: status(100))), gift: .init(unique: gift()))); toggleNft(context: c, stateValue: s, gift: gift()); XCTAssertEqual(c.reactions.engine.peers.calls.count, 1); XCTAssertNil(c.reactions.engine.peers.calls.last?.fileId); XCTAssertTrue(c.reactions.engine.accountData.calls.isEmpty) }
    func testDetailsDifferentGiftShowsWearPreview() { let c = Context(); let s = Atomic(value: State(owner: EnginePeer(TelegramUser(status: status(100))), gift: .init(unique: gift(200)))); toggleNft(context: c, stateValue: s, gift: gift(200)); guard case .previewWear = s.with({ $0.source }) else { return XCTFail() }; XCTAssertTrue(c.reactions.engine.accountData.calls.isEmpty) }
    func testDetailsSameGiftWithMissingFileDoesNotCrash() { let c = Context(); let value = StarGift.UniqueGift(id: 100, file: nil); let s = Atomic(value: State(owner: EnginePeer(TelegramUser(status: status(100))), gift: .init(unique: value))); toggleNft(context: c, stateValue: s, gift: value); XCTAssertTrue(c.reactions.engine.accountData.calls.isEmpty) }
}
