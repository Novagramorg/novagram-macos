import Cocoa
import Postbox
import TGUIKit
import InAppSettings
import Localization
import AlertsUI

extension FastSettings {
    static func requstPermission(with permission: BotPemissionKey, for peerId: PeerId, success: @escaping()->Void) {
        let localizedHeader = _NSLocalizedString("Confirm.Header.\(permission.rawValue)")
        let localizedDesc = _NSLocalizedString("Confirm.Desc.\(permission.rawValue)")
        verifyAlert_button(for: mainWindow, header: localizedHeader, information: localizedDesc, successHandler: { _ in
            success()
        })
    }
}
