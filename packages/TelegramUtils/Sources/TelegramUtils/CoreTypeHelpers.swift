import Foundation
import TelegramCore
import Postbox
import TelegramMediaResources

public extension MessageIndex {
    func withUpdatedTimestamp(_ timestamp: Int32) -> MessageIndex {
        return MessageIndex(id: self.id, timestamp: timestamp)
    }
    init(_ message: Message) {
        self.init(id: message.id, timestamp: message.timestamp)
    }
    
}

public extension MessageHistoryAnchorIndex {
    func withSubstractedTimestamp(_ timestamp: Int32) -> MessageHistoryAnchorIndex {
        switch self {
        case let .message(index):
            return MessageHistoryAnchorIndex.message(MessageIndex(id: index.id, timestamp: index.timestamp - timestamp))
        default:
            return self
        }
    }
}

public extension ChatContextResultCollection {
    func withAdditionalCollection(_ collection: ChatContextResultCollection) -> ChatContextResultCollection {
        return ChatContextResultCollection(botId: collection.botId, peerId: collection.peerId, query: collection.query, geoPoint: collection.geoPoint, queryId: collection.queryId, nextOffset: collection.nextOffset, presentation: collection.presentation, switchPeer: collection.switchPeer, webView: collection.webView, results: self.results + collection.results, cacheTimeout: collection.cacheTimeout)
    }
}

extension LocalFileReferenceMediaResource : @retroactive Equatable {
    public static func ==(lhs: LocalFileReferenceMediaResource, rhs: LocalFileReferenceMediaResource) -> Bool {
        return lhs.isEqual(to: rhs)
    }
}

public func removeFile(at path: String) {
    try? FileManager.default.removeItem(atPath: path)
}

public extension MessageForwardInfo {
    var authorTitle: String {
        return author.flatMap { TelegramUtilsHooks.shared.peerTitle($0) } ?? authorSignature ?? ""
    }
}
