//
//  NovagramVideoAds.swift
//  Telegram-Mac
//
//  VIDEO slot (serving v2): a text banner over a channel video in the full-screen player. Telegram-Mac
//  already draws Telegram's own video ads there (SVideoController / SVideoView `AdMessageView`, fed by
//  AdMessagesHistoryContext.state), so OUR ad goes through the same pipeline: one ad per player open,
//  shown after start_delay seconds of playback, closable after min_display_duration, gone after
//  max_display_duration (server values; SDKAdVideoTimers.fallback when a response omits them).
//  Telegram's video ad stays a fallback (never for Premium, nothing while "Remove all ads" is on).
//
//  Not ported from iOS: the next banner after between_delay inside the same player and the per-channel
//  timer sharing across neighbouring videos (Telegram-Mac's player has no such scheduler).
//
//  Hooks: SVideoController.swift (state source, markAsSeen, invoke, removeAd) and SVideoView.swift (menu).
//

import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import NovagramAds

enum NovagramVideoAds {
    /// The ad-source tuple SVideoController consumes (`AdMessagesHistoryContext.state`).
    typealias AdState = (interPostInterval: Int32?, messages: [Message], startDelay: Int32?, betweenDelay: Int32?)

    /// The player's ad source by the product rule: OUR VIDEO ad for this channel post first; Telegram's
    /// `fallback` only when we have none and never for Premium; empty while "Remove all ads" is on.
    static func adState(context: AccountContext, message: Message, fallback: Signal<AdState, NoError>) -> Signal<AdState, NoError> {
        let empty: AdState = (interPostInterval: nil, messages: [], startDelay: nil, betweenDelay: nil)
        // Telegram's per-message context (messageId != nil) emits nothing until it gets a NON-empty answer
        // (its init sets the empty state without didSet, and an equal empty answer is not re-emitted), so
        // start the fallback empty: otherwise combineLatest in oursFirst would hold OUR ad back forever.
        let fallback: Signal<AdState, NoError> = .single(empty) |> then(fallback)
        return NovagramAdsCenter.oursFirst(context: context, surface: "VIDEO", ours: self.ourAdState(context: context, message: message), fallback: fallback, empty: empty, isEmpty: { state in
            return state.messages.isEmpty
        }, map: { state -> AdState in
            return state
        })
    }

    private static func ourAdState(context: AccountContext, message: Message) -> Signal<AdState?, NoError> {
        guard NovagramAdsCenter.isConfigured, message.id.namespace == Namespaces.Message.Cloud, message.id.id > 0, message.adAttribute == nil else {
            return .single(nil)
        }
        let peerId = message.id.peerId
        guard let channelId = NovagramChatAds.botApiChannelId(peerId), let channel = message.peers[peerId] as? TelegramChannel, case .broadcast = channel.info else {
            return .single(nil)
        }
        let slot: SDKAdSlot = .video(channelId: NovagramChatAds.requestChannelId(channelId), messageId: Int64(message.id.id))
        return NovagramAdsCenter.visibleAd(context: context, slot: slot)
        |> map { served -> AdState? in
            guard let served else {
                return nil
            }
            let timers = served.videoTimers ?? SDKAdVideoTimers.fallback
            let durations = (min: Int32(timers.minDisplayDuration.rounded()), max: Int32(timers.maxDisplayDuration.rounded()))
            let adMessage = NovagramAdMessage.make(served: served, peerId: peerId, chatPeer: channel, displayDurations: durations)
            return (interPostInterval: nil, messages: [adMessage], startDelay: Int32(timers.startDelay.rounded()), betweenDelay: Int32(timers.betweenDelay.rounded()))
        }
    }
}
