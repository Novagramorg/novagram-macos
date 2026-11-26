import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import TGUIKit
import ColorPalette
import InAppSettings
#if !SHARE
import InlineStickers
import TelegramTheme
import FetchManager
import Reactions
import DiceCache
import CaptureExclusion
#endif

public protocol AccountContextProtocol: AnyObject {
    associatedtype Shared: SharedAccountContextProtocol
    var sharedContext: Shared { get }

    var account: Account { get }
    var window: Window { get }
    var engine: TelegramEngine { get }
    var peerId: PeerId { get }
    var myPeer: Peer? { get }

    var isPremium: Bool { get }
    var isSupport: Bool { get }
    var isExternal: Bool { get }
    var timeDifference: TimeInterval { get }

    var appConfiguration: AppConfiguration { get }
    var limitConfiguration: LimitsConfiguration { get }
    var peerNameColors: PeerNameColors { get }
    var meUrlPrefix: String { get }
    var meUrlDisplayPrefix: String { get }
    var meUrlHost: String { get }

    var layout: SplitViewState { get }
    var timestamp: Int32 { get }
    var contentSettings: ContentSettings { get }
    var isCurrent: Bool { get }
    var recentlyUserPeerIds: Signal<[PeerId], NoError> { get }
    var cancelGlobalSearch: ValuePromise<Bool> { get }
    var bindings: AccountContextBindings { get }
    var isFrozen: Bool { get }

    #if !SHARE
    var peerChannelMemberCategoriesContextsManager: PeerChannelMemberCategoriesContextsManager { get }
    var premiumLimits: PremiumLimitConfig { get }
    var premiumOrder: PremiumPromoOrder { get }
    var globalPeerHandler: Promise<ChatLocation?> { get }
    var globalForumId: ValuePromise<PeerId?> { get }
    var globalLocationId: ChatLocation? { get }
    var diceCache: DiceCache { get }
    var captureExclusionManager: CaptureExclusionManager { get }
    var autoplayMedia: AutoplayMediaPreferences { get }
    var chatThemes: Signal<[(ChatTheme, TelegramPresentationTheme)], NoError> { get }
    var layoutValue: Signal<SplitViewState, NoError> { get }
    var isInGlobalSearch: Bool { get set }
    var closeFolderFirst: Bool { get set }
    var stickerSettings: StickerSettings { get }
    var emojiGameInfo: EmojiGameInfo { get }
    func chatLocationInput(for location: ChatLocation, contextHolder: Atomic<ChatLocationContextHolder?>) -> ChatLocationInput
    var audioTranscriptionTrial: AudioTranscription.TrialState { get }
    func chatLocationOutgoingReadState(for location: ChatLocation, contextHolder: Atomic<ChatLocationContextHolder?>) -> Signal<MessageId?, NoError>
    func chatLocationUnreadCount(for location: ChatLocation, contextHolder: Atomic<ChatLocationContextHolder?>) -> Signal<Int, NoError>
    func applyMaxReadIndex(for location: ChatLocation, contextHolder: Atomic<ChatLocationContextHolder?>, messageIndex: MessageIndex)
    func addRecentlyUsedPeer(peerId: PeerId)
    func checkFirstRecentlyForDuplicate(peerId: PeerId)
    #endif

    #if !SHARE
    var inlinePacksContext: InlineStickersContext { get }
    var giftAuctionsManager: GiftAuctionsManager { get }
    var debug: Bool { get }
    var privacy: Signal<AccountPrivacySettings?, NoError> { get }
    var premiumProductsAndPrice: ([PremiumGiftProduct], (Int64, NSDecimalNumber)) { get }
    func updateMessagesPrivacy(noPaidMessages: SelectivePrivacySettings, globalSettings: GlobalPrivacySettings)
    func currencyContext(_ currency: CurrencyAmount.Currency) -> StarsContext
    func marketComission(_ currency: CurrencyAmount.Currency) -> Double
    var emoticonThemes: [(ChatTheme, TelegramPresentationTheme)] { get }
    var temporaryPassword: String? { get }
    func setTemporaryPwd(_ password: String) -> Void
    func resetTemporaryPwd()
    #endif
    func isLite(_ key: LiteModeKey) -> Bool

    #if !SHARE
    var premiumIsBlocked: Bool { get }
    var contentConfig: ContentSettingsConfiguration { get set }
    var fetchManager: FetchManager { get }
    var inAppPurchaseManager: any InAppPurchaseManagerProtocol { get }
    var starsContext: StarsContext { get }
    var tonContext: StarsContext { get }
    var starsSubscriptionsContext: StarsSubscriptionsContext { get }
    var reactions: Reactions { get }
    var activeSessionsContext: ActiveSessionsContext { get }
    var blockedPeersContext: BlockedPeersContext { get }
    var webSessions: WebSessionsContext { get }
    var hasPassportSettings: Promise<Bool> { get }
    var isKeyWindow: Signal<Bool, NoError> { get }
    #endif
}

public extension AccountContextProtocol {
    func isLite() -> Bool {
        return isLite(.any)
    }
}
