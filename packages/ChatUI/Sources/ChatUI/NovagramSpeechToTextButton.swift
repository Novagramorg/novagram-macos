import Cocoa
import TGUIKit
import TelegramTheme
import InputView
import AlertsUI
import SwiftSignalKit
import TelegramCore
import NovagramCore

// Speech-to-text button inside the message field, left of the emoji/actions buttons
// (Settings → Novagram → Voice → Speech to text). Dictated text replaces the input.
// Any manual change of the input (typing, sending) stops the dictation, so a late result never
// overwrites what the user did.
final class NovagramSpeechToTextButton {
    static let width: CGFloat = 30

    static var isEnabled: Bool {
        return NovagramSettingsKey.bool("stt_enabled", default: false)
    }

    // Space the text view leaves free for the button.
    static var reservedWidth: CGFloat {
        return isEnabled ? width : 0
    }

    private weak var chatInteraction: ChatInteraction?
    private var button: ImageButton?
    private var manager: NovagramSpeechToTextManager?
    private var lastDictatedText: String?
    // Text dictated before the user clicked the button to stop; translated once the recognizer stops.
    private var translateOnStop: String?

    init(chatInteraction: ChatInteraction) {
        self.chatInteraction = chatInteraction
    }

    deinit {
        manager?.stopRecording()
    }

    // `rightEdge` is the x where the actions buttons start; `bottomY` the bottom of the text row.
    func layout(in container: NSView, rightEdge: CGFloat, bottomY: CGFloat, hidden: Bool, transition: ContainedViewLayoutTransition) {
        guard NovagramSpeechToTextButton.isEnabled, !hidden else {
            if manager?.isRecording == true {
                stop()
            }
            button?.removeFromSuperview()
            button = nil
            return
        }
        let current: ImageButton
        if let button {
            current = button
        } else {
            current = ImageButton()
            current.autohighlight = false
            current.scaleOnClick = true
            current.set(handler: { [weak self] _ in
                self?.toggle()
            }, for: .Click)
            container.addSubview(current)
            button = current
            updateAppearance()
        }
        let size = NSMakeSize(NovagramSpeechToTextButton.width, 34)
        let frame = NSMakeRect(rightEdge - size.width, bottomY - size.height, size.width, size.height)
        if current.frame == .zero {
            current.frame = frame
        } else {
            transition.updateFrame(view: current, frame: frame)
        }
    }

    func updateAppearance() {
        guard let button else {
            return
        }
        let isRecording = manager?.isRecording == true
        let color = isRecording ? theme.colors.redUI : theme.colors.grayIcon
        let symbol = NSImage(systemSymbolName: "waveform.and.mic", accessibilityDescription: nil) ?? NSImage(systemSymbolName: "mic", accessibilityDescription: nil)
        let image = symbol?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)) ?? symbol
        if let icon = image?.precomposed(color) {
            button.set(image: icon, for: .Normal)
            button.set(image: icon, for: .Hover)
            button.set(image: icon, for: .Highlight)
        }
        let l10n = NovagramL10n.current
        button.toolTip = isRecording ? l10n.stt_recordingTip : l10n.stt_buttonTip
    }

    private func toggle() {
        if manager == nil {
            let manager = NovagramSpeechToTextManager()
            manager.onTextUpdate = { [weak self] text in
                DispatchQueue.main.async {
                    self?.apply(text)
                }
            }
            manager.onStop = { [weak self] in
                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }
                    let dictated = self.translateOnStop ?? self.lastDictatedText
                    self.translateOnStop = nil
                    self.lastDictatedText = nil
                    self.updateAppearance()
                    if let dictated {
                        self.translateDictated(dictated)
                    }
                }
            }
            manager.onError = { [weak self] text in
                DispatchQueue.main.async {
                    if let window = self?.chatInteraction?.context.window {
                        alert(for: window, info: text)
                    }
                    self?.updateAppearance()
                }
            }
            self.manager = manager
        } else if let manager, !manager.isRecording {
            manager.updateLocale(UserDefaults(suiteName: "pro_messager")?.string(forKey: "stt_language") ?? "en-US")
        }
        translateOnStop = manager?.isRecording == true ? lastDictatedText : nil
        lastDictatedText = nil
        manager?.toggleRecording()
        updateAppearance()
    }

    private func stop() {
        translateOnStop = nil
        manager?.stopRecording()
        lastDictatedText = nil
        updateAppearance()
    }

    // iOS "Translate voice messages" (`voice_translate_enabled`): the finished dictation is translated
    // into the auto-translate language, unless the user changed the text meanwhile.
    private func translateDictated(_ text: String) {
        guard let chatInteraction, !text.isEmpty, NovagramSettingsKey.bool("voice_translate_enabled"), !NovagramSettingsKey.bool("translate_confirm_enabled") else {
            return
        }
        guard chatInteraction.presentation.effectiveInput.inputText == text else {
            return
        }
        let saved = UserDefaults(suiteName: NovagramSettingsKey.suite)?.string(forKey: "auto_translate_lang") ?? ""
        let lang = saved.isEmpty ? "en" : saved
        _ = (chatInteraction.context.engine.messages.translate(text: text, toLang: lang)
            |> `catch` { _ -> Signal<(String, [MessageTextEntity])?, NoError> in .single(nil) }
            |> deliverOnMainQueue).start(next: { [weak chatInteraction] result in
            guard let chatInteraction, let translated = result?.0, !translated.isEmpty, chatInteraction.presentation.effectiveInput.inputText == text else {
                return
            }
            chatInteraction.update({
                $0.withUpdatedEffectiveInputState(ChatTextInputState(inputText: translated))
            })
        })
    }

    private func apply(_ text: String) {
        guard let chatInteraction, manager?.isRecording == true else {
            return
        }
        let current = chatInteraction.presentation.effectiveInput.inputText
        if let lastDictatedText, current != lastDictatedText {
            stop()
            return
        }
        lastDictatedText = text
        chatInteraction.update({
            $0.withUpdatedEffectiveInputState(ChatTextInputState(inputText: text))
        })
    }
}
