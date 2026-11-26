import Foundation

struct MediaId: Hashable { let namespace: Int32; let id: Int64 }
struct PeerId: Hashable { let value: Int64; func toInt64() -> Int64 { value } }
struct MessageId: Hashable { let peerId: PeerId; let namespace: Int32; let id: Int32 }
struct Message { let id: MessageId; var chatStableId: AnyHashable { id } }
struct Resource { let id: MediaId }
struct File { let fileId: MediaId; var resource: Resource { Resource(id: fileId) } }
struct Entry {
    let messageId: MessageId
    func isEqual(to message: Message) -> Bool { message.id == messageId }
    func isEqual(to id: MessageId) -> Bool { id == messageId }
}
struct Song { let entry: Entry; let resource: Resource }
struct Player { let currentSong: Song? }
struct Row { let inModal: Bool; let file: File; let message: Message }
enum Namespaces { enum Message { static let Cloud: Int32 = 0; static let Local: Int32 = 1 } }
struct Account { let peerId = PeerId(value: 42) }
struct Context { let account = Account() }
struct InputDataIdentifier: Equatable { let value: String; init(_ value: String) { self.value = value } }
__MAPPING__
__IDS__

private final class Picker {
    let context = Context()
    let messageIds = SendAudioMessageIds()
    func saved(_ id: Int64, namespace: Int32 = 0) -> MessageId {
        let context = self.context
        let file = File(fileId: MediaId(namespace: namespace, id: id))
        __SAVED__
        return messageId
    }
    func bot(_ id: Int64) -> MessageId {
        let peerId = context.account.peerId
        let file = File(fileId: MediaId(namespace: 0, id: id))
        __BOT__
        return messageId
    }
}

func merge(shared: [Message], bot: [Message]) -> [Message] {
    __MERGE__
    return allMessages
}

func isPlaying(controller: Player, file: File, message: Message) -> Bool {
    return __PLAYING__
}
func wrapperId(file: File, message: Message) -> AnyHashable {
    return __WRAPPER__
}
func playingRow(song: Song, item: Row) -> Bool {
    return __ROW_PLAYING__
}
func usesSuppliedMenu(inModal: Bool, isCompactPlayer: Bool) -> Bool {
    return __MENU__
}

func check(_ condition: Bool, _ message: String) {
    if !condition { print(message); exit(1) }
}

private let picker = Picker()
switch CommandLine.arguments[1] {
case "saved-collision":
    check(picker.saved(1) != picker.saved(1 + (1 << 31)), "Distinct saved files collide after truncation")
case "bot-collision":
    check(picker.bot(1) != picker.bot(1 + Int64(Int32.max)), "Distinct bot files collide after remainder mapping")
case "negative-ids":
    check(picker.bot(-1) != picker.bot(-2), "Distinct signed file IDs collapse to zero")
case "cross-source":
    check(picker.saved(Int64.max) == picker.bot(Int64.max), "Same file gets different synthetic identities")
case "stable":
    let first = picker.saved(42)
    _ = picker.saved(999)
    check(picker.saved(42) == first, "Identity changed after an intervening file")
case "media-namespace":
    check(picker.saved(42, namespace: 0) != picker.saved(42, namespace: 1), "Identity discards media namespace")
case "concurrent-mapping":
    let lock = NSLock()
    var results: [Int64: Set<MessageId>] = [:]
    DispatchQueue.concurrentPerform(iterations: 1000) { index in
        let id = Int64(index % 100)
        let mapped = picker.saved(id)
        lock.lock()
        results[id, default: []].insert(mapped)
        lock.unlock()
    }
    check(results.count == 100 && results.values.allSatisfy { $0.count == 1 }, "Concurrent requests assigned inconsistent IDs")
    check(Set(results.values.flatMap { $0 }).count == 100, "Concurrent requests reused IDs across files")
case "row-namespace":
    let cloud = Message(id: MessageId(peerId: PeerId(value: 42), namespace: 0, id: 1))
    let local = Message(id: MessageId(peerId: PeerId(value: 42), namespace: 1, id: 1))
    check(_id_search(cloud) != _id_search(local), "Search rows discard the message namespace")
case "row-peer":
    let a = Message(id: MessageId(peerId: PeerId(value: 42), namespace: 0, id: 1))
    let b = Message(id: MessageId(peerId: PeerId(value: 43), namespace: 0, id: 1))
    check(_id_shared(a) != _id_shared(b), "Rows discard peer identity")
case "bot-duplicates":
    let a = Message(id: picker.bot(1))
    let b = Message(id: picker.bot(2))
    check(merge(shared: [a], bot: [b, b, a]).map { $0.id } == [a.id, b.id], "Repeated bot results produce duplicate row identities")
case "shared-order":
    let a = Message(id: picker.saved(1))
    let b = Message(id: picker.saved(2))
    let c = Message(id: picker.bot(3))
    check(merge(shared: [b, a], bot: [a, c]).map { $0.id } == [b.id, a.id, c.id], "Merge changed existing result order")
case "playback-collision":
    let file = File(fileId: MediaId(namespace: 0, id: 55))
    let other = File(fileId: MediaId(namespace: 0, id: 66))
    let message = Message(id: picker.saved(55))
    let controller = Player(currentSong: Song(entry: Entry(messageId: message.id), resource: other.resource))
    check(!isPlaying(controller: controller, file: file, message: message), "Colliding synthetic ID toggles another song")
case "playback-same-resource":
    let file = File(fileId: MediaId(namespace: 0, id: 55))
    let message = Message(id: picker.saved(55))
    let otherMessage = Message(id: picker.saved(66))
    let controller = Player(currentSong: Song(entry: Entry(messageId: otherMessage.id), resource: file.resource))
    check(isPlaying(controller: controller, file: file, message: message), "Same resource restarts after picker identity changes")
case "wrapper-identity":
    let file = File(fileId: MediaId(namespace: 0, id: Int64.max))
    check(wrapperId(file: file, message: Message(id: picker.saved(Int64.max))) == AnyHashable(file.fileId), "Player identity discards the full file ID")
case "modal-playing-row":
    let file = File(fileId: MediaId(namespace: 0, id: 55))
    let other = File(fileId: MediaId(namespace: 0, id: 66))
    let message = Message(id: picker.saved(55))
    let song = Song(entry: Entry(messageId: message.id), resource: other.resource)
    check(!playingRow(song: song, item: Row(inModal: true, file: file, message: message)), "Modal marks a different resource as playing")
    check(playingRow(song: song, item: Row(inModal: true, file: other, message: Message(id: picker.saved(66)))), "Modal misses the playing resource")
case "chat-playing-row":
    let file = File(fileId: MediaId(namespace: 0, id: 55))
    let message = Message(id: picker.saved(55))
    let song = Song(entry: Entry(messageId: message.id), resource: file.resource)
    check(playingRow(song: song, item: Row(inModal: false, file: file, message: message)), "Shared media row lost message-based playback identity")
    check(!playingRow(song: song, item: Row(inModal: false, file: file, message: Message(id: picker.saved(66)))), "Shared media row matches by file instead of message")
case "modal-menu":
    check(usesSuppliedMenu(inModal: true, isCompactPlayer: false), "Audio picker ignores its Send menu and falls through to message actions")
case "chat-menu":
    check(!usesSuppliedMenu(inModal: false, isCompactPlayer: false), "Ordinary message menu was replaced")
    check(usesSuppliedMenu(inModal: false, isCompactPlayer: true), "Compact player menu was replaced")
default:
    exit(2)
}
