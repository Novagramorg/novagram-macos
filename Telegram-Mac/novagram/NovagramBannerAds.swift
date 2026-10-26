//
//  NovagramBannerAds.swift
//  Telegram-Mac
//
//  System banners above the chat list (SDKBannerFeed). Telegram-Mac already draws server notices there
//  (`UICustomLinkAction`, fed by ServerProvidedSuggestion.link), so OUR banner goes into the same slot as
//  a `.link` suggestion placed first. Telegram's own notices show unchanged when we have no banner.
//  Port of iOS submodules/Fenixuz/NovagramAds/Sources/NovagramBannerAds.swift.
//
//  Hooks: ChatListController.swift — the `suggestions` source and UICustomLinkAction
//  (action / dismiss / canDismiss / isEqual). See FENIXUZ_HOOKS.md "Novagram ads v2".
//

import Cocoa
import SwiftSignalKit
import Postbox
import TelegramCore
import NovagramAds

enum NovagramBannerAds {
    /// `novagram-banner:<uuid>` (closable) or `novagram-banner-fixed:<uuid>` (no "X").
    static let closablePrefix = "novagram-banner:"
    static let fixedPrefix = "novagram-banner-fixed:"
    static let changedNotification = Notification.Name("FenixNovagramBannerChanged")
    static let store = NovagramBannerStore()

    /// Telegram's server suggestions with OUR live banner (if any) in front, so it takes the chat-list
    /// notice slot. Emits Telegram's list at once: the chat list never waits for our network call.
    static func suggestions(context: AccountContext, telegram: Signal<[ServerProvidedSuggestion], NoError>) -> Signal<[ServerProvidedSuggestion], NoError> {
        return combineLatest(telegram, self.bannerSuggestion(context: context), NovagramAdsGate.enabledSignal)
        |> map { telegram, ours, adsEnabled -> [ServerProvidedSuggestion] in
            // "Remove all ads" on: nothing in this slot, neither our banner nor Telegram's promo notices
            // (birthday setup, Premium grace, Stars, links). Security notices are not suggestions and stay.
            guard adsEnabled else {
                return []
            }
            guard let ours else {
                return telegram
            }
            return [ours] + telegram
        }
    }

    static func isOurs(noticeId: String) -> Bool {
        return self.bannerId(noticeId: noticeId) != nil
    }

    /// Fixed banners (dismissible == false) have no "X". Telegram's notices keep theirs.
    static func canDismiss(noticeId: String) -> Bool {
        return !noticeId.hasPrefix(self.fixedPrefix)
    }

    /// A tap on OUR banner: counts the click (fire-and-forget) and opens its link in the app. Returns
    /// false for Telegram's own notices, so the caller keeps its own path for those.
    static func openIfOurs(noticeId: String, context: AccountContext) -> Bool {
        guard let bannerId = self.bannerId(noticeId: noticeId) else {
            return false
        }
        guard let banner = self.store.banner(id: bannerId), let link = banner.linkURL else {
            // Not tappable (no link): nothing to open, nothing to count.
            return true
        }
        if let feed = NovagramAdsCenter.bannerFeed(context: context) {
            Task {
                _ = await feed.click(banner)
            }
        }
        execute(inapp: inApp(for: link.absoluteString.nsstring, context: context, openInfo: { peerId, _, messageId, action in
            context.bindings.rootNavigation().push(ChatAdditionController(context: context, chatLocation: .peer(peerId), focusTarget: .init(messageId: messageId), initialAction: action))
        }))
        return true
    }

    /// Closes OUR banner: hidden at once, remembered by the feed, sent to the server (retried later when
    /// offline). Returns false for Telegram's own notices (they go to Telegram's dismiss call).
    static func dismissIfOurs(noticeId: String, context: AccountContext) -> Bool {
        guard let bannerId = self.bannerId(noticeId: noticeId) else {
            return false
        }
        self.store.close(userId: NovagramAdsCenter.userId(context), id: bannerId)
        NotificationCenter.default.post(name: self.changedNotification, object: nil)
        if let banner = self.store.banner(id: bannerId), let feed = NovagramAdsCenter.bannerFeed(context: context) {
            Task {
                await feed.dismiss(banner)
            }
        }
        return true
    }

    // MARK: - Private

    /// The first live, not-closed banner of the account as a `.link` suggestion. Refreshes on subscribe
    /// (app start, account switch) and when the app becomes active; the feed throttles to 15 minutes.
    private static func bannerSuggestion(context: AccountContext) -> Signal<ServerProvidedSuggestion?, NoError> {
        guard let feed = NovagramAdsCenter.bannerFeed(context: context) else {
            return .single(nil)
        }
        let userId = NovagramAdsCenter.userId(context)
        let source = Signal<SDKBannerAd?, NoError> { subscriber in
            let subscription = NovagramBannerSubscription(feed: feed, userId: userId, emit: { banner in
                subscriber.putNext(banner)
            })
            subscription.start()
            return ActionDisposable {
                subscription.stop()
            }
        }
        let suggestion = source
        |> map { banner -> ServerProvidedSuggestion? in
            return banner.map(self.suggestion)
        }
        return NovagramAdsCenter.gated(empty: nil, .single(nil) |> then(suggestion))
        |> distinctUntilChanged
    }

    private static func suggestion(_ banner: SDKBannerAd) -> ServerProvidedSuggestion {
        let prefix = banner.dismissible ? self.closablePrefix : self.fixedPrefix
        return .link(
            id: prefix + banner.id.uuidString,
            url: banner.linkURL?.absoluteString ?? "",
            title: ServerSuggestionInfo.Item.Text(string: banner.title, entities: []),
            subtitle: ServerSuggestionInfo.Item.Text(string: banner.text, entities: [])
        )
    }

    private static func bannerId(noticeId: String) -> UUID? {
        for prefix in [self.closablePrefix, self.fixedPrefix] where noticeId.hasPrefix(prefix) {
            return UUID(uuidString: String(noticeId.dropFirst(prefix.count)))
        }
        return nil
    }
}

/// Reloads one account's banner: on start, when the app becomes active, after a close, and when the
/// shown banner's ends_at passes. Results are applied on the main queue; a newer reload wins.
final class NovagramBannerSubscription {
    private let feed: SDKBannerFeed
    private let userId: Int64
    private let emit: (SDKBannerAd?) -> Void
    private let generation = Atomic<Int>(value: 0)
    private var observers: [NSObjectProtocol] = []
    /// Main queue only.
    private var expiryTimer: SwiftSignalKit.Timer?
    /// Main queue only: a reload finishing after `stop()` must not schedule a new timer.
    private var isStopped = false

    init(feed: SDKBannerFeed, userId: Int64, emit: @escaping (SDKBannerAd?) -> Void) {
        self.feed = feed
        self.userId = userId
        self.emit = emit
    }

    func start() {
        self.reload(refresh: true)
        self.observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reload(refresh: true)
        })
        self.observers.append(NotificationCenter.default.addObserver(forName: NovagramBannerAds.changedNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reload(refresh: false)
        })
    }

    func stop() {
        for observer in self.observers {
            NotificationCenter.default.removeObserver(observer)
        }
        self.observers.removeAll()
        // Dispose can come from any queue; the timer lives on the main queue (strong self until then).
        Queue.mainQueue().async {
            self.isStopped = true
            self.expiryTimer?.invalidate()
            self.expiryTimer = nil
        }
    }

    private func reload(refresh: Bool) {
        let current = self.generation.modify { $0 + 1 }
        let feed = self.feed
        let userId = self.userId
        Task { [weak self] in
            if refresh {
                await feed.refresh()
            }
            let banner = await feed.banners().first(where: { !NovagramBannerAds.store.isClosed(userId: userId, id: $0.id) })
            Queue.mainQueue().async {
                // A newer reload started meanwhile: let it report instead.
                guard let self, !self.isStopped, self.generation.with({ $0 }) == current else {
                    return
                }
                if let banner {
                    NovagramBannerAds.store.remember(banner)
                }
                self.scheduleExpiry(banner?.endsAt)
                self.emit(banner)
            }
        }
    }

    /// Replaces the previous timer; `feed.banners()` drops the expired banner on the reload it triggers.
    private func scheduleExpiry(_ endsAt: Date?) {
        self.expiryTimer?.invalidate()
        self.expiryTimer = nil
        guard let endsAt else {
            return
        }
        let delay = max(1.0, endsAt.timeIntervalSinceNow + 1.0)
        let timer = SwiftSignalKit.Timer(timeout: delay, repeat: false, completion: { [weak self] in
            self?.reload(refresh: false)
        }, queue: Queue.mainQueue())
        self.expiryTimer = timer
        timer.start()
    }
}

/// Banners shown so far (to answer taps) and banners closed in this run, per account (hidden before
/// the feed knows).
final class NovagramBannerStore: @unchecked Sendable {
    private struct ClosedKey: Hashable {
        let userId: Int64
        let id: UUID
    }

    private let lock = NSLock()
    private var banners: [UUID: SDKBannerAd] = [:]
    private var closedKeys = Set<ClosedKey>()

    func remember(_ banner: SDKBannerAd) {
        self.lock.lock()
        self.banners[banner.id] = banner
        self.lock.unlock()
    }

    func banner(id: UUID) -> SDKBannerAd? {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.banners[id]
    }

    func close(userId: Int64, id: UUID) {
        self.lock.lock()
        self.closedKeys.insert(ClosedKey(userId: userId, id: id))
        self.lock.unlock()
    }

    func isClosed(userId: Int64, id: UUID) -> Bool {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.closedKeys.contains(ClosedKey(userId: userId, id: id))
    }
}
