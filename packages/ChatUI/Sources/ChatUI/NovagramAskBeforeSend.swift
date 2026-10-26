import Cocoa
import TGUIKit
import AlertsUI
import NovagramCore

// "Ask before sending" (Settings → Novagram → Protection): confirm a sticker or a voice message before it goes out.
func novagramConfirmBeforeSend(sticker: Bool = false, voice: Bool = false, window: Window, send: @escaping () -> Void, cancel: @escaping () -> Void = {}) {
    let l10n = NovagramL10n.current
    let question: String?
    if sticker && NovagramSettingsKey.bool("ask_before_send_sticker") {
        question = l10n.askSend_sticker
    } else if voice && NovagramSettingsKey.bool("ask_before_send_voice") {
        question = l10n.askSend_voice
    } else {
        question = nil
    }
    guard let question else {
        send()
        return
    }
    verifyAlert(for: window, information: question, ok: l10n.askSend_send, cancel: l10n.askSend_cancel, successHandler: { _ in
        send()
    }, cancelHandler: cancel)
}
