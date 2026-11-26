import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import PaymentsUI

func installPaymentsUIHooks() {
    installPaymentsHooks(.init(formatPhoneNumber: { context, number in
        guard let context = context as? AccountContext else {
            return number
        }
        return formatPhoneNumber(context: context, number: number)
    }, meUrlHost: {
        return appDelegate?.currentContext?.meUrlHost

    }))
}
