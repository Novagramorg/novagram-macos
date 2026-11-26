import Cocoa
import InputDataUI
import TGUIKit
import InAppSettings

extension InputTextDataRowView: @retroactive InputDataTextFormatting {
}

func installInputDataUIHooks() {
    InputDataUIHooks.install(InputDataUIHooks(
        checkSendingAbility: { FastSettings.checkSendingAbility(for: $0) },
        mainWindow: { mainWindow },
        showAlert: { alert(for: $0, info: $1) },
        showModalText: { showModalText(for: $0, text: $1) },
        detectExternalURL: { candidate in
            let attributed = NSMutableAttributedString(string: candidate)
            attributed.detectLinks(type: [.Links])
            var url: String?
            attributed.enumerateAttribute(.link, in: attributed.range, options: [], using: { value, _, stop in
                if let value = value as? inAppLink, case let .external(link, _) = value {
                    url = link
                }
                stop.pointee = ObjCBool(url != nil)
            })
            return url
        },
        makeLoadingRow: { SearchEmptyRowItem($0, stableId: $1, isLoading: true) }
    ))
}
