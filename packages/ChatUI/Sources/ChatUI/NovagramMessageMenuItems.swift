import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import InputView
import LocalAnimations
import ChatHistoryModel
import NovagramCore

// Message context menu items added by Novagram: forward without the sender name, edit before forwarding,
// and the edit history screen (old fork: ChatMessageMenuItems.swift).
func novagramForwardMenuItems(message: Message, chatInteraction: ChatInteraction) -> [ContextMenuItem] {
    let l10n = NovagramL10n.current
    var items: [ContextMenuItem] = []
    if NovagramSettingsKey.bool("forward_hide_names") {
        items.append(ContextMenuItem(l10n.forward_withoutQuotes, handler: { [weak chatInteraction] in
            chatInteraction?.update(animated: true, {
                $0.updatedInterfaceState {
                    $0.withUpdatedForwardMessageIds([message.id])
                        .withUpdatedForwardMessages([message])
                        .withUpdatedHideSendersName(true, saveTempValue: true)
                }
            })
            chatInteraction?.focusInputField()
        }, itemImage: MenuAnimation.menu_forward.value))
    }

    if !message.text.isEmpty {
        items.append(ContextMenuItem(l10n.forward_editAndForward, handler: { [weak chatInteraction] in
            guard let chatInteraction else {
                return
            }
            var attributes: [ChatTextInputAttribute] = []
            if let entities = message.attributes.compactMap({ $0 as? TextEntitiesMessageAttribute }).first {
                attributes = chatTextAttributes(from: entities, associatedMedia: message.associatedMedia)
            }
            let length = message.text.utf16.count
            let inputState = ChatTextInputState(inputText: message.text, selectionRange: length ..< length, attributes: attributes)
            chatInteraction.update(animated: true, {
                $0.updatedInterfaceState {
                    $0.withUpdatedInputState(inputState)
                }
            })
            chatInteraction.focusInputField()
        }, itemImage: MenuAnimation.menu_edit.value))
    }
    return items
}

// The history is recorded either way; the switch only hides the menu item (iOS default: on).
func novagramEditedHistoryMenuItem(message: Message, chatInteraction: ChatInteraction) -> ContextMenuItem? {
    guard NovagramSettingsKey.bool("edited_history_enabled", default: true) else {
        return nil
    }
    return ContextMenuItem(NovagramL10n.current.editedHistory_screenTitle, handler: { [weak chatInteraction] in
        guard let chatInteraction else {
            return
        }
        NovagramHooks.shared.presentEditedHistory(chatInteraction.context, message.id.peerId, message.id.id, message.text)
    }, itemImage: MenuAnimation.menu_edited.value)
}
