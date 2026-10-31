import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramTheme
import Localization
import GeneralRows
import InputDataUI
import NovagramCallRecordingCore

public enum NovagramCallRecordingSettingsRow {
    case auto
    case folder
}

extension NovagramCallRecordingSettings {
    public static func pageRowTexts(isOn: Bool) -> (title: String, value: String) {
        let strings = CallRecordingSettingsStrings(languageCode: appCurrentLanguage.languageCode)
        return (strings.title, isOn ? strings.on : strings.off)
    }
}

private final class Arguments {
    let toggleRecord: (Bool) -> Void
    let toggleAuto: (Bool) -> Void
    let changeFolder: () -> Void
    let openRecordings: () -> Void

    init(toggleRecord: @escaping (Bool) -> Void, toggleAuto: @escaping (Bool) -> Void, changeFolder: @escaping () -> Void, openRecordings: @escaping () -> Void) {
        self.toggleRecord = toggleRecord
        self.toggleAuto = toggleAuto
        self.changeFolder = changeFolder
        self.openRecordings = openRecordings
    }
}

private struct State: Equatable {
    var isEnabled: Bool
    var isAutoEnabled: Bool
    var folder: String?
    var recordingCount: Int

    static func stored(recordingCount: Int) -> State {
        return State(isEnabled: NovagramCallRecordingSettings.isStoredEnabled, isAutoEnabled: NovagramCallRecordingSettings.isAutoStored, folder: NovagramCallRecordingSettings.folderDisplayPath, recordingCount: recordingCount)
    }
}

private let _id_record = InputDataIdentifier("_id_call_recording_record")
private let _id_auto = InputDataIdentifier("_id_call_recording_auto")
private let _id_folder = InputDataIdentifier("_id_call_recording_folder")
private let _id_recordings = InputDataIdentifier("_id_call_recording_recordings")

private func entries(_ state: State, strings: CallRecordingSettingsStrings, l10n: NovagramL10n, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    func section() {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    }
    func text(_ text: String, _ viewType: GeneralViewType) {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(text), data: .init(color: theme.colors.listGrayText, viewType: viewType)))
        index += 1
    }
    func row(_ identifier: InputDataIdentifier, _ name: String, _ type: GeneralInteractedType, _ action: @escaping () -> Void) {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: identifier, data: .init(name: name, color: theme.colors.text, type: type, viewType: .singleItem, action: action)))
        index += 1
    }

    section()
    text(strings.recordingHeader, .textTopItem)
    row(_id_record, strings.recordTitle, .switchable(state.isEnabled), { arguments.toggleRecord(!state.isEnabled) })
    text(strings.recordFooter, .textBottomItem)

    if state.isEnabled {
        section()
        row(_id_auto, strings.autoTitle, .switchable(state.isAutoEnabled), { arguments.toggleAuto(!state.isAutoEnabled) })
        text(strings.autoFooter, .textBottomItem)

        section()
        row(_id_folder, l10n.callRecording_saveTo, .nextContext(state.folder ?? l10n.callRecording_askEveryTime), arguments.changeFolder)
        text(l10n.callRecording_saveToFooter, .textBottomItem)
    }

    section()
    text(strings.recordingsHeader, .textTopItem)
    row(_id_recordings, strings.recordingsTitle, .nextContext(state.recordingCount > 0 ? "\(state.recordingCount)" : ""), arguments.openRecordings)
    text(strings.recordingsFooter, .textBottomItem)

    section()
    text(strings.privacyHeader, .textTopItem)
    text(strings.privacyText, .textBottomItem)

    section()
    return entries
}

public func NovagramCallRecordingSettingsController(focus: NovagramCallRecordingSettingsRow? = nil) -> InputDataController {
    let actionsDisposable = DisposableSet()
    let countDisposable = MetaDisposable()
    actionsDisposable.add(countDisposable)

    let initialState = State.stored(recordingCount: 0)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }
    let reloadSettings: () -> Void = {
        updateState { current in
            return State.stored(recordingCount: current.recordingCount)
        }
    }
    let reloadCount: () -> Void = {
        countDisposable.set((NovagramCallRecordingSettings.recordingCountSignal |> deliverOnMainQueue).start(next: { count in
            updateState { current in
                var current = current
                current.recordingCount = count
                return current
            }
        }))
    }
    let settingsChanged: () -> Void = {
        reloadSettings()
        NotificationCenter.default.post(name: NSNotification.Name("NovagramSettingsChanged"), object: nil)
    }

    var getController: (() -> InputDataController?)?

    let arguments = Arguments(toggleRecord: { value in
        NovagramCallRecordingSettings.setEnabled(value)
        settingsChanged()
        if value {
            NovagramCallRecordingSettings.chooseFolder(window: getController?()?.window, completion: { _ in
                reloadSettings()
                reloadCount()
            })
        }
    }, toggleAuto: { value in
        NovagramCallRecordingSettings.setAutoEnabled(value)
        settingsChanged()
    }, changeFolder: {
        guard let window = getController?()?.window else {
            return
        }
        NovagramCallRecordingSettings.changeFolder(window: window, completion: {
            reloadSettings()
            reloadCount()
        })
    }, openRecordings: {
        guard let recordings = makeNovagramCallRecordingsController() else {
            return
        }
        getController?()?.navigationController?.push(recordings)
    })

    let observer = NotificationCenter.default.addObserver(forName: CallRecordingSettings.changedNotification, object: nil, queue: .main) { _ in
        reloadSettings()
        reloadCount()
    }
    actionsDisposable.add(ActionDisposable {
        NotificationCenter.default.removeObserver(observer)
    })

    let signal = combineLatest(queue: prepareQueue, statePromise.get(), appearanceSignal)
        |> map { state, _ in
            let strings = CallRecordingSettingsStrings(languageCode: appCurrentLanguage.languageCode)
            let l10n = NovagramL10n(languageCode: appCurrentLanguage.languageCode)
            return InputDataSignalValue(entries: entries(state, strings: strings, l10n: l10n, arguments: arguments))
        }

    let title = CallRecordingSettingsStrings(languageCode: appCurrentLanguage.languageCode).title
    let controller = InputDataController(dataSignal: signal, title: title, removeAfterDisappear: false, hasDone: false)
    getController = { [weak controller] in
        return controller
    }
    controller.didAppear = { _ in
        reloadSettings()
        reloadCount()
    }
    if let focus {
        let identifier = focus == .auto ? _id_auto : _id_folder
        var didFocus = false
        controller.afterTransaction = { controller in
            guard !didFocus else {
                return
            }
            didFocus = true
            let stableId = InputDataEntryId.general(identifier)
            guard controller.tableView.item(stableId: AnyHashable(stableId)) != nil else {
                return
            }
            controller.tableView.scroll(to: .center(id: AnyHashable(stableId), innerId: nil, animated: true, focus: .init(focus: true), inset: 0), inset: NSEdgeInsets())
        }
    }
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    return controller
}
