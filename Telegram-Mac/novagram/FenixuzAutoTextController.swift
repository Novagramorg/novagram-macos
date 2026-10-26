//
//  FenixuzAutoTextController.swift
//  Telegram-Mac
//
//  iOS portasi: submodules/Fenixuz/ProMessager/Sources/FenixAutoTextController.swift
//
//  Mac AppKit port, built on InputDataController (GeneralInputRowItem is gone in 13.x). "Auto-text" feature: when enabled, an opt-in suffix is
//  appended to every outgoing message.
//
//  Storage (parity with iOS):
//    UserDefaults(suiteName: "pro_messager")
//      "auto_text_enabled"  Bool   (default: false)
//      "auto_text_content"  String (default: "")
//
//  Posts FenixSettingsChanged notification when either field changes so the
//  Mac chat-input consumer (future wave) can re-read.

import Cocoa
import TGUIKit
import TelegramCore
import Localization
import SwiftSignalKit
import FenixuzCore
import InputDataUI
import GeneralRows
import TelegramTheme

// MARK: - Storage

private let kAutoTextSuite     = "pro_messager"
private let kAutoTextEnabled   = "auto_text_enabled"
private let kAutoTextContent   = "auto_text_content"

// MARK: - State + Arguments

private struct AutoTextState: Equatable {
    var isEnabled: Bool
    var content: String

    static func load() -> AutoTextState {
        let d = UserDefaults(suiteName: kAutoTextSuite)
        return AutoTextState(
            isEnabled: d?.bool(forKey: kAutoTextEnabled) ?? false,
            content:   d?.string(forKey: kAutoTextContent) ?? ""
        )
    }
}

private final class AutoTextArguments {
    let updateEnabled: (Bool) -> Void
    init(updateEnabled: @escaping (Bool) -> Void) {
        self.updateEnabled = updateEnabled
    }
}

private let _id_auto_text_toggle = InputDataIdentifier("_id_auto_text_toggle")
private let _id_auto_text_input = InputDataIdentifier("_id_auto_text_input")
private let autoTextLimit: Int32 = 300

private func autoTextEntries(state: AutoTextState, arguments: AutoTextArguments) -> [InputDataEntry] {
    let l10n = FenixuzL10n(languageCode: appCurrentLanguage.languageCode)
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(l10n.autoText_info), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_auto_text_toggle, data: .init(name: l10n.autoText_toggleTitle, color: theme.colors.text, type: .switchable(state.isEnabled), viewType: .singleItem, description: l10n.autoText_toggleSubtitle, action: {
        arguments.updateEnabled(!state.isEnabled)
    })))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(l10n.autoText_inputHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    entries.append(.input(sectionId: sectionId, index: index, value: .string(state.content), error: nil, identifier: _id_auto_text_input, mode: .plain, data: InputDataRowData(viewType: .singleItem), placeholder: nil, inputPlaceholder: l10n.autoText_inputPlaceholder, filter: { $0 }, limit: autoTextLimit))
    index += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(l10n.autoText_inputHint), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

// MARK: - Controller

func FenixuzAutoTextController(_ context: AccountContext) -> InputDataController {
    let initialState = AutoTextState.load()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((AutoTextState) -> AutoTextState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    let defaults = UserDefaults(suiteName: kAutoTextSuite)

    let arguments = AutoTextArguments(updateEnabled: { value in
        defaults?.set(value, forKey: kAutoTextEnabled)
        updateState { current in
            var current = current
            current.isEnabled = value
            return current
        }
        NotificationCenter.default.post(name: NSNotification.Name("FenixSettingsChanged"), object: nil)
    })

    let signal = combineLatest(queue: prepareQueue, statePromise.get(), appearanceSignal)
        |> map { state, _ in
            return InputDataSignalValue(entries: autoTextEntries(state: state, arguments: arguments))
        }

    return InputDataController(dataSignal: signal, title: FenixuzL10n.current.autoText_screenTitle, updateDatas: { data in
        guard let text = data[_id_auto_text_input]?.stringValue else {
            return .fail(.none)
        }
        if text != stateValue.with({ $0.content }) {
            defaults?.set(text, forKey: kAutoTextContent)
            updateState { current in
                var current = current
                current.content = text
                return current
            }
            NotificationCenter.default.post(name: NSNotification.Name("FenixSettingsChanged"), object: nil)
        }
        return .fail(.none)
    }, removeAfterDisappear: false, hasDone: false)
}
