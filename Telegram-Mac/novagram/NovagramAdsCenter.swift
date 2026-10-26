//
//  NovagramAdsCenter.swift
//  Telegram-Mac
//
//  Novagram ads, serving v2 (NovagramAds SDK 3.0, binary) — the shared core.
//  Port of iOS submodules/Novagram/NovagramAds/Sources/NovagramAdsCenter.swift.
//
//  One SDKClient for the app, one SDKAdsSession and one SDKBannerFeed per Telegram account, all kept
//  for the app's lifetime (ad tokens are only valid for the account they were served to). The build only
//  names an environment (see common.xcconfig); the SDK resolves everything else itself.
//
//  OUR sponsored messages carry an AdMessageAttribute whose opaqueId is "novagram:<random_id>", so the
//  hooks in Telegram-owned files can tell them apart from Telegram's own ads.
//
//  Product rule (`oursFirst`): Novagram ads first, to every user (Telegram Premium included), and their
//  events go only to our backend. Telegram's own ad is a fallback for when our backend has no ad for
//  the slot, and never for a Premium user. The hidden "Remove all ads" toggle hides both.
//

import Cocoa
import os
import SwiftSignalKit
import Postbox
import TelegramCore
import Localization
import NovagramAds
import NovagramCore
import PhoneNumberUtils

enum NovagramAdsCenter {
    static let logger = Logger(subsystem: "uz.fenixuz.app", category: "NovagramAds")
    static let registry = NovagramAdsRegistry()

    /// Info.plist key filled from the NOVAGRAM_ADS_ENVIRONMENT build setting (development | production).
    private static let environmentInfoPlistKey = "NovagramAdsEnvironment"

    /// The environment of this build. Missing or unknown value falls back to production.
    static func environment(bundle: Bundle = .main) -> SDKEnvironment {
        return SDKEnvironment(infoPlistKey: self.environmentInfoPlistKey, bundle: bundle) ?? .production
    }

    /// The SDK configuration for this build's environment (nil only for the debug "ads disabled" switch).
    static func makeConfiguration(bundle: Bundle = .main) -> SDKConfiguration? {
        #if DEBUG
        // Debug builds only: lets QA launch a build without any ad traffic.
        if ProcessInfo.processInfo.environment["NOVAGRAM_ADS_DISABLED"] == "1" {
            return nil
        }
        #endif
        return SDKConfiguration(environment: self.environment(bundle: bundle))
    }

    /// True when ads are on in this run (the client exists).
    static var isConfigured: Bool {
        return registry.client != nil
    }

    static func userId(_ context: AccountContext) -> Int64 {
        return context.account.peerId.id._internalGetInt64Value()
    }

    /// random_id for logs: first 8 characters only.
    static func masked(_ token: String) -> String {
        return String(token.prefix(8)) + "…"
    }

    // MARK: - Product rule

    /// The state of OUR side of a slot: still asking, nothing to show, or an ad.
    enum Slot<T> {
        case pending
        case none
        case ad(T)
    }

    /// Live Telegram Premium status of the account (Telegram's fallback ads are never shown to Premium).
    static func isPremium(context: AccountContext) -> Signal<Bool, NoError> {
        return context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
        |> map { peer -> Bool in
            return peer?.isPremium ?? false
        }
        |> distinctUntilChanged
    }

    /// Wraps OUR result as pending -> none / ad, so Telegram's fallback never flashes before ours.
    static func slot<T>(_ ours: Signal<T?, NoError>) -> Signal<Slot<T>, NoError> {
        return .single(.pending)
        |> then(ours |> map { value -> Slot<T> in
            if let value {
                return .ad(value)
            }
            return .none
        })
    }

    /// Novagram ads first; Telegram's `fallback` only when our backend has no ad, never for Premium users;
    /// both hidden while "Remove all ads" is on. Emits `empty` at once, so the caller never waits for us.
    static func oursFirst<Ours, Value>(context: AccountContext, surface: String, ours: Signal<Ours?, NoError>, fallback: Signal<Value, NoError>, empty: Value, isEmpty: @escaping (Value) -> Bool, map transform: @escaping (Ours) -> Value) -> Signal<Value, NoError> {
        let lastSource = Atomic<String?>(value: nil)
        let combined = combineLatest(self.slot(ours), fallback, self.isPremium(context: context))
        |> map { ours, fallback, isPremium -> Value in
            let value: Value
            let source: String
            switch ours {
            case let .ad(ad):
                value = transform(ad)
                source = "novagram"
            case .pending:
                value = empty
                source = "none"
            case .none:
                value = isPremium ? empty : fallback
                source = isEmpty(value) ? "none" : "telegram"
            }
            if lastSource.swap(source) != source {
                logger.debug("\(surface, privacy: .public) source=\(source, privacy: .public)\(isPremium ? " (premium)" : "", privacy: .public)")
            }
            return value
        }
        return self.gated(empty: empty, combined)
    }

    /// Mirrors `source` while ads are allowed; emits `empty` while "Remove all ads" is on (switches live).
    static func gated<T>(empty: T, _ source: Signal<T, NoError>) -> Signal<T, NoError> {
        return NovagramAdsGate.enabledSignal
        |> distinctUntilChanged
        |> mapToSignal { enabled -> Signal<T, NoError> in
            return enabled ? source : .single(empty)
        }
    }

    // MARK: - Serving

    /// The account's session, created (and started) on first use with the account's targeting.
    static func session(context: AccountContext) -> Signal<SDKAdsSession?, NoError> {
        guard let client = registry.client else {
            return .single(nil)
        }
        let userId = self.userId(context)
        registry.setContext(context, userId: userId)
        if let session = registry.existingSession(userId: userId) {
            return .single(session)
        }
        return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
        |> map { accountPeer -> SDKAdsSession? in
            let targeting = self.targeting(context: context, accountPeer: accountPeer)
            return registry.session(userId: userId, client: client, targeting: targeting)
        }
    }

    /// Phone country by calling code (never the number itself), interface language, platform
    /// (the SDK's "macos", which the backend maps to desktop) and app version.
    static func targeting(context: AccountContext, accountPeer: EnginePeer?) -> SDKAdTargeting {
        var phoneCountry: String?
        if case let .user(user) = accountPeer, let phone = user.phone, !phone.isEmpty {
            let countries = context.currentCountriesConfiguration.with { $0 }
            phoneCountry = lookupCountryIdByNumber(phone, configuration: countries)?.0.id
        }
        return SDKAdTargeting(
            phoneCountry: phoneCountry,
            lang: appCurrentLanguage.baseLanguageCode,
            appVersion: SDKAdTargeting.bundleAppVersion
        )
    }

    /// The ad for `slot` (cached by the session for ttl_seconds), minus ads hidden locally.
    static func visibleAd(context: AccountContext, slot: SDKAdSlot) -> Signal<SDKServedAd?, NoError> {
        let userId = self.userId(context)
        let served = session(context: context)
        |> mapToSignal { session -> Signal<SDKServedAd?, NoError> in
            guard let session else {
                return .single(nil)
            }
            return novagramAsyncSignal {
                return await session.ad(for: slot)
            }
        }
        |> map { served -> SDKServedAd? in
            logger.debug("\(slot.placement, privacy: .public): \(served == nil ? "no ad" : "ad served", privacy: .public)")
            if let served {
                registry.remember(served, userId: userId)
            }
            return served
        }
        return combineLatest(served, registry.hiddenVersion.get())
        |> map { served, _ -> SDKServedAd? in
            guard let served, !registry.isHidden(token: served.ad.randomId) else {
                return nil
            }
            return served
        }
    }

    // MARK: - Events (called from the hooks in Telegram-owned files)

    /// Counts a view of OUR ad (its whole text was on screen). Returns false for Telegram's own ads,
    /// so the caller keeps Telegram's path for those. One view per random_id (here and in the SDK).
    @discardableResult
    static func recordViewIfOurs(opaqueId: Data) -> Bool {
        guard let token = NovagramAdsHooks.token(opaqueId: opaqueId) else {
            return false
        }
        recordView(token: token)
        return true
    }

    /// Queues a click on OUR ad (persistent queue, never waits for the network) and starts watching for
    /// the join / Start that makes it an `action`. Returns false for Telegram's own ads.
    @discardableResult
    static func recordClickIfOurs(opaqueId: Data) -> Bool {
        guard let token = NovagramAdsHooks.token(opaqueId: opaqueId) else {
            return false
        }
        recordClick(token: token)
        return true
    }

    /// Records `video_open` for OUR ad (its video opened full screen; the SDK ignores it unless the
    /// ad's media is a VIDEO). Returns false for Telegram's own ads.
    @discardableResult
    static func recordVideoOpenIfOurs(opaqueId: Data) -> Bool {
        guard let token = NovagramAdsHooks.token(opaqueId: opaqueId) else {
            return false
        }
        guard let entry = registry.served(token: token), let session = registry.existingSession(userId: entry.userId) else {
            return true
        }
        logger.debug("video_open -> novagram \(masked(token), privacy: .public)")
        let served = entry.ad
        Task {
            await session.recordVideoOpen(served)
        }
        return true
    }

    /// Hides OUR ad locally for its random_id (bot panel "X"; no server call). False for Telegram's ads.
    @discardableResult
    static func hideIfOurs(opaqueId: Data) -> Bool {
        guard let token = NovagramAdsHooks.token(opaqueId: opaqueId) else {
            return false
        }
        registry.hide(token: token)
        return true
    }

    static func recordView(token: String) {
        guard let entry = registry.served(token: token), registry.markViewed(token: token), let session = registry.existingSession(userId: entry.userId) else {
            return
        }
        logger.debug("view -> novagram \(masked(token), privacy: .public)")
        let served = entry.ad
        Task {
            await session.recordView(served)
        }
    }

    /// The click Task is created synchronously, before the caller opens the url; the SDK only persists
    /// the event to its on-disk queue (a few ms), the request goes out with the next batch.
    static func recordClick(token: String) {
        guard let entry = registry.served(token: token), let session = registry.existingSession(userId: entry.userId) else {
            return
        }
        logger.debug("click -> novagram \(masked(token), privacy: .public)")
        let served = entry.ad
        let userId = entry.userId
        Task {
            await session.recordClick(served)
            Queue.mainQueue().async {
                // The click is queued: now watch for the join / Start that makes it an `action`.
                if let context = registry.context(userId: userId) {
                    NovagramAdActions.watch(served: served, session: session, context: context)
                }
            }
        }
    }

    /// Reports OUR ad and hides it at once. The caller thanks the user whatever the outcome.
    static func report(token: String, reason: SDKAdReportReason) {
        registry.hide(token: token)
        guard let entry = registry.served(token: token), let session = registry.existingSession(userId: entry.userId) else {
            return
        }
        let served = entry.ad
        Task {
            let outcome = await session.report(served, reason: reason)
            if !outcome.isDelivered {
                logger.info("report not delivered: \(String(describing: outcome), privacy: .public)")
            }
        }
    }

    // MARK: - Banners

    static func bannerFeed(context: AccountContext) -> SDKBannerFeed? {
        guard let client = registry.client else {
            return nil
        }
        return registry.bannerFeed(userId: userId(context), client: client)
    }
}

/// Bridges an async call into a one-shot Signal; disposing cancels the task.
func novagramAsyncSignal<T>(_ operation: @escaping () async -> T) -> Signal<T, NoError> {
    return Signal { subscriber in
        let task = Task {
            let value = await operation()
            if Task.isCancelled {
                return
            }
            subscriber.putNext(value)
            subscriber.putCompletion()
        }
        return ActionDisposable {
            task.cancel()
        }
    }
}

/// Lock-protected state shared by every surface: the client, per-account sessions and banner feeds,
/// the served ads by random_id, and the ads hidden locally until the app restarts.
final class NovagramAdsRegistry: @unchecked Sendable {
    struct ServedEntry {
        let userId: Int64
        let ad: SDKServedAd
    }

    private final class WeakContext {
        weak var value: AccountContext?

        init(_ value: AccountContext) {
            self.value = value
        }
    }

    private let lock = NSLock()
    private var clientResolved = false
    private var clientValue: SDKClient?
    private var sessions: [Int64: SDKAdsSession] = [:]
    private var feeds: [Int64: SDKBannerFeed] = [:]
    private var servedAds: [String: ServedEntry] = [:]
    private var viewedTokens = Set<String>()
    private var hiddenTokens = Set<String>()
    private var hiddenCounter = 0
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var contexts: [Int64: WeakContext] = [:]

    /// Bumped whenever an ad gets hidden, so the ad signals re-filter.
    let hiddenVersion = ValuePromise<Int>(0, ignoreRepeated: true)

    private func withLock<T>(_ body: () -> T) -> T {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return body()
    }

    var client: SDKClient? {
        return self.withLock {
            if !self.clientResolved {
                self.clientResolved = true
                if let configuration = NovagramAdsCenter.makeConfiguration() {
                    self.clientValue = SDKClient(configuration: configuration)
                }
            }
            return self.clientValue
        }
    }

    /// The account's context (weak), for watchers that outlive the screen that served the ad.
    func setContext(_ context: AccountContext, userId: Int64) {
        self.withLock {
            if self.contexts[userId]?.value !== context {
                self.contexts[userId] = WeakContext(context)
            }
        }
    }

    func context(userId: Int64) -> AccountContext? {
        return self.withLock {
            return self.contexts[userId]?.value
        }
    }

    func existingSession(userId: Int64) -> SDKAdsSession? {
        return self.withLock {
            return self.sessions[userId]
        }
    }

    func session(userId: Int64, client: SDKClient, targeting: SDKAdTargeting) -> SDKAdsSession {
        var created: SDKAdsSession?
        let session: SDKAdsSession = self.withLock {
            if let current = self.sessions[userId] {
                return current
            }
            // The SDK logger never receives the key and masks random_id (debug level, Console only).
            var configuration = SDKAdsSessionConfiguration.default
            configuration.logger = { message in
                NovagramAdsCenter.logger.debug("\(message, privacy: .public)")
            }
            let session = SDKAdsSession(client: client, userId: userId, targeting: targeting, configuration: configuration)
            self.sessions[userId] = session
            created = session
            return session
        }
        if let created {
            // Periodic flush; also sends the events left over from the last launch.
            Task {
                await created.start()
            }
            self.observeLifecycleIfNeeded()
        }
        return session
    }

    func bannerFeed(userId: Int64, client: SDKClient) -> SDKBannerFeed {
        return self.withLock {
            if let current = self.feeds[userId] {
                return current
            }
            let feed = SDKBannerFeed(client: client, userId: userId)
            self.feeds[userId] = feed
            return feed
        }
    }

    /// The event queue is flushed when the app resigns active or terminates. Events that do not make
    /// it out before the process exits stay in the SDK's on-disk queue and go with the next launch.
    private func observeLifecycleIfNeeded() {
        let needsObservers = self.withLock { self.lifecycleObservers.isEmpty }
        guard needsObservers else {
            return
        }
        let names: [Notification.Name] = [NSApplication.willResignActiveNotification, NSApplication.willTerminateNotification]
        let observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.flushAll()
            }
        }
        self.withLock {
            self.lifecycleObservers = observers
        }
    }

    private func flushAll() {
        let sessions = self.withLock { Array(self.sessions.values) }
        for session in sessions {
            Task {
                await session.flush()
            }
        }
    }

    func remember(_ served: SDKServedAd, userId: Int64) {
        self.withLock {
            self.servedAds[served.ad.randomId] = ServedEntry(userId: userId, ad: served)
        }
    }

    func served(token: String) -> ServedEntry? {
        return self.withLock {
            return self.servedAds[token]
        }
    }

    /// True the first time a token is seen, so a scrolling list does not spawn a task per frame.
    func markViewed(token: String) -> Bool {
        return self.withLock {
            return self.viewedTokens.insert(token).inserted
        }
    }

    func isHidden(token: String) -> Bool {
        return self.withLock {
            return self.hiddenTokens.contains(token)
        }
    }

    func hide(token: String) {
        let version: Int? = self.withLock {
            guard self.hiddenTokens.insert(token).inserted else {
                return nil
            }
            self.hiddenCounter += 1
            return self.hiddenCounter
        }
        if let version {
            self.hiddenVersion.set(version)
        }
    }
}
