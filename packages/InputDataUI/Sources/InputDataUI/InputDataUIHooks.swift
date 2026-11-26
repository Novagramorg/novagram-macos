import Cocoa
import TGUIKit

public protocol InputDataTextFormatting: AnyObject {
    func makeBold()
    func makeItalic()
    func makeMonospace()
    func makeUrl()
}

public struct InputDataUIHooks {
    public let checkSendingAbility: (NSEvent) -> Bool
    public let mainWindow: () -> Window
    public let showAlert: (Window, String) -> Void
    public let showModalText: (Window, String) -> Void
    public let detectExternalURL: (String) -> String?
    public let makeLoadingRow: (NSSize, AnyHashable) -> TableRowItem

    public init(checkSendingAbility: @escaping (NSEvent) -> Bool,
                mainWindow: @escaping () -> Window,
                showAlert: @escaping (Window, String) -> Void,
                showModalText: @escaping (Window, String) -> Void,
                detectExternalURL: @escaping (String) -> String?,
                makeLoadingRow: @escaping (NSSize, AnyHashable) -> TableRowItem) {
        self.checkSendingAbility = checkSendingAbility
        self.mainWindow = mainWindow
        self.showAlert = showAlert
        self.showModalText = showModalText
        self.detectExternalURL = detectExternalURL
        self.makeLoadingRow = makeLoadingRow
    }

    private static var installed: InputDataUIHooks?

    public static var shared: InputDataUIHooks {
        guard let hooks = installed else {
            preconditionFailure("Install InputDataUIHooks before using input controllers")
        }
        return hooks
    }

    public static func install(_ hooks: InputDataUIHooks) {
        precondition(Thread.isMainThread)
        installed = hooks
    }
}

enum InputDataTextFormattingAction: CaseIterable {
    case bold
    case italic
    case monospace
    case link

    func apply(to responder: AnyObject?) {
        guard let responder = responder as? InputDataTextFormatting else {
            return
        }
        switch self {
        case .bold: responder.makeBold()
        case .italic: responder.makeItalic()
        case .monospace: responder.makeMonospace()
        case .link: responder.makeUrl()
        }
    }
}
