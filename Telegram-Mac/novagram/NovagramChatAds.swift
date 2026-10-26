//
//  NovagramChatAds.swift
//  Telegram-Mac
//
//  CHANNEL_MESSAGE and BOT slots (serving v2). Telegram-Mac feeds one ad source to both surfaces:
//  `(fixed: Message?, opportunistic: [Message], version: Int)` from ChatAdData. In a channel the fixed
//  message is the sponsored bubble after the last post; in a bot chat it is the panel above the chat
//  (ChatHeaderController `BotAdMessage`). `withInjectedAd` wraps that source by the product rule:
//  OUR ad first, Telegram's only when we have none and never for Premium, nothing while
//  "Remove all ads" is on.
//  Ports of iOS NovagramChannelAds.swift and NovagramBotAds.swift.
//
//  Hooks (ChatController.swift, see NOVAGRAM_HOOKS.md "Novagram ads v2"):
//   - `adMessages` source: `NovagramChatAds.withInjectedAd(baseAdMessages, context:peerId:)`.
//   - `markAdAction`: `NovagramChatAds.reportClickIfOurs(opaqueId:context:)`.
//   - `markAdAsSeen`, the readAds loop and `removeAd`: `NovagramAdsCenter.recordViewIfOurs` / `hideIfOurs`.
//

import Foundation
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramCore
import NovagramAds
import ChatUI
import GalleryUI
import NovagramCore

enum NovagramChatAds {
    typealias AdState = (fixed: Message?, opportunistic: [Message], version: Int)

    /// CHANNEL_MESSAGE only in public broadcast channels with at least this many subscribers (the
    /// server does not check it; the app does, for every channel, no exceptions).
    static let minimumSubscribers = 1000
    /// How long to wait for the channel's subscriber count before giving up on the slot.
    static let participantCountTimeout: Double = 4.0
    /// Bot API channel id: `-(1_000_000_000_000 + inner id)`.
    static let botApiChannelIdBase: Int64 = 1_000_000_000_000

    /// The chat's ad source by the product rule. Channels ask the CHANNEL_MESSAGE slot, bot chats the BOT
    /// slot; other chats have no slot of ours but Telegram's ad still follows the Premium and
    /// "Remove all ads" rules. Emits an empty state first, so the chat history never waits for us.
    static func withInjectedAd(_ base: Signal<AdState, NoError>, context: AccountContext, peerId: PeerId) -> Signal<AdState, NoError> {
        let ours: Signal<Message?, NoError>
        let surface: String
        switch peerId.namespace {
        case Namespaces.Peer.CloudChannel:
            ours = self.channelAdMessage(context: context, peerId: peerId)
            surface = "CHANNEL_MESSAGE"
        case Namespaces.Peer.CloudUser:
            ours = self.botAdMessage(context: context, peerId: peerId)
            surface = "BOT"
        default:
            ours = .single(nil)
            surface = "CHAT"
        }
        let empty: AdState = (fixed: nil, opportunistic: [], version: 0)
        return NovagramAdsCenter.oursFirst(context: context, surface: surface, ours: ours, fallback: base, empty: empty, isEmpty: { state in
            return state.fixed == nil && state.opportunistic.isEmpty
        }, map: { message -> AdState in
            // One fixed ad after the last post (v2 has no posts_between).
            return (fixed: message, opportunistic: [], version: 0)
        })
    }

    /// A tap on one of our sponsored messages: queues the click for OUR backend and returns true, so
    /// the caller does NOT fall through to Telegram's markAction (which would send our opaqueId to
    /// Telegram's ad server). False for Telegram's own ads. The caller opens the url right after.
    @discardableResult
    static func reportClickIfOurs(opaqueId: Data, context: AccountContext) -> Bool {
        return NovagramAdsCenter.recordClickIfOurs(opaqueId: opaqueId)
    }

    /// A click on the MEDIA of OUR channel bubble, like iOS (ChatController: only a non-animated video opens
    /// the gallery, any other media tap runs `activateAdAction`). Two hooks call it:
    ///  - ChatMediaContentView.mouseDown: in a copy-protected chat the media hands its mouse-down to the
    ///    parent view, and the ad bubble (WPContentView) opens the ad link on mouse-down, so the video
    ///    used to open the channel.
    ///  - ChatMessageItem showMedia: the bubble opens the gallery with `.alone`, which looks the
    ///    message up in Postbox. A sponsored message is never stored there, so the gallery came up
    ///    empty (and a photo click did nothing and was never counted).
    /// Video: `.messages([message])` hands the message itself to the gallery. The gallery records
    /// `video_open` (MGalleryItem hook) and shows the ad button (click).
    /// Photo / GIF / anything else: queue our `click` and open the ad link in-app, like the bubble button.
    /// False for Telegram's own ads, which keep the upstream behaviour.
    static func openMediaIfOurs(message: Message?, media: Media?, context: AccountContext?, delegate: InteractionContentViewProtocol?, parameters: ChatMediaLayoutParameters?) -> Bool {
        guard let message, let adAttribute = message.adAttribute, let token = NovagramAdsHooks.token(opaqueId: adAttribute.opaqueId), let context else {
            return false
        }
        guard let file = media as? TelegramMediaFile, file.isVideo, !file.isAnimated else {
            return self.openAdLink(url: adAttribute.url, opaqueId: adAttribute.opaqueId, token: token, context: context)
        }
        // Already open: the mouse-up after the mouse-down hook asks again.
        if getGalleryViewer() != nil {
            return true
        }
        NovagramAdsCenter.logger.debug("video click -> gallery \(NovagramAdsCenter.masked(token), privacy: .public)")
        showChatGallery(context: context, message: message, delegate, parameters, type: .messages([message]), chatMode: nil, chatLocation: nil)
        return true
    }

    /// Mouse-down (protected chat) and the mouse-up that follows both reach `openMediaIfOurs`: one
    /// physical click must count once.
    private static let mediaClickDebounce: CFTimeInterval = 1.5
    private static var lastMediaClick: (token: String, time: CFAbsoluteTime)?

    /// Our `click` is queued before the url opens, never sent to Telegram (same order as WPLayout.invokeAction).
    private static func openAdLink(url: String, opaqueId: Data, token: String, context: AccountContext) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        if let last = self.lastMediaClick, last.token == token, now - last.time < self.mediaClickDebounce {
            return true
        }
        self.lastMediaClick = (token: token, time: now)
        NovagramAdsCenter.logger.debug("photo click -> ad link \(NovagramAdsCenter.masked(token), privacy: .public)")
        let link = inApp(for: url.nsstring, context: context, openInfo: { peerId, toChat, messageId, action in
            // The chat on screen opens the link exactly like the bubble button does.
            if let chat = context.bindings.rootNavigation().controller as? ChatController {
                chat.chatInteraction.openInfo(peerId, toChat, messageId, action)
            } else {
                context.bindings.rootNavigation().push(ChatAdditionController(context: context, chatLocation: .peer(peerId), focusTarget: .init(messageId: messageId), initialAction: action))
            }
        })
        NovagramAdsCenter.recordClickIfOurs(opaqueId: opaqueId)
        execute(inapp: link)
        return true
    }

    // MARK: - CHANNEL_MESSAGE

    /// The Bot API id of a channel peer (`-100…`), or nil when it is not a valid channel id.
    static func botApiChannelId(_ peerId: PeerId) -> Int64? {
        guard peerId.namespace == Namespaces.Peer.CloudChannel else {
            return nil
        }
        let channelId = -(self.botApiChannelIdBase + peerId.id._internalGetInt64Value())
        return SDKAdSlot.isValidChannelId(channelId) ? channelId : nil
    }

    /// The channel_id sent to the backend. Debug builds only: the launch environment value
    /// NOVAGRAM_ADS_DEBUG_CHANNEL_ID=-100… replaces it, so an eligible channel of a test account can show
    /// the backend's test campaigns. Release builds always send the real id.
    static func requestChannelId(_ channelId: Int64) -> Int64 {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["NOVAGRAM_ADS_DEBUG_CHANNEL_ID"], let override = Int64(value), SDKAdSlot.isValidChannelId(override) {
            return override
        }
        #endif
        return channelId
    }

    /// The channel peer when it may carry ads: a public broadcast channel (has a username) with at
    /// least 1000 subscribers. Emits once; nil when not eligible or unknown.
    private static func eligibleChannel(context: AccountContext, peerId: PeerId) -> Signal<EnginePeer?, NoError> {
        // The subscriber count lives in CachedChannelData, which arrives a moment after the chat opens.
        return context.engine.data.subscribe(
            TelegramEngine.EngineData.Item.Peer.Peer(id: peerId),
            TelegramEngine.EngineData.Item.Peer.ParticipantCount(id: peerId)
        )
        |> filter { _, participantCount in
            return participantCount != nil
        }
        |> take(1)
        |> timeout(self.participantCountTimeout, queue: .mainQueue(), alternate: .single((nil, nil)))
        |> map { peer, participantCount -> EnginePeer? in
            guard case let .channel(channel) = peer, case .broadcast = channel.info, channel.addressName != nil else {
                NovagramAdsCenter.logger.debug("channel slot skipped: not a public broadcast channel")
                return nil
            }
            guard let participantCount, participantCount >= self.minimumSubscribers else {
                NovagramAdsCenter.logger.debug("channel slot skipped: \(participantCount ?? -1, privacy: .public) subscribers")
                return nil
            }
            return peer
        }
    }

    private static func channelAdMessage(context: AccountContext, peerId: PeerId) -> Signal<Message?, NoError> {
        guard NovagramAdsCenter.isConfigured, let channelId = self.botApiChannelId(peerId) else {
            return .single(nil)
        }
        return self.eligibleChannel(context: context, peerId: peerId)
        |> mapToSignal { peer -> Signal<Message?, NoError> in
            guard let peer else {
                return .single(nil)
            }
            return NovagramAdsCenter.visibleAd(context: context, slot: .channel(channelId: self.requestChannelId(channelId)))
            |> map { served -> Message? in
                guard let served else {
                    return nil
                }
                return NovagramAdMessage.make(served: served, peerId: peerId, chatPeer: peer._asPeer())
            }
        }
    }

    // MARK: - BOT

    private static func botAdMessage(context: AccountContext, peerId: PeerId) -> Signal<Message?, NoError> {
        guard NovagramAdsCenter.isConfigured else {
            return .single(nil)
        }
        return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        |> mapToSignal { peer -> Signal<Message?, NoError> in
            guard case let .user(user) = peer, user.botInfo != nil, let username = user.addressName, SDKAdSlot.bareBotUsername(username) != nil else {
                return .single(nil)
            }
            return NovagramAdsCenter.visibleAd(context: context, slot: .bot(username: username))
            |> map { served -> Message? in
                guard let served else {
                    return nil
                }
                return NovagramAdMessage.make(served: served, peerId: peerId, chatPeer: user)
            }
        }
    }
}
