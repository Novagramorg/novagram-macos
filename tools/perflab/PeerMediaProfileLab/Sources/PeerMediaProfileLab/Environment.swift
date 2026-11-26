import Cocoa
import SwiftSignalKit

public struct PeerId: Hashable, Codable {
    let value: Int64
    init(_ value: Int64) { self.value = value }
    var predecessor: PeerId { PeerId(value - 1) }
    var successor: PeerId { PeerId(value + 1) }
    static let max = PeerId(Int64.max)
    func toInt64() -> Int64 { value }
}

public enum PeerInputActivity: Equatable {
    case typing
    case uploading(Int32)
    case speaking(Int32)
}

public struct MessageId: Hashable, Codable {
    public typealias Namespace = Int32
    let peerId: PeerId
    let namespace: Int32
    let id: Int32
}

public final class Message: Equatable {
    let id: MessageId
    let timestamp: Int32
    let version: Int
    let restricted: Bool
    var expanded: [Message] = []
    init(_ id: Int32, timestamp: Int32, namespace: Int32 = 0, version: Int = 0, restricted: Bool = false) {
        self.id = MessageId(peerId: PeerId(1), namespace: namespace, id: id)
        self.timestamp = timestamp
        self.version = version
        self.restricted = restricted
    }
    public static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id && lhs.timestamp == rhs.timestamp && lhs.version == rhs.version && lhs.restricted == rhs.restricted
    }
    func restrictedText(_ settings: ContentSettings) -> String? { restricted ? "restricted" : nil }
}

extension MessageIndex {
    init(_ message: Message) { self.init(id: message.id, timestamp: message.timestamp) }
}

public struct ContentSettings: Equatable { var enabled = true }
public struct SearchState: Equatable { var request = "" }
public struct AutomaticMediaDownloadSettings: Equatable { var enabled = true }
public enum ChatHistoryViewScrollPosition: Equatable { case top, bottom }
public enum ChatHistoryViewUpdateType: Equatable { case generic, fillHole }
public enum TableSavingSide: Equatable { case upper, lower }
public enum MessageTags { case file, music, voice, webPage }
public enum PeerMediaUpdateState { case search, history, loading }
public struct PeerMediaUpdate {
    var messages: [Message]
    var updateType: PeerMediaUpdateState
    var automaticDownload = AutomaticMediaDownloadSettings()
}

public final class MessageHistoryView {
    let laterId: MessageIndex?
    let earlierId: MessageIndex?
    let holeLater: Bool
    let holeEarlier: Bool
    let anchorIndex: Int
    init(laterId: MessageIndex? = nil, earlierId: MessageIndex? = nil, holeLater: Bool = false, holeEarlier: Bool = false, anchorIndex: Int = 0) {
        self.laterId = laterId
        self.earlierId = earlierId
        self.holeLater = holeLater
        self.holeEarlier = holeEarlier
        self.anchorIndex = anchorIndex
    }
}

public protocol Identifiable { var stableId: AnyHashable { get } }
public enum GeneralViewType: Equatable { case singleItem, firstItem, lastItem, innerItem }

func sharedMediaPredicate(for tags: MessageTags) -> (Message) -> Bool { { _ in true } }
func expandSharedMediaMessages(_ messages: [Message], where predicate: (Message) -> Bool) -> [Message] {
    messages.flatMap { $0.expanded.isEmpty ? [$0] : $0.expanded }.filter(predicate)
}

typealias TabData = (tabs: [PeerMediaCollectionMode], selected: PeerMediaCollectionMode?, hasLoaded: Bool)
final class TabController {
    let ready = Promise<Bool>()
    var subscriptions = 0
    var cancellations = 0
    init(automaticallyReady: Bool) {
        ready.set(Signal { [weak self] subscriber in
            self?.subscriptions += 1
            if automaticallyReady { subscriber.putNext(true) }
            return ActionDisposable { [weak self] in self?.cancellations += 1 }
        })
    }
}

class TabHarnessBase {
    let tabsSignal = Promise<TabData>()
    let pipe = ValuePipe<TabData>()
    var automaticallyReady = true
    private var controllers: [PeerMediaCollectionMode: TabController] = [:]
    var preparations = 0
    init() { tabsSignal.set(pipe.signal()) }
    func prepareController(for mode: PeerMediaCollectionMode) -> TabController? {
        preparations += 1
        return controller(for: mode)
    }
    func controller(for mode: PeerMediaCollectionMode) -> TabController {
        if let controller = controllers[mode] { return controller }
        let controller = TabController(automaticallyReady: automaticallyReady)
        controllers[mode] = controller
        return controller
    }
}
