import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import NovagramSearchKit

public typealias NovagramSavedSearch = NovagramSearchKit.NovagramSavedSearch

public enum NovagramSavedSearches {
    public static let recentLimit = NovagramSavedSearchStore.recentLimit

    private static var store: NovagramSavedSearchStore {
        return .shared
    }

    public static func list(accountPeerId: PeerId) -> [NovagramSavedSearch] {
        return store.list(accountPeerId: accountPeerId.toInt64())
    }

    public static func signal(accountPeerId: PeerId) -> Signal<[NovagramSavedSearch], NoError> {
        return combineLatest(changes(), NovagramSearchFeatures.signal()) |> map { _, enabled in enabled ? list(accountPeerId: accountPeerId) : [] } |> distinctUntilChanged
    }

    public static func record(_ query: String?, accountPeerId: PeerId, accountRecordId: AccountRecordId) {
        guard NovagramSearchFeatures.isEnabled else {
            return
        }
        store.record(query, accountPeerId: accountPeerId.toInt64(), accountRecordId: accountRecordId.int64)
    }

    public static func setPinned(_ query: String, pinned: Bool, accountPeerId: PeerId, accountRecordId: AccountRecordId) {
        store.setPinned(query, pinned: pinned, accountPeerId: accountPeerId.toInt64(), accountRecordId: accountRecordId.int64)
    }

    public static func remove(_ query: String, accountPeerId: PeerId, accountRecordId: AccountRecordId) {
        store.remove(query, accountPeerId: accountPeerId.toInt64(), accountRecordId: accountRecordId.int64)
    }

    public static func clear(accountRecordId: AccountRecordId) {
        store.clear(accountRecordId: accountRecordId.int64)
    }

    private static func changes() -> Signal<Void, NoError> {
        return Signal { subscriber in
            subscriber.putNext(Void())
            let observer = NotificationCenter.default.addObserver(forName: NovagramSavedSearchStore.didChangeNotification, object: nil, queue: nil, using: { _ in
                subscriber.putNext(Void())
            })
            return ActionDisposable {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
