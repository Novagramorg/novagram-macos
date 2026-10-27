import Cocoa
import TGUIKit
import SwiftSignalKit
import Foundation
import Postbox
import TelegramCore
import PremiumStatusUI
import InputDataUI
import GeneralRows
import TelegramUtils
import TelegramContext
import TelegramTheme
import Localization




public func alert(for window:Window, header:String? = appName, info:String?, ok: String = strings().modalOK, disclaimer: String? = nil, completion: (()->Void)? = nil, onDeinit:(()->Void)? = nil, presentation: TelegramPresentationTheme = theme) { // Novagram
    
    
    let data = ModalAlertData(title: header, info: info ?? "", ok: ok, options: [], disclaimer: disclaimer)
    
    showModalAlert(for: window, data: data, completion: { _ in
        completion?()
    }, onDeinit: onDeinit, presentation: presentation)
    
}

public enum ConfirmResult {
    case thrid
    case basic
}

public func verifyAlert_button(for window:Window, header: String = appName, information:String?, ok:String = strings().alertOK, cancel:String = strings().alertCancel, option:String? = nil, successHandler:@escaping (ConfirmResult)->Void, cancelHandler: @escaping()->Void = { }, presentation: TelegramPresentationTheme = theme, onDeinit: @escaping()->Void = {}) {

    verifyAlert(for: window, header: header, information: information, ok: ok, cancel: cancel, option: option, optionIsSelected: nil, successHandler: successHandler, cancelHandler: cancelHandler, presentation: presentation, onDeinit: onDeinit)
}

public func verifyAlert(for window:Window, header: String = appName, information:String? = nil, ok:String = strings().alertOK, cancel:String = strings().alertCancel, option:String? = nil, optionIsSelected: Bool? = true, successHandler:@escaping(ConfirmResult)->Void, cancelHandler:@escaping()->Void = { }, presentation: TelegramPresentationTheme = theme, onDeinit: @escaping()->Void = {}, headerItem: ModalAlertData.Header? = nil) {
    
    
    var options: [ModalAlertData.Option] = []
    
    if let string = option, optionIsSelected != nil {
        options.append(.init(string: string, isSelected: optionIsSelected == true))
    }
    let mode: ModalAlertData.Mode
    if let option = option, optionIsSelected == nil {
        mode = .confirm(text: option, isThird: true)
    } else {
        mode = .confirm(text: cancel, isThird: false)
    }
    
    let data: ModalAlertData = .init(title: header, info: information ?? "", description: nil, ok: ok, options: options, mode: mode, header: headerItem)
    
    
    showModalAlert(for: window, data: data, completion: { result in
        if result.selected.isEmpty {
            successHandler(.basic)
        } else {
            if result.selected[0] == true {
                successHandler(.thrid)
            } else {
                successHandler(.basic)
            }
        }
    }, cancel: cancelHandler, onDeinit: onDeinit, presentation: presentation)
    
}

public func verifyAlertSignal(for window:Window, header: String = appName, information:String? = nil, ok:String = strings().alertOK, cancel:String = strings().alertCancel, option: String? = nil, optionIsSelected: Bool = true, presentation: TelegramPresentationTheme = theme, headerItem: ModalAlertData.Header? = nil, completeWhenDismissed: Bool = false) -> Signal<ConfirmResult?, NoError> {
    let value:ValuePromise<ConfirmResult?> = ValuePromise(ignoreRepeated: true)
    let dismissed = DisposableSet()
    
    verifyAlert(for: window, header: header, information: information, ok: ok, cancel: cancel, option: option, optionIsSelected: optionIsSelected, successHandler: { response in
         value.set(response)
    }, cancelHandler: {
        value.set(nil)
    }, presentation: presentation, onDeinit: {
        dismissed.dispose()
    }, headerItem: headerItem)
    
    let result = value.get() |> take(1)
    
    if completeWhenDismissed {
        return Signal { subscriber in
            let disposable = result.start(next: { response in
                subscriber.putNext(response)
            }, completed: {
                subscriber.putCompletion()
            })
            dismissed.add(ActionDisposable {
                disposable.dispose()
                subscriber.putCompletion()
            })
            return disposable
        }
    }
    
    return result
    
}
