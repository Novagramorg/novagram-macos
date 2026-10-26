import Cocoa
import TGUIKit
import AlertsUI
import FenixuzCore

// "Ask before sending" (Settings → Novagram → Protection): confirm a sticker or a voice message before it goes out.
func fenixuzConfirmBeforeSend(sticker: Bool = false, voice: Bool = false, window: Window, send: @escaping () -> Void, cancel: @escaping () -> Void = {}) {
    let l10n = FenixuzL10n.current
    let question: String?
    if sticker && FenixuzSettingsKey.bool("ask_before_send_sticker") {
        question = l10n.askSend_sticker
    } else if voice && FenixuzSettingsKey.bool("ask_before_send_voice") {
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
