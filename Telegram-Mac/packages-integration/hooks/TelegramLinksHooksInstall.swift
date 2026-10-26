import Cocoa
import TGUIKit
import FenixuzCore // Fenixuz

func installTelegramLinksHooks() {
    LinkHooks.install(LinkHooks(callbackLink: { text, handler in
        return inAppLink.callback(text, handler)
    }, globalLinkExecutor: {
        return globalLinkExecutor
    }, openExternalLink: { link, confirm in
        if FenixuzAppStoreIAP.shouldBlockExternalPurchase(link: link) || link == strings().fragmentTonAddFundsLink { FenixuzAppStoreIAP.presentBlockedAlert(on: appDelegate?.currentContext?.window ?? mainWindow); return } // Fenixuz
        execute(inapp: .external(link: link, confirm))
    }, markdownLink: { contents in
        return inApp(for: contents.nsstring, context: appDelegate?.currentContext, openInfo: { peerId, _, _, _ in
            if let context = appDelegate?.currentContext {
                context.bindings.rootNavigation().push(ChatAdditionController(context: context, chatLocation: .peer(peerId)))
            }
        })
    }, externalLink: { link, confirm in
        return inAppLink.external(link: link, confirm)
    }, linkPayload: { value in
        if let value = value as? inAppLink, case let .external(link, _) = value {
            return link
        }
        return nil
    }, openAnyLink: { value in
        if let value = value as? inAppLink {
            execute(inapp: value)
        }
    }, detectLinks: { attributedString, type in
        attributedString.detectLinks(type: type)
    }))
}
