import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import InputDataUI
import GeneralRows
import Localization
import TelegramTheme
import NovagramCore

private let _id_novagram_proxy = InputDataIdentifier("_id_novagram_proxy")

// NovagramProxy switch at the top of Proxy Settings: connects through an auto-selected proxy
// from the bundled pool, for regions where Telegram is blocked. Reachable from the login screen too.
func novagramProxyEntries(sectionId: inout Int32, index: inout Int32, enabled: Bool, accountManager: AccountManager<TelegramAccountManagerTypes>) -> [InputDataEntry] {
    let lang = appCurrentLanguage.languageCode
    var entries: [InputDataEntry] = []
    entries.append(.custom(sectionId: sectionId, index: index, value: .string(nil), identifier: _id_novagram_proxy, equatable: InputDataEquatable(enabled), comparable: nil, item: { initialSize, stableId in
        return GeneralInteractedRowItem(initialSize, stableId: stableId, name: NovagramAutoProxyStrings.toggleTitle(langCode: lang), type: .switchable(enabled), viewType: .singleItem, action: {
            NovagramAutoProxyManager.shared.setEnabled(!enabled, accountManager: accountManager)
        })
    }))
    index += 1
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(NovagramAutoProxyStrings.toggleTip(langCode: lang)), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    return entries
}
