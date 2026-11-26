import Cocoa
import TGUIKit
#if SHARE
import TelegramUtilsShare
typealias TelegramGenericViewController<T: NSView> = TelegramUtilsShare.TelegramGenericViewController<T, AccountContext>
typealias TelegramViewController = TelegramUtilsShare.TelegramViewController<AccountContext>
typealias TableViewController = TelegramUtilsShare.TableViewController<AccountContext>
typealias EditableViewController<T: NSView> = TelegramUtilsShare.EditableViewController<T, AccountContext>
#else
import TelegramUtils
typealias TelegramGenericViewController<T: NSView> = TelegramUtils.TelegramGenericViewController<T, AccountContext>
typealias TelegramViewController = TelegramUtils.TelegramViewController<AccountContext>
typealias TableViewController = TelegramUtils.TableViewController<AccountContext>
typealias EditableViewController<T: NSView> = TelegramUtils.EditableViewController<T, AccountContext>
typealias PasscodeSettingsViewController = PasscodeUI.PasscodeSettingsViewController<AccountContext>
typealias RecentSessionsController = SessionsUI.RecentSessionsController<AccountContext>
typealias WebSessionsController = SessionsUI.WebSessionsController<AccountContext>
typealias SecretChatKeyViewController = PeerInfoUI.SecretChatKeyViewController<AccountContext>
typealias BlockedPeersViewController = SettingsUI.BlockedPeersViewController<AccountContext>
typealias ChannelStatisticsController = StatisticsUI.ChannelStatisticsController<AccountContext>
typealias DownloadSettingsViewController = DataUsageUI.DownloadSettingsViewController<AccountContext>
typealias LinkInvationController = InviteLinksUI.LinkInvationController<AccountContext>
typealias PrivacyAndSecurityViewController = SettingsUI.PrivacyAndSecurityViewController<AccountContext>
typealias SelectivePrivacySettingsController = SettingsUI.SelectivePrivacySettingsController<AccountContext>
typealias SelectivePrivacySettingsPeersController = SettingsUI.SelectivePrivacySettingsPeersController<AccountContext>
typealias GeneralSettingsViewController = SettingsUI.GeneralSettingsViewController<AccountContext>
typealias DataAndStorageViewController = DataUsageUI.DataAndStorageViewController<AccountContext>
typealias EmptyComposeController<I, T, R: NSView> = SelectPeersUI.EmptyComposeController<I, T, R, AccountContext>
typealias ComposeViewController<T, I, V: NSView> = SelectPeersUI.ComposeViewController<T, I, V, AccountContext>
typealias RecentCallsViewController = CallsUI.RecentCallsViewController<AccountContext>
typealias InstalledStickerPacksController = StickerSettingsUI.InstalledStickerPacksController<AccountContext>
typealias ArchivedStickerPacksController = StickerSettingsUI.ArchivedStickerPacksController<AccountContext>
typealias FeaturedStickerPacksController = StickerSettingsUI.FeaturedStickerPacksController<AccountContext>
typealias EmptyChatViewController = WidgetUI.EmptyChatViewController<AccountContext>
typealias StorageUsageController = DataUsageUI.StorageUsageController<AccountContext>
typealias ChatController = ChatUI.ChatController<AccountContext>
typealias ChatAdditionController = ChatUI.ChatAdditionController<AccountContext>
typealias ChatScheduleController = ChatUI.ChatScheduleController<AccountContext>
typealias EmojiesController = EntertainmentUI.EmojiesController<AccountContext>
typealias NStickersViewController = EntertainmentUI.NStickersViewController<AccountContext>
typealias EntertainmentViewController = EntertainmentUI.EntertainmentViewController<AccountContext>
typealias PeerMediaListController = PeerMediaUI.PeerMediaListController<AccountContext>
typealias PeerMediaPhotosController = PeerMediaUI.PeerMediaPhotosController<AccountContext>
typealias InstantViewInBrowser = WebAppUI.InstantViewInBrowser<AccountContext>
typealias PremiumStatusController = EntertainmentUI.PremiumStatusController<AccountContext>
typealias SetupQuickReactionController = EntertainmentUI.SetupQuickReactionController<AccountContext>
typealias PeersListController = ChatListUI.PeersListController<AccountContext>
typealias ChatListController = ChatListUI.ChatListController<AccountContext>
typealias CommunityListController = ChatListUI.CommunityListController<AccountContext>
typealias ContactsController = ChatListUI.ContactsController<AccountContext>
typealias ChannelAdminsViewController = ChannelAdminUI.ChannelAdminsViewController<AccountContext>
typealias ChannelEventLogController = ChannelAdminUI.ChannelEventLogController<AccountContext>
typealias ChannelPermissionsController = PeerModerationUI.ChannelPermissionsController<AccountContext>
typealias ChannelBlacklistViewController = PeerModerationUI.ChannelBlacklistViewController<AccountContext>
typealias ChannelMembersViewController = PeerModerationUI.ChannelMembersViewController<AccountContext>
typealias GroupStickerSetController = ChannelSettingsUI.GroupStickerSetController<AccountContext>
typealias ChannelVisibilityController = ChannelSettingsUI.ChannelVisibilityController<AccountContext>
typealias AccountViewController = SettingsUI.AccountViewController<AccountContext>
typealias PeerInfoController = PeerInfoUI.PeerInfoController<AccountContext>
typealias PeerMediaController = PeerInfoUI.PeerMediaController<AccountContext>
typealias StoryMediaController = StoriesUI.StoryMediaController<AccountContext>
typealias StoryModalController = StoriesUI.StoryModalController<AccountContext>
#endif

func installTelegramUtilsHooks() {
    installTelegramContextHooks(.init(peerTitle: { $0.displayTitle }))
    #if SHARE
    TelegramUtilsHooks.install(.init(animationsAreLite: { false }, isLite: { _ in false }, peerTitle: { $0.displayTitle }, peerLetters: { $0.displayLetters }, peerIsForum: { $0.isForum }, peerCompactTitle: { $0.compactDisplayTitle }, repliesPeerId: { repliesPeerId }))
    #else
    TelegramUtilsHooks.install(.init(animationsAreLite: { isLite(.animations) }, isLite: { isLite($0) }, peerTitle: { $0.displayTitle }, peerLetters: { $0.displayLetters }, peerIsForum: { $0.isForum }, peerCompactTitle: { $0.compactDisplayTitle }, repliesPeerId: { repliesPeerId }, topicFile: { title, color, general in
        ForumUI.makeIconFile(title: title, iconColor: color, isGeneral: general)
    }, topicImage: { title, backgroundColors, strokeColors in
        makeTopicIcon(title, bgColors: backgroundColors, strokeColors: strokeColors)
    }, generalTopicImage: { resource, scale in
        makeGeneralTopicIcon(resource, scale: scale)
    }))
    #endif
}
