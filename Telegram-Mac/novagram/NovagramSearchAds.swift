//
//  NovagramSearchAds.swift
//  Telegram-Mac
//
//  SEARCH slot (serving v2): one sponsored row in global search, above the results. `view` when the row
//  is shown, `click` when it is opened (queued before the peer opens). Telegram's own sponsored peers
//  are a fallback for when our backend has no ad for the query, never for Premium users, and nothing
//  shows while "Remove all ads" is on.
//  Port of iOS submodules/Novagram/NovagramAds/Sources/NovagramSearchAds.swift.
//
//  Hooks: SearchController.swift (`.novagramAdPeer` entry, Telegram `adPeers` fallback, click) and
//  RecentPeerRowItem.swift (the row's "Ad" pill: view + About / Report menu).
//

import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import NovagramCore
import NovagramAds

/// A promoted channel or bot resolved for the current search query.

enum NovagramSearchAds {
    /// The backend matches the whole normalized query of this length only.
    private static let queryLengthRange = 3 ... 32

    /// OUR promoted peer for `query` (after the user stops typing for ~0.5 s), or nil. Emits nil first so
    /// the search results never wait for us. Hidden while "Remove all ads" is on.
    static func promotedChannel(context: AccountContext, query: String) -> Signal<NovagramPromotedSearchPeer?, NoError> {
        return NovagramAdsCenter.gated(empty: nil, .single(nil) |> then(self.promotedPeer(context: context, query: query)))
    }

    /// Telegram's sponsored peers by the product rule: only once our backend answered "no ad" for this
    /// query, never for Premium users, none while "Remove all ads" is on.
    /// Emits exactly one value, after our backend answered (at most `fallbackWait` seconds): SearchController
    /// dedupes the remote results across emissions (its `ids`), so a second value dropped the results it
    /// had just shown and they vanished.
    static func telegramFallback(context: AccountContext, query: String, telegram: Signal<[AdPeer], NoError>) -> Signal<[AdPeer], NoError> {
        return NovagramAdsCenter.oursFirst(context: context, surface: "SEARCH", ours: self.promotedPeer(context: context, query: query), fallback: telegram, empty: [], isEmpty: { $0.isEmpty }, waitForOurs: true, map: { _ -> [AdPeer] in
            return []
        })
        |> take(1)
        |> timeout(fallbackWait, queue: Queue.mainQueue(), alternate: .single([]))
    }

    private static let fallbackWait: Double = 1.5

    /// The search row's pill text (uz "Reklama", ru "Реклама", en "Ad").
    static var adLabel: String {
        return NovagramL10n.current.ads_label
    }

    /// The row was shown.
    static func recordView(token: String) {
        NovagramAdsCenter.recordView(token: token)
    }

    /// The row was opened: queues the click before the caller opens the peer.
    static func recordClick(token: String) {
        NovagramAdsCenter.recordClick(token: token)
    }

    /// The promoted peer when the backend has an ad for this exact query, else nil. Both callers above
    /// share one request: the SDK session joins in-flight serves and caches the answer for ttl_seconds.
    private static func promotedPeer(context: AccountContext, query: String) -> Signal<NovagramPromotedSearchPeer?, NoError> {
        guard NovagramAdsCenter.isConfigured, self.queryLengthRange.contains(SDKAdSlot.normalizedSearchQuery(query).count) else {
            return .single(nil)
        }
        let request = NovagramAdsCenter.visibleAd(context: context, slot: .search(query: query))
        |> mapToSignal { served -> Signal<NovagramPromotedSearchPeer?, NoError> in
            guard let served else {
                return .single(nil)
            }
            guard let username = SDKAdSlot.bareBotUsername(served.ad.promoted.username) ?? SDKAdSlot.bareBotUsername(served.ad.url) else {
                return .single(nil)
            }
            return context.engine.peers.resolvePeerByName(name: username, referrer: nil)
            |> mapToSignal { result -> Signal<NovagramPromotedSearchPeer?, NoError> in
                guard case let .result(peer) = result else {
                    return .complete()
                }
                return .single(peer.map { NovagramPromotedSearchPeer(peer: $0, token: served.ad.randomId) })
            }
        }
        return Signal<Void, NoError>.single(Void())
        |> delay(SDKAdsLimits.searchDebounce, queue: .mainQueue())
        |> mapToSignal { _ -> Signal<NovagramPromotedSearchPeer?, NoError> in
            return request
        }
    }
}
