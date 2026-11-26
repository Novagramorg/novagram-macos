import Cocoa
import TelegramCore

import SwiftSignalKit
import Postbox
import TGUIKit
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AlertsUI
import LocalAnimations
import TelegramIconsTheme
import SystemPermissions
import TelegramMediaUtils


public func CallSettingsModalController(_ sharedContext: any SharedAccountContextProtocol, presentation: TelegramPresentationTheme = theme) -> InputDataModalController {
    
    var close: (()->Void)? = nil

    
    let controller = CallSettingsController(sharedContext: sharedContext, presentation: presentation)
    
    controller.getBackgroundColor = {
        return presentation.colors.listBackground
    }
    
    controller.leftModalHeader = ModalHeaderData(image: presentation.icons.modalClose, handler: {
        close?()
    })

    let modalController = InputDataModalController(controller, presentation: presentation)

    modalController._hasBorder = false
    
    modalController.getModalTheme = {
        .init(text: presentation.colors.text, grayText: presentation.colors.grayText, background: .clear, border: .clear, accent: presentation.colors.accent, grayForeground: .clear, activeBackground: presentation.colors.background, activeBorder: presentation.colors.border, listBackground: .clear)
    }
    modalController.getHeaderBorderColor = {
        return presentation.colors.border
    }

    
    close = { [weak modalController] in
        modalController?.close()
    }
    
    return modalController
    
}
