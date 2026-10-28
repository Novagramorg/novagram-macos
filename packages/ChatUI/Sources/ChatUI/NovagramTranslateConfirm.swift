import Cocoa
import TGUIKit
import TelegramCore
import SwiftSignalKit
import InputView
import AlertsUI
import NovagramCore

// iOS "Ask to translate on send" (`translate_confirm_enabled`): before a text message goes out, ask
// whether to send it translated into the auto-translate language or as written. The answer runs the
// normal send again; while this switch is on, Sender skips its own auto-translate (iOS: the prompt wins).
private var novagramTranslateConfirmResending = false

// True when the prompt took over this send; the caller must return.
func novagramTranslateConfirmIntercepts(chatInteraction: ChatInteraction, resend: @escaping () -> Void) -> Bool {
    guard !novagramTranslateConfirmResending, NovagramSettingsKey.bool("translate_confirm_enabled") else {
        return false
    }
    guard let lang = UserDefaults(suiteName: NovagramSettingsKey.suite)?.string(forKey: "auto_translate_lang"), !lang.isEmpty else {
        return false
    }
    let presentation = chatInteraction.presentation
    guard presentation.state == .normal, presentation.interfaceState.editState == nil, presentation.abilityToSend else {
        return false
    }
    guard chatInteraction.mode.customChatContents == nil, chatInteraction.richTextDraft == nil else {
        return false
    }
    let input = presentation.effectiveInput
    guard !input.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return false
    }

    let context = chatInteraction.context
    let send: (ChatTextInputState?) -> Void = { [weak chatInteraction] translated in
        guard let chatInteraction else {
            return
        }
        if let translated {
            chatInteraction.update({
                $0.withUpdatedEffectiveInputState(translated)
            })
        }
        novagramTranslateConfirmResending = true
        resend()
        novagramTranslateConfirmResending = false
    }

    let l10n = NovagramL10n.current
    verifyAlert_button(for: context.window, header: l10n.translateConfirm_alertTitle, information: input.inputText, ok: l10n.translateConfirm_translate, option: l10n.translateConfirm_original, successHandler: { result in
        switch result {
        case .thrid:
            send(nil)
        case .basic:
            _ = (context.engine.messages.translate(text: input.inputText, toLang: lang)
                |> `catch` { _ -> Signal<(String, [MessageTextEntity])?, NoError> in .single(nil) }
                |> deliverOnMainQueue).start(next: { result in
                if let text = result?.0, !text.isEmpty {
                    send(ChatTextInputState(inputText: text))
                } else {
                    send(nil)
                }
            })
        }
    })
    return true
}
