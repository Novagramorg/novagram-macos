import Foundation
import SwiftSignalKit
import TGUIKit
import TelegramCore
import CodeSyntax
import Postbox

func installMessagePermissionsHooks() {
    installMessagePermissionHooks(.init(canSendMessage: { peer, isThreadMode, threadData in
        return peer.canSendMessage(isThreadMode, threadData: threadData)
    }))
}

func installMessageTextUtilsHooks() {
    installMessageTextHooks(.init(currentContext: {
        return appDelegate?.currentContext
    }))
}

func installDateSelectorUIHooks() {
    installDateSelectorHooks(.init(showPremiumBoarding: { window in
        if let context = appDelegate?.currentContext {
            prem(with: PremiumBoardingController(context: context), for: window)
        }
    }))
}

func installInstantPageUIHooks() {
    installInstantPageHooks(.init(highlightCode: { code, language, isDark, textColor, textFont, italicFont, mediumFont, themeKeys in
        guard let theme = SyntaxterTheme(dark: isDark, textColor: textColor, textFont: textFont, italicFont: italicFont, mediumFont: mediumFont, themeKeys: themeKeys) else {
            return nil
        }
        return CodeSyntax.syntax(code: code, language: language, theme: theme)
    }, makeAudioItem: { frame, media in
        return InstantPageAudioItem(frame: frame, media: media)
    }, openPeer: { context, peerId, openChat, messageId, action in
        guard let context = context as? AccountContext else {
            return
        }
        if openChat {
            context.bindings.rootNavigation().push(ChatController(context: context, chatLocation: .peer(peerId), focusTarget: .init(messageId: messageId), initialAction: action))
        } else {
            PeerInfoController.push(navigation: context.bindings.rootNavigation(), context: context, peerId: peerId)
        }
    }, openUrl: { context, url, webpageId, progress, openPeer, setDisposable in
        guard let context = context as? AccountContext else {
            return
        }
        setDisposable(nil)
        progress(0.07)
        let result = inApp(for: url.nsstring, context: context, openInfo: { peerId, openChat, messageId, initialAction in
            openPeer(peerId, openChat, messageId, initialAction)
        }, applyProxy: { proxy in
            applyExternalProxy(proxy, accountManager: context.sharedContext.accountManager)
        })
        switch result {
        case let .external(externalUrl, _):
            if let webpageId = webpageId {
                var anchor: String?
                if let anchorRange = externalUrl.range(of: "#") {
                    anchor = String(externalUrl[anchorRange.upperBound...])
                }
                setDisposable((webpagePreviewWithProgress(account: context.account, urls: [externalUrl], webpageId: webpageId) |> deliverOnMainQueue).start(next: { result in
                    switch result {
                    case let .result(webpage):
                        if let webpage = webpage {
                            progress(1.0)
                            BrowserStateContext.get(context).open(tab: .instantView(url: externalUrl, webPage: webpage.webpage, anchor: anchor))
                        }
                    case let .progress(value):
                        progress(CGFloat(0.07 + value * (1.0 - 0.07)))
                    }
                }))
            } else {
                progress(1.0)
                execute(inapp: result)
            }
        default:
            progress(1.0)
            execute(inapp: result)
        }
    }, audioPlayer: {
        return appDelegate?.sharedApplicationContextValue?.sharedContext.getAudioPlayer()
    }, showGallery: { context, medias, firstIndex, interactive in
        guard let context = context as? AccountContext else {
            return
        }
        showInstantViewGallery(context: context, medias: medias, firstIndex: firstIndex, interactive as? InteractionContentViewProtocol)
    }, shareLink: { context, link, window in
        guard let context = context as? AccountContext else {
            return
        }
        showModal(with: ShareModalController(ShareLinkObject(context, link: link)), for: window)
    }))
}
