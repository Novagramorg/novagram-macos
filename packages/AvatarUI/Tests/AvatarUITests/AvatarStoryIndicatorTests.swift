import XCTest
import Cocoa
import TGUIKit
import ColorPalette
import Postbox
import TelegramCore
import AvatarUI

final class AvatarStoryIndicatorTests: XCTestCase {
    private func channel(forum: Bool) -> Peer {
        return TelegramChannel(id: PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(1)), accessHash: nil, title: "Channel", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: .group(.init(flags: [])), flags: forum ? [.isForum] : [], restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    private func forumBot() -> Peer {
        return TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(2)), accessHash: nil, firstName: "Bot", lastName: nil, username: nil, phone: nil, photo: [], botInfo: BotUserInfo(flags: [.hasForum], inlinePlaceholder: nil), restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    private func component(peer: Peer, active: Bool = false, rounded: Bool? = nil) throws -> AvatarStoryIndicatorComponent {
        let image = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        let presentation = PresentationTheme(colors: whitePalette, search: SearchTheme(.clear, image, image, { "" }, .black, .gray), inputTheme: .init(quote: .init(foreground: .init(main: .blue), icon: NSImage(), collapse: NSImage(), expand: NSImage()), indicatorColor: .blue, backgroundColor: .white, selectingColor: .blue, textColor: .black, accentColor: .blue, grayTextColor: .gray, fontSize: 13))
        let story = EngineStorySubscriptions.Item(peer: EnginePeer(peer), hasUnseen: true, hasUnseenCloseFriends: true, hasLiveItems: false, hasPending: false, storyCount: 5, unseenCount: 2, lastTimestamp: 0)
        return AvatarStoryIndicatorComponent(story: story, presentation: presentation, active: active, isRoundedRect: rounded)
    }

    func testDefaultShapeUsesOnlyForumChannels() throws {
        XCTAssertTrue(try component(peer: channel(forum: true)).isRoundedRect)
        XCTAssertFalse(try component(peer: channel(forum: false)).isRoundedRect)
        let bot = forumBot()
        XCTAssertTrue(bot.isForum)
        XCTAssertFalse(try component(peer: bot).isRoundedRect)
    }

    func testExplicitShapeOverridesPeerClassification() throws {
        XCTAssertFalse(try component(peer: channel(forum: true), rounded: false).isRoundedRect)
        XCTAssertTrue(try component(peer: forumBot(), rounded: true).isRoundedRect)
    }

    func testActiveStoryKeepsExistingCounterSemantics() throws {
        let peer = channel(forum: true)
        XCTAssertEqual(try component(peer: peer).counters, .init(totalCount: 5, unseenCount: 2))
        XCTAssertEqual(try component(peer: peer, active: true).counters, .init(totalCount: 5, unseenCount: 5))
    }
}
