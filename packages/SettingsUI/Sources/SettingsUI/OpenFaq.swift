import Cocoa
import TelegramCore
import Localization
import Postbox
import SwiftSignalKit
import TGUIKit
import InAppSettings
import ColorPalette
import ThemeSettings
import TelegramContext
import TelegramUtils

private let localizedFaqLanguages: Set<String> = ["ar", "de", "es", "fa", "fr", "he", "id", "it", "kk", "ko", "ms", "nl", "pl", "pt-br", "tr", "uk"]

func localizedFaqUrl() -> String {
    let language = appCurrentLanguage.languageCode
    if localizedFaqLanguages.contains(language) {
        return "https://telegram.org/faq/" + language
    } else {
        return "https://telegram.org/faq#general-questions"
    }
}

public func openFaq(context: any AccountContextProtocol) {
    _ = showModalProgress(signal: cachedFaqInstantPage(context: context) |> take(1) |> deliverOnMainQueue, for: context.window).start(next: { resolvedUrl in
        if case let .instantView(link, webPage, anchor) = resolvedUrl.settingsSearchInAppLink {
            SettingsNavigationHooks.shared.openInstantView(context, link, webPage, anchor)
        } else {
            SettingsHooks.shared.executeInAppLink(resolvedUrl)
        }
    })
}
