private struct InputDataIdentifier: Hashable {
    let value: String
    init(_ value: String) { self.value = value }
}

private enum InputDataValue: Equatable {
    case string(String)
    var stringValue: String? {
        switch self { case let .string(value): return value }
    }
}

private struct InputDataValueError: Equatable {
    enum Target { case data }
    let description: String
    let target: Target
}

private enum InputDataValidation {
    enum FieldAction { case shake }
    enum Failure {
        case none
        case fields([InputDataIdentifier: FieldAction])
        case doSomething(next: (@escaping (InputDataValidation) -> Void) -> Void)
    }
    case none
    case fail(Failure)
}

private final class Window {
    var progress: Disposable?
    var messages: [String] = []
}

private protocol AccountContextProtocol {
    var account: Account { get }
    var window: Window { get }
}

private final class Context: AccountContextProtocol {
    let account = Account()
    let window = Window()
}

private func bestWindow(_ context: any AccountContextProtocol, _ controller: InputDataController?) -> Window { context.window }
private func showModalText(for window: Window, text: String) { window.messages.append(text) }

private func showModalProgress<T, E>(signal: Signal<T, E>, for window: Window) -> Signal<T, E> {
    Signal { subscriber in
        let disposable = (signal |> deliverOnMainQueue).start(next: subscriber.putNext, error: subscriber.putError, completed: subscriber.putCompletion)
        window.progress = disposable
        return disposable
    }
}

private func isValidEmail(_ value: String) -> Bool { value.contains("@") }
private func deliverOnPrepareQueue<T, E>(_ signal: Signal<T, E>) -> Signal<T, E> { signal }

@dynamicMemberLookup
private struct TestStrings {
    subscript(dynamicMember name: String) -> String { name }
    func passkeysMaxLimitReached(_ count: Int) -> String { "limit-\(count)" }
}
private func strings() -> TestStrings { TestStrings() }

@dynamicMemberLookup
private struct TestTheme {
    subscript(dynamicMember name: String) -> TestTheme { self }
}
private let theme = TestTheme()

private enum AnalyticsScreen { case settingsPrivacyLoginEmail, settingsPrivacyLoginEmailCode, settingsPrivacyPasskeys }
private final class Analytics {
    static let shared = Analytics()
    var screens: Analytics { self }
    func show(_ id: ObjectIdentifier, screen: AnalyticsScreen) {}
}

private struct ModalHeaderData {
    init(title: String) {}
    init(image: TestTheme, handler: @escaping () -> Void) {}
}

private final class Button {
    enum State { case Normal }
    var isEnabled = true
    func set(text: String, for state: State) {}
    func set(background: TestTheme, for state: State) {}
}

private final class ModalInteractions {
    let button = Button()
    init(acceptTitle: String, accept: @escaping () -> Void, singleButton: Bool) {}
    func updateDone(_ update: (Button) -> Void) { update(button) }
}

private struct TestEntries {
    let state: State
    let arguments: Arguments
}
private func entries(_ state: State, arguments: Arguments) -> TestEntries { TestEntries(state: state, arguments: arguments) }
private struct InputDataSignalValue { let entries: TestEntries }

private final class InputDataController {
    var validateData: ([InputDataIdentifier: InputDataValue]) -> InputDataValidation = { _ in .none }
    var updateDatas: ([InputDataIdentifier: InputDataValue]) -> InputDataValidation = { _ in .none }
    var onDeinit: () -> Void = {}
    var contextObject: AnyObject?
    var afterTransaction: (InputDataController) -> Void = { _ in }
    var analyticsScreen = AnalyticsScreen.settingsPrivacyLoginEmail
    var leftModalHeader: ModalHeaderData?
    var centerModalHeader: ModalHeaderData?
    private(set) var snapshot: TestEntries!
    private let observer = MetaDisposable()
    init(dataSignal: Signal<InputDataSignalValue, NoError>, title: String) {
        observer.set(dataSignal.start(next: { [weak self] value in
            guard let self else { return }
            self.snapshot = value.entries
            self.afterTransaction(self)
        }))
    }
    func proccessValidation(_ validation: InputDataValidation) {
        if case let .fail(.doSomething(next)) = validation {
            next { [weak self] in self?.proccessValidation($0) }
        }
    }
    func returnKeyAction() { proccessValidation(validateData([:])) }
    deinit { observer.dispose(); onDeinit() }
}

private final class InputDataModalController {
    let controller: InputDataController
    let interactions: ModalInteractions?
    var modal: InputDataModalController? { self }
    private let closeHandler: (@escaping () -> Void) -> Void
    private(set) var closed = false
    init(_ controller: InputDataController, modalInteractions: ModalInteractions? = nil, closeHandler: @escaping (@escaping () -> Void) -> Void = { $0() }) {
        self.controller = controller
        self.interactions = modalInteractions
        self.closeHandler = closeHandler
    }
    func close() { closeHandler { self.closed = true } }
    func updateLocalizationAndTheme(theme: TestTheme) {}
}

private func alert(for window: Window, info: String) { window.messages.append(info) }
private func verifyAlert(for window: Window, header: String, information: String, ok: String, cancel: String, successHandler: (Bool) -> Void) { successHandler(true) }
