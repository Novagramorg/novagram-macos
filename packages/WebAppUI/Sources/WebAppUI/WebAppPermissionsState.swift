import TelegramCore
import Postbox
import Foundation
import SwiftSignalKit
import InAppSettings
#if SHARE
import TelegramThemeShare
import TelegramContextShare
#else
import TelegramTheme
import TelegramContext
#endif

public struct WebAppPermissionsState: Codable {
    public enum CodingKeys: String, CodingKey {
        case location
        case emojiStatus
    }
    
    public struct Location: Codable {
        public enum CodingKeys: String, CodingKey {
            case isRequested
            case isAllowed
        }
        
        public let isRequested: Bool
        public let isAllowed: Bool
        
        public init(
            isRequested: Bool,
            isAllowed: Bool
        ) {
            self.isRequested = isRequested
            self.isAllowed = isAllowed
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            self.isRequested = try container.decode(Bool.self, forKey: .isRequested)
            self.isAllowed = try container.decode(Bool.self, forKey: .isAllowed)
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encode(self.isRequested, forKey: .isRequested)
            try container.encode(self.isAllowed, forKey: .isAllowed)
        }
    }
    
    public struct EmojiStatus: Codable {
        public enum CodingKeys: String, CodingKey {
            case isRequested
        }
        
        public let isRequested: Bool
        
        public init(
            isRequested: Bool
        ) {
            self.isRequested = isRequested
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            self.isRequested = try container.decode(Bool.self, forKey: .isRequested)
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encode(self.isRequested, forKey: .isRequested)
        }
    }
        
    public let location: Location?
    public let emojiStatus: EmojiStatus?
    
    public init(
        location: Location?,
        emojiStatus: EmojiStatus?
    ) {
        self.location = location
        self.emojiStatus = emojiStatus
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.location = try container.decodeIfPresent(WebAppPermissionsState.Location.self, forKey: .location)
        self.emojiStatus = try container.decodeIfPresent(WebAppPermissionsState.EmojiStatus.self, forKey: .emojiStatus)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encodeIfPresent(self.location, forKey: .location)
        try container.encodeIfPresent(self.emojiStatus, forKey: .emojiStatus)
    }
}

public func webAppPermissionsState(context: any AccountContextProtocol, peerId: EnginePeer.Id) -> Signal<WebAppPermissionsState?, NoError> {
    let key = EngineDataBuffer(length: 8)
    key.setInt64(0, value: peerId.id._internalGetInt64Value())
    
    return context.engine.data.subscribe(TelegramEngine.EngineData.Item.ItemCache.Item(collectionId: ApplicationSpecificItemCacheCollectionId.webAppPermissionsState, id: key))
    |> map { entry -> WebAppPermissionsState? in
        return entry?.get(WebAppPermissionsState.self)
    }
}

public func updateWebAppPermissionsStateInteractively(context: any AccountContextProtocol, peerId: EnginePeer.Id, _ f: @escaping (WebAppPermissionsState?) -> WebAppPermissionsState?) -> Signal<Never, NoError> {
    let key = ValueBoxKey(length: 8)
    key.setInt64(0, value: peerId.id._internalGetInt64Value())
    let entryId = ItemCacheEntryId(collectionId: ApplicationSpecificItemCacheCollectionId.webAppPermissionsState, key: key)
    let postbox = context.account.postbox

    return Signal { subscriber in
        let cancelled = Atomic(value: false)
        let disposable = (postbox.transaction { transaction -> Void in
            guard !cancelled.with({ $0 }) else {
                return
            }
            let current = transaction.retrieveItemCacheEntry(id: entryId)?.get(WebAppPermissionsState.self)
            let updated = f(current)
            guard !cancelled.with({ $0 }) else {
                return
            }
            if let updated {
                if let entry = CodableEntry(updated) {
                    transaction.putItemCacheEntry(id: entryId, entry: entry)
                }
            } else {
                transaction.removeItemCacheEntry(id: entryId)
            }
        } |> ignoreValues).start(completed: subscriber.putCompletion)
        return ActionDisposable {
            _ = cancelled.swap(true)
            disposable.dispose()
        }
    }
}
