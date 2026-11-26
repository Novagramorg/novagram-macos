import Cocoa
import SwiftSignalKit
import Postbox
import TelegramCore
import TGUIKit
import Localization
import TelegramContext



private func extractAnchor(string: String) -> (String, String?) {
    var anchorValue: String?
    if let anchorRange = string.range(of: "#") {
        let anchor = string[anchorRange.upperBound...]
        if !anchor.isEmpty {
            anchorValue = String(anchor)
        }
    }
    var trimmedUrl = string
    if let anchor = anchorValue, let anchorRange = string.range(of: "#\(anchor)") {
        let url = string[..<anchorRange.lowerBound]
        if !url.isEmpty {
            trimmedUrl = String(url)
        }
    }
    return (trimmedUrl, anchorValue)
}

private let refreshTimeout: Int32 = 60 * 60 * 12

func cachedFaqInstantPage(context: any AccountContextProtocol) -> Signal<SettingsSearchInAppLinkValue, NoError> {
    let faqUrl = localizedFaqUrl()

    
    let (cachedUrl, anchor) = extractAnchor(string: faqUrl)
    
    return SettingsNavigationHooks.shared.cachedInstantPage(context, cachedUrl)
        |> mapToSignal { cachedInstantPage -> Signal<SettingsSearchInAppLinkValue, NoError> in
            let updated = SettingsHooks.shared.resolveInstantViewUrl(context.account, faqUrl)
                |> afterNext { result in
                    if case let .instantView(_, webPage, _) = result.settingsSearchInAppLink, case let .Loaded(content) = webPage.content, let instantPage = content.instantPage {
                        if instantPage.isComplete {
                            let _ = SettingsNavigationHooks.shared.updateCachedInstantPage(context, cachedUrl, webPage).start()
                        } else {
                            let _ = (actualizedWebpage(account: context.account, webpage: webPage)
                                |> mapToSignal { webPage -> Signal<Void, NoError> in
                                    if case let .Loaded(content) = webPage.content, let instantPage = content.instantPage, instantPage.isComplete {
                                        return SettingsNavigationHooks.shared.updateCachedInstantPage(context, cachedUrl, webPage)
                                    } else {
                                        return .complete()
                                    }
                                }).start()
                        }
                    }
            }
            
            let now = Int32(CFAbsoluteTimeGetCurrent())
            if let cachedInstantPage = cachedInstantPage, case let .Loaded(content) = cachedInstantPage.webPage.content, let instantPage = content.instantPage, instantPage.isComplete {
                let current: Signal<SettingsSearchInAppLinkValue, NoError> = .single(SettingsHooks.shared.instantViewInAppLink(faqUrl, cachedInstantPage.webPage, anchor))
                if now > cachedInstantPage.timestamp + refreshTimeout {
                    return current
                        |> then(updated)
                } else {
                    return current
                }
            } else {
                return updated
            }
    }
}

func faqSearchableItems<Context: AccountContextProtocol>(context: Context) -> Signal<[SettingsSearchableItem<Context>], NoError> {
    return cachedFaqInstantPage(context: context)
        |> map { resolvedUrl -> [SettingsSearchableItem<Context>] in
            var results: [SettingsSearchableItem<Context>] = []
            var nextIndex: Int32 = 2
            if case let .instantView(_, webPage, _) = resolvedUrl.settingsSearchInAppLink {
                if case let .Loaded(content) = webPage.content, let instantPage = content.instantPage {
                    var processingQuestions = false
                    var currentSection: String?
                    outer: for block in instantPage._parse().blocks {
                        if !processingQuestions {
                            switch block {
                            case .blockQuote:
                                if results.isEmpty {
                                    processingQuestions = true
                                }
                            default:
                                break
                            }
                        } else {
                            switch block {
                            case let .paragraph(text):
                                if case .bold = text {
                                    currentSection = text.plainText
                                } else if case .concat = text {
                                    processingQuestions = false
                                }
                            case let .list(items, false):
                                if let currentSection = currentSection {
                                    for item in items {
                                        if case let .text(itemText, _, _) = item, case let .url(text, url, _) = itemText {
                                            let (_, anchor) = extractAnchor(string: url)
                                            var index = nextIndex
                                            if anchor?.contains("delete-my-account") ?? false {
                                                index = 1
                                            } else {
                                                nextIndex += 1
                                            }
                                            let item = SettingsSearchableItem<Context>(id: .faq(index), title: text.plainText, alternate: [], icon: .faq, breadcrumbs: [strings().accountSettingsFAQ, currentSection], present: { context, _, present in
                                                SettingsNavigationHooks.shared.openInstantView(context, url, webPage, anchor)
                                            })
                                            if index == 1 {
                                                results.insert(item, at: 0)
                                            } else {
                                                results.append(item)
                                            }
                                        }
                                    }
                                }
                            default:
                                break
                            }
                        }
                    }
                }
            }
            return results
    }
}
