import Cocoa
import TGUIKit
import TelegramTheme
import FenixuzCore
import TelegramCore
import Postbox
import SwiftSignalKit
import ApiCredentials
import AlertsUI
import Localization

// "Log in with a bot token" link under the QR and phone login buttons (FenixuzLoginFeatures.botToken).
func fenixuzStyleBotTokenLink(_ button: TextButton) {
    button.scaleOnClick = true
    button.set(font: Auth_Insets.infoFontBold, for: .Normal)
    button.set(color: theme.colors.accent, for: .Normal)
    button.set(text: FenixuzL10n.current.botlogin_entry_button, for: .Normal)
    _ = button.sizeToFit()
}

// Height the link adds to a login screen's content stack.
func fenixuzBotTokenLinkHeight(_ button: TextButton) -> CGFloat {
    return FenixuzLoginFeatures.botToken ? 10 + button.frame.height : 0
}

// Runs auth.importBotAuthorization (TelegramCore fork patch, fork-patches/telegramcore) and reports back to AuthController.
func fenixuzLoginWithBotToken(_ token: String, account: UnauthorizedAccount, accountManager: AccountManager<TelegramAccountManagerTypes>, window: Window?, disposable: MetaDisposable, setLocked: @escaping (Bool) -> Void, setError: @escaping (ImportBotAuthorizationError) -> Void, completed: @escaping () -> Void, retry: @escaping () -> Void) {
    guard let window else {
        return
    }
    setLocked(true)
    let signal = importBotAuthorization(accountManager: accountManager, account: account, apiId: ApiEnvironment.apiId, apiHash: ApiEnvironment.apiHash, botToken: token)
        |> map(Optional.init)
        |> mapError(Optional.init)
        |> timeout(20, queue: Queue.mainQueue(), alternate: .fail(nil))
        |> deliverOnMainQueue

    disposable.set(signal.start(error: { error in
        if let error {
            setError(error)
        } else {
            setLocked(false)
            verifyAlert_button(for: window, header: strings().loginConnectionErrorHeader, information: strings().loginConnectionErrorInfo, ok: strings().loginConnectionErrorTryAgain, option: strings().loginConnectionErrorUseProxy, successHandler: { result in
                switch result {
                case .basic:
                    retry()
                case .thrid:
                    break
                }
            })
        }
    }, completed: {
        completed()
    }))
}
