
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import InputDataUI


private final class Arguments {
    let context: any AccountContextProtocol
    init(context: any AccountContextProtocol) {
        self.context = context
    }
}

private struct State : Equatable {

}


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []

    var sectionId:Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

public func TemplateController(context: any AccountContextProtocol) -> InputDataController {

    let actionsDisposable = DisposableSet()

    let initialState = State()

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }

    var getController:(()->ViewController?)? = nil

    var window:Window {
        get {
            return bestWindow(context, getController?())
        }
    }

    let arguments = Arguments(context: context)

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: " ")

    getController = { [weak controller] in
        return controller
    }

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    return controller

}

public func TemplateModalController(context: any AccountContextProtocol) -> InputDataModalController {

    let controller = TemplateController(context: context)

    var close:(()->Void)? = nil

    let modalInteractions = ModalInteractions(acceptTitle: strings().modalDone, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: {
        close?()
    })

    close = { [weak modalController] in
        modalController?.modal?.close()
    }

    return modalController
}
