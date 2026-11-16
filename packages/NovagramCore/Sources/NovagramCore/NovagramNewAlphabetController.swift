import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramTheme
import Localization
import GeneralRows
import InputDataUI
import NovagramUzScriptCore

// "Yangi alifbo" page (Novagram Settings → Messages) and its "Convert text" tool. Texts and rules come from NovagramUzScriptKit.
public enum NovagramNewAlphabet {
    public static var rowTitle: String {
        return texts().title
    }

    public static var newBadge: CGImage {
        return generateTextIcon_NewBadge(bgColor: theme.colors.accent, textColor: theme.colors.underSelectedColor)
    }

    static func texts() -> UzScriptStrings {
        return UzScriptStrings(languageCode: appCurrentLanguage.languageCode)
    }
}

// MARK: - Hero row: the four new letters with the old spelling under each.

private let heroLetters: [(String, String)] = [("Ş", "sh"), ("Ç", "ch"), ("Ö", "oʻ"), ("Ğ", "gʻ")]

private final class NewAlphabetHeroRowItem: GeneralRowItem {
    init(_ initialSize: NSSize, stableId: AnyHashable, viewType: GeneralViewType) {
        super.init(initialSize, height: 96, stableId: stableId, viewType: viewType)
    }

    override func viewClass() -> AnyClass {
        return NewAlphabetHeroRowView.self
    }
}

private final class NewAlphabetHeroTile: View {
    private let letterView = TextView()
    private let oldView = TextView()
    private let box = View()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        box.layer?.cornerRadius = 12
        addSubview(box)
        box.addSubview(letterView)
        addSubview(oldView)
        letterView.userInteractionEnabled = false
        letterView.isSelectable = false
        oldView.userInteractionEnabled = false
        oldView.isSelectable = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(letter: String, old: String) {
        box.backgroundColor = theme.colors.accent.withAlphaComponent(0.12)
        let letterLayout = TextViewLayout(.initialize(string: letter, color: theme.colors.accent, font: .bold(28)), maximumNumberOfLines: 1)
        letterLayout.measure(width: .greatestFiniteMagnitude)
        letterView.update(letterLayout)
        let oldLayout = TextViewLayout(.initialize(string: old, color: theme.colors.grayText, font: .normal(12)), maximumNumberOfLines: 1)
        oldLayout.measure(width: .greatestFiniteMagnitude)
        oldView.update(oldLayout)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        box.frame = NSRect(x: 0, y: 0, width: frame.width, height: frame.width)
        letterView.center()
        oldView.setFrameOrigin(NSPoint(x: floor((frame.width - oldView.frame.width) / 2), y: box.frame.maxY + 3))
    }
}

private final class NewAlphabetHeroRowView: GeneralContainableRowView {
    private let tileSize: CGFloat = 56
    private let tileSpacing: CGFloat = 12
    private var tiles: [NewAlphabetHeroTile] = []

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for _ in heroLetters {
            let tile = NewAlphabetHeroTile(frame: NSRect(x: 0, y: 0, width: tileSize, height: tileSize + 20))
            tiles.append(tile)
            addSubview(tile)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        for (tile, letter) in zip(tiles, heroLetters) {
            tile.update(letter: letter.0, old: letter.1)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let count = CGFloat(tiles.count)
        let totalWidth = count * tileSize + (count - 1) * tileSpacing
        var x = floor((containerView.frame.width - totalWidth) / 2)
        let y = floor((containerView.frame.height - tileSize - 20) / 2)
        for tile in tiles {
            tile.frame = NSRect(x: x, y: y, width: tileSize, height: tileSize + 20)
            x += tileSize + tileSpacing
        }
    }
}

// MARK: - Settings page

private final class PageArguments {
    let toggleSend: (Bool) -> Void
    let toggleShow: (Bool) -> Void
    let toggleChatMenu: (Bool) -> Void
    let openConverter: () -> Void

    init(toggleSend: @escaping (Bool) -> Void, toggleShow: @escaping (Bool) -> Void, toggleChatMenu: @escaping (Bool) -> Void, openConverter: @escaping () -> Void) {
        self.toggleSend = toggleSend
        self.toggleShow = toggleShow
        self.toggleChatMenu = toggleChatMenu
        self.openConverter = openConverter
    }
}

private struct PageState: Equatable {
    var send: Bool
    var show: Bool
    var chatMenu: Bool

    static func stored() -> PageState {
        let settings = UzScriptSettings()
        return PageState(send: settings.sendInNewAlphabet, show: settings.showChatsInNewAlphabet, chatMenu: settings.cyrillicLatinEnabled)
    }
}

private let _id_hero = InputDataIdentifier("_id_new_alphabet_hero")
private let _id_send = InputDataIdentifier("_id_new_alphabet_send")
private let _id_show = InputDataIdentifier("_id_new_alphabet_show")
private let _id_chat_menu = InputDataIdentifier("_id_new_alphabet_chat_menu")
private let _id_convert = InputDataIdentifier("_id_new_alphabet_convert")

private func pageEntries(_ state: PageState, texts: UzScriptStrings, arguments: PageArguments) -> [InputDataEntry] {
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
    func row(_ identifier: InputDataIdentifier, _ name: String, _ description: String?, _ type: GeneralInteractedType, _ viewType: GeneralViewType, _ action: @escaping () -> Void) {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: identifier, data: .init(name: name, color: theme.colors.text, type: type, viewType: viewType, description: description, action: action)))
        index += 1
    }

    section()
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_hero, equatable: nil, comparable: nil, item: { initialSize, stableId in
        return NewAlphabetHeroRowItem(initialSize, stableId: stableId, viewType: .singleItem)
    }))
    index += 1
    text(texts.heroText, .textBottomItem)

    section()
    row(_id_send, texts.sendSwitchTitle, texts.sendSwitchSubtitle, .switchable(state.send), .firstItem, { arguments.toggleSend(!state.send) })
    row(_id_show, texts.showSwitchTitle, texts.showSwitchSubtitle, .switchable(state.show), .innerItem, { arguments.toggleShow(!state.show) })
    row(_id_chat_menu, texts.chatMenuSwitchTitle, texts.chatMenuSwitchSubtitle, .switchable(state.chatMenu), .lastItem, { arguments.toggleChatMenu(!state.chatMenu) })
    text(texts.captionsNote, .textBottomItem)

    section()
    row(_id_convert, texts.convertTextRow, nil, .next, .singleItem, arguments.openConverter)
    text(texts.footer, .textBottomItem)

    section()
    return entries
}

public func NovagramNewAlphabetController() -> InputDataController {
    let statePromise = ValuePromise(PageState.stored(), ignoreRepeated: true)
    let reload: () -> Void = {
        statePromise.set(PageState.stored())
        NotificationCenter.default.post(name: NSNotification.Name("NovagramSettingsChanged"), object: nil)
    }

    var getController: (() -> InputDataController?)?

    let arguments = PageArguments(toggleSend: { value in
        UzScriptSettings().sendInNewAlphabet = value
        reload()
    }, toggleShow: { value in
        UzScriptSettings().showChatsInNewAlphabet = value
        reload()
    }, toggleChatMenu: { value in
        UzScriptSettings().cyrillicLatinEnabled = value
        reload()
    }, openConverter: {
        getController?()?.navigationController?.push(NovagramConvertTextController())
    })

    let signal = combineLatest(queue: prepareQueue, statePromise.get(), appearanceSignal)
        |> map { state, _ in
            return InputDataSignalValue(entries: pageEntries(state, texts: NovagramNewAlphabet.texts(), arguments: arguments))
        }

    let controller = InputDataController(dataSignal: signal, title: NovagramNewAlphabet.texts().title, removeAfterDisappear: false, hasDone: false)
    getController = { [weak controller] in
        return controller
    }
    controller.didAppear = { _ in
        statePromise.set(PageState.stored())
    }
    return controller
}

// MARK: - Convert text tool

private struct ConvertState: Equatable {
    var input: String
    var target: UzScript
}

private let _id_convert_input = InputDataIdentifier("_id_new_alphabet_convert_input")
private let _id_convert_copy = InputDataIdentifier("_id_new_alphabet_convert_copy")
private let convertTargets: [UzScript] = [.latin2027, .latin1995, .cyrillic]
private let convertInputLimit: Int32 = 4096

private func _id_convert_target(_ script: UzScript) -> InputDataIdentifier {
    return InputDataIdentifier("_id_new_alphabet_convert_target_\(script.rawValue)")
}

private func convertedText(_ state: ConvertState) -> String {
    guard !state.input.isEmpty else {
        return ""
    }
    return UzScriptConverter.convert(state.input, to: state.target).text
}

private func convertEntries(_ state: ConvertState, texts: UzScriptStrings, setTarget: @escaping (UzScript) -> Void, copy: @escaping () -> Void) -> [InputDataEntry] {
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

    section()
    entries.append(.input(sectionId: sectionId, index: index, value: .string(state.input), error: nil, identifier: _id_convert_input, mode: .plain, data: InputDataRowData(viewType: .singleItem), placeholder: nil, inputPlaceholder: texts.inputPlaceholder, filter: { $0 }, limit: convertInputLimit))
    index += 1
    if !state.input.isEmpty {
        let detected = UzScriptConverter.detect(state.input)
        text("\(texts.detectedLabel): \(texts.scriptName(detected))", .textBottomItem)
    }

    section()
    text(texts.targetLabel, .textTopItem)
    for script in convertTargets {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_convert_target(script), data: .init(name: texts.scriptName(script), color: theme.colors.text, type: .selectable(state.target == script), viewType: bestGeneralViewType(convertTargets, for: script), action: { setTarget(script) })))
        index += 1
    }

    let result = convertedText(state)
    if !result.isEmpty {
        section()
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(result), data: .init(color: theme.colors.text, viewType: .singleItem)))
        index += 1
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_convert_copy, data: .init(name: texts.copy, color: theme.colors.accent, type: .none, viewType: .singleItem, action: copy)))
        index += 1
    }

    section()
    return entries
}

private func NovagramConvertTextController() -> InputDataController {
    let initialState = ConvertState(input: "", target: .latin2027)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((ConvertState) -> ConvertState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var getController: (() -> InputDataController?)?

    let setTarget: (UzScript) -> Void = { script in
        updateState { current in
            var current = current
            current.target = script
            return current
        }
    }
    let copy: () -> Void = {
        let result = convertedText(stateValue.with { $0 })
        guard !result.isEmpty else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
        if let window = getController?()?.window {
            showModalText(for: window, text: NovagramNewAlphabet.texts().copied)
        }
    }

    let signal = combineLatest(queue: prepareQueue, statePromise.get(), appearanceSignal)
        |> map { state, _ in
            return InputDataSignalValue(entries: convertEntries(state, texts: NovagramNewAlphabet.texts(), setTarget: setTarget, copy: copy))
        }

    let controller = InputDataController(dataSignal: signal, title: NovagramNewAlphabet.texts().convertTextRow, updateDatas: { data in
        let input = data[_id_convert_input]?.stringValue ?? ""
        updateState { current in
            var current = current
            current.input = input
            return current
        }
        return .none
    }, removeAfterDisappear: false, hasDone: false)
    getController = { [weak controller] in
        return controller
    }
    return controller
}
