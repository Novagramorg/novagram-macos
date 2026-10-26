//
//  NovagramAdMessage.swift
//  Telegram-Mac
//
//  Builds the sponsored `Message` Telegram's own ad UI renders (channel bubble, bot panel, video
//  banner) in the same shape as TelegramCore's AdMessagesHistoryContext messages, so our ad goes
//  through Telegram-Mac's sponsored-message UI unchanged.
//  Port of iOS submodules/Novagram/NovagramAds/Sources/NovagramAdMessage.swift.
//

import Foundation
import Postbox
import TelegramCore
import NovagramCore
import NovagramAds

enum NovagramAdMessage {
    /// Telegram uses this synthetic author id for every sponsored message.
    private static let authorPeerId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(1))
    /// 16:9 default when the response has no media size, so the bubble reserves its frame early.
    private static let defaultDimensions = PixelDimensions(width: 1280, height: 720)

    /// - Parameter displayDurations: VIDEO slot only — min / max display duration (seconds), read by
    ///   the video banner's countdown and close button.
    static func make(served: SDKServedAd, peerId: PeerId, chatPeer: Peer?, displayDurations: (min: Int32, max: Int32)? = nil) -> Message {
        let ad = served.ad
        let contentMedia = self.contentMedia(ad)
        let otherInfo = ad.otherInfo.trimmingCharacters(in: .whitespacesAndNewlines)

        let adAttribute = AdMessageAttribute(
            opaqueId: NovagramAdsHooks.opaqueId(token: ad.randomId),
            messageType: .sponsored,
            url: ad.url,
            buttonText: self.buttonText(for: ad),
            sponsorInfo: otherInfo.isEmpty ? nil : otherInfo,
            additionalInfo: nil,
            canReport: true,
            hasContentMedia: contentMedia != nil,
            minDisplayDuration: displayDurations?.min,
            maxDisplayDuration: displayDurations?.max
        )

        var messagePeers = SimpleDictionary<PeerId, Peer>()
        if let chatPeer {
            messagePeers[chatPeer.id] = chatPeer
        }
        let author = self.author(title: ad.displayTitle)
        messagePeers[author.id] = author

        var media: [Media] = []
        if let contentMedia {
            media.append(contentMedia)
        }

        // A new random_id is a new showing, so the list must treat it as a changed item.
        let messageStableVersion = UInt32(bitPattern: Int32(truncatingIfNeeded: ad.randomId.hashValue))

        return Message(
            stableId: 0,
            stableVersion: messageStableVersion,
            id: MessageId(peerId: peerId, namespace: Namespaces.Message.Local, id: self.messageId(token: ad.randomId)),
            globallyUniqueId: nil,
            groupingKey: nil,
            groupInfo: nil,
            threadId: nil,
            timestamp: Int32.max - 1,
            flags: [.Incoming],
            tags: [],
            globalTags: [],
            localTags: [],
            customTags: [],
            forwardInfo: nil,
            author: author,
            text: ad.text,
            attributes: [adAttribute],
            media: media,
            peers: messagePeers,
            associatedMessages: SimpleDictionary<MessageId, Message>(),
            associatedMessageIds: [],
            associatedMedia: [:],
            associatedThreadInfo: nil,
            associatedStories: [:]
        )
    }

    /// The button under the channel bubble: the app translates button_type.
    static func buttonText(for ad: SDKSponsoredAd) -> String {
        let strings = NovagramL10n.current
        switch ad.buttonType {
        case .some(.bot):
            return strings.ads_openBot
        case .some(.channel):
            return strings.ads_viewChannel
        default:
            // .unknown, a future value, or no button type: fall back to the promoted peer's type.
            if case .bot = ad.promoted.type {
                return strings.ads_openBot
            }
            return strings.ads_viewChannel
        }
    }

    /// A positive, non-zero id derived from random_id (FNV-1a 32-bit). Telegram's own sponsored message
    /// uses id 0, so the bot panel (which compares messages) sees a switch between theirs and ours.
    static func messageId(token: String) -> Int32 {
        var hash: UInt32 = 2166136261
        for byte in token.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16777619
        }
        return Int32(bitPattern: hash & 0x7FFF_FFFF) | 1
    }

    private static func author(title: String) -> Peer {
        return TelegramChannel(
            id: self.authorPeerId,
            accessHash: nil,
            title: title,
            username: nil,
            photo: [],
            creationDate: 0,
            version: 0,
            participationStatus: .left,
            info: .broadcast(TelegramChannelBroadcastInfo(flags: [])),
            flags: [],
            restrictionInfo: nil,
            adminRights: nil,
            bannedRights: nil,
            defaultBannedRights: nil,
            usernames: [],
            storiesHidden: nil,
            nameColor: .blue,
            backgroundEmojiId: nil,
            profileColor: nil,
            profileBackgroundEmojiId: nil,
            emojiStatus: nil,
            approximateBoostLevel: nil,
            subscriptionUntilDate: nil,
            verificationIconFileId: nil,
            sendPaidMessageStars: nil,
            linkedMonoforumId: nil
        )
    }

    /// Stable media id for an immutable media url (FNV-1a 64-bit).
    private static func mediaId(namespace: Int32, url: URL) -> MediaId {
        var hash: UInt64 = 14695981039346656037
        for byte in url.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return MediaId(namespace: namespace, id: Int64(bitPattern: hash & 0x7FFF_FFFF_FFFF_FFFF))
    }

    /// PHOTO as a web image, VIDEO as a web mp4, both through HttpReferenceMediaResource (TelegramCore
    /// downloads the whole immutable file over HTTPS, keyed by url). Only https media is accepted.
    private static func contentMedia(_ ad: SDKSponsoredAd) -> Media? {
        guard let media = ad.media, let url = media.mediaURL, url.scheme == "https" else {
            return nil
        }
        var dimensions = self.defaultDimensions
        if let width = media.width, let height = media.height, width > 0, height > 0 {
            dimensions = PixelDimensions(width: Int32(clamping: width), height: Int32(clamping: height))
        }
        let resource = HttpReferenceMediaResource(url: url.absoluteString, size: nil)
        switch media.type {
        case .photo:
            let representation = TelegramMediaImageRepresentation(
                dimensions: dimensions,
                resource: resource,
                progressiveSizes: [],
                immediateThumbnailData: nil
            )
            return TelegramMediaImage(
                imageId: self.mediaId(namespace: Namespaces.Media.LocalImage, url: url),
                representations: [representation],
                immediateThumbnailData: nil,
                reference: nil,
                partialReference: nil,
                flags: []
            )
        case .video:
            let duration = media.duration.map { NSDecimalNumber(decimal: $0.value).doubleValue } ?? 0.0
            return TelegramMediaFile(
                fileId: self.mediaId(namespace: Namespaces.Media.LocalFile, url: url),
                partialReference: nil,
                resource: resource,
                previewRepresentations: [],
                videoThumbnails: [],
                videoCover: nil,
                immediateThumbnailData: nil,
                mimeType: "video/mp4",
                size: nil,
                attributes: [
                    .Video(duration: duration, size: dimensions, flags: [], preloadSize: nil, coverTime: nil, videoCodec: nil),
                    .FileName(fileName: "novagram-ad.mp4")
                ],
                alternativeRepresentations: []
            )
        case .unknown:
            return nil
        @unknown default:
            return nil
        }
    }
}
