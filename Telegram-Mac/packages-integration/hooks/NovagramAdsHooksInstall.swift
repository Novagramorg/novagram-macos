import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import ChatUI
import FenixuzCore

// Novagram ads v2: the SDK (packages/NovagramAdsBinary) is linked to the app only, so the app installs the
// closures that ChatUI, GalleryUI and ChatListUI call through NovagramAdsHooks.
func installNovagramAdsHooks() {
    var hooks = NovagramAdsHooks()
    hooks.showAds = {
        return NovagramAdsGate.showAds
    }
    hooks.withInjectedAd = { base, context, peerId in
        guard let context = context as? AccountContext else {
            return base
        }
        return NovagramChatAds.withInjectedAd(base, context: context, peerId: peerId)
    }
    hooks.hideIfOurs = { opaqueId in
        return NovagramAdsCenter.hideIfOurs(opaqueId: opaqueId)
    }
    hooks.recordViewIfOurs = { opaqueId in
        return NovagramAdsCenter.recordViewIfOurs(opaqueId: opaqueId)
    }
    hooks.recordClickIfOurs = { opaqueId in
        return NovagramAdsCenter.recordClickIfOurs(opaqueId: opaqueId)
    }
    hooks.recordVideoOpenIfOurs = { opaqueId in
        return NovagramAdsCenter.recordVideoOpenIfOurs(opaqueId: opaqueId)
    }
    hooks.reportClickIfOurs = { opaqueId, _ in
        return NovagramAdsCenter.recordClickIfOurs(opaqueId: opaqueId)
    }
    hooks.menuItems = { opaqueId, window in
        return NovagramAdMenu.items(opaqueId: opaqueId, window: window)
    }
    hooks.menu = { opaqueId, window, presentation in
        return NovagramAdMenu.menu(opaqueId: opaqueId, window: window, presentation: presentation)
    }
    hooks.openMediaIfOurs = { message, media, context, delegate, parameters in
        guard NovagramAdsHooks.isOurs(message: message), let context = context as? AccountContext else {
            return false
        }
        return NovagramChatAds.openMediaIfOurs(message: message, media: media, context: context, delegate: delegate as? InteractionContentViewProtocol, parameters: parameters as? ChatMediaLayoutParameters)
    }
    hooks.videoAdState = { context, message, fallback in
        guard let context = context as? AccountContext else {
            return fallback
        }
        return NovagramVideoAds.adState(context: context, message: message, fallback: fallback)
    }
    installNovagramBannerAdsHooks(&hooks)
    installNovagramSearchAdsHooks(&hooks)
    NovagramAdsHooks.install(hooks)
}

private func installNovagramBannerAdsHooks(_ hooks: inout NovagramAdsHooks) {
    hooks.bannerSuggestions = { context, telegram in
        guard let context = context as? AccountContext else {
            return telegram
        }
        return NovagramBannerAds.suggestions(context: context, telegram: telegram)
    }
    hooks.bannerOpenIfOurs = { noticeId, context in
        guard let context = context as? AccountContext else {
            return NovagramBannerAds.isOurs(noticeId: noticeId)
        }
        return NovagramBannerAds.openIfOurs(noticeId: noticeId, context: context)
    }
    hooks.bannerDismissIfOurs = { noticeId, context in
        guard let context = context as? AccountContext else {
            return NovagramBannerAds.isOurs(noticeId: noticeId)
        }
        return NovagramBannerAds.dismissIfOurs(noticeId: noticeId, context: context)
    }
    hooks.bannerIsOurs = { noticeId in
        return NovagramBannerAds.isOurs(noticeId: noticeId)
    }
    hooks.bannerCanDismiss = { noticeId in
        return NovagramBannerAds.canDismiss(noticeId: noticeId)
    }
}

private func installNovagramSearchAdsHooks(_ hooks: inout NovagramAdsHooks) {
    hooks.promotedSearchPeer = { context, query in
        guard let context = context as? AccountContext else {
            return .single(nil)
        }
        return NovagramSearchAds.promotedChannel(context: context, query: query)
    }
    hooks.searchTelegramFallback = { context, query, telegram in
        guard let context = context as? AccountContext else {
            return telegram
        }
        return NovagramSearchAds.telegramFallback(context: context, query: query, telegram: telegram)
    }
    hooks.searchAdLabel = {
        return NovagramSearchAds.adLabel
    }
    hooks.searchAdMenu = { token, window in
        return NovagramAdMenu.menu(token: token, window: window)
    }
    hooks.searchRecordView = { token in
        NovagramSearchAds.recordView(token: token)
    }
    hooks.searchRecordClick = { token in
        NovagramSearchAds.recordClick(token: token)
    }
}
