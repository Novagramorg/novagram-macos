import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import GroupCallScreenUI
import ChatUI
import ChatModeTypes
import TelegramUtils
import TelegramMediaUtils
import TelegramTheme
import EntertainmentUI

extension EmojiesController: @retroactive GroupCallEmojiesController {

}

func installGroupCallScreenUIHooks() {
    GroupCallScreenUIHooks.install(GroupCallScreenUIHooks(forceUpdateStatusBarIconByDockTile: { sharedContext in
        forceUpdateStatusBarIconByDockTile(sharedContext: sharedContext.concrete)
    }, getCrossAccountGroupCall: { sharedContext in
        return sharedContext.concrete.getCrossAccountGroupCall()
    }, updateCurrentGroupCallValue: { sharedContext, value in
        sharedContext.concrete.updateCurrentGroupCallValue(value)
    }, showGroupCall: { sharedContext, context in
        sharedContext.concrete.showGroupCall(with: context)
    }, pushPeerInfo: { navigation, context, peerId in
        PeerInfoController.push(navigation: navigation, context: context.concrete, peerId: peerId)
    }, showReactionsWindow: { context, peerId, react, onClose, presentation, name, parentWindow, view in
        let w = ReactionsWindowController(context.concrete, peerId: peerId, selectedItems: [], react: react, onClose: onClose, presentation: presentation, name: name, moveTop: true, parentWindow: parentWindow)
        w.show(view)
    }, makeVolumeMenuItem: { volume, didUpdateValue in
        return SliderContextMenuItem(volume: volume, didUpdateValue)
    }, generateFakeIconReversed: { foregroundColor, backgroundColor in
        return generateFakeIconReversed(foregroundColor: foregroundColor, backgroundColor: backgroundColor)
    }, generateScamIconReversed: { foregroundColor, backgroundColor in
        return generateScamIconReversed(foregroundColor: foregroundColor, backgroundColor: backgroundColor)
    }, makeEmojies: { context, presentation in
        let emojis = EmojiesController(context as! AccountContext, presentation: presentation)
        return emojis
    }, updateEmojies: { emoji, interactions, chatInteraction in
        (emoji as! EmojiesController).update(with: interactions, chatInteraction: chatInteraction)
    }, formatMessageText: { entities, text, context, fontSize, textColor, linkColor in
        return ChatMessageItem.applyMessageEntities(with: [TextEntitiesMessageAttribute(entities: entities)], for: text, message: nil, context: context, fontSize: fontSize, openInfo: { _, _, _, _ in }, textColor: textColor, linkColor: linkColor, isDark: true, bubbled: false)
    }, reactionsListWidth: { count, maxCount, allowToAll in
        return ContextAddReactionsListView.width(for: count, maxCount: maxCount, allowToAll: allowToAll)
    }, makeReactionsListView: { rect, context, list, add, reveal, presentation, parentWindow in
        return ContextAddReactionsListView(frame: rect, context: context, list: list, add: add, radiusLayer: nil, revealReactions: reveal, presentation: presentation, hasBubble: false, aboveText: nil, parentWindow: parentWindow)
    }, makeRTMPServerUrlItem: { initialSize, stableId, label, copyMenuText, labelColor, textColor, text, context, viewType, isTextSelectable, callback, selectFullWord, canCopy, _copyToClipboard, textFont in
        return TextAndLabelItem(initialSize, stableId: stableId, label: label, copyMenuText: copyMenuText, labelColor: labelColor, textColor: textColor, text: text, context: context as? AccountContext, viewType: viewType, isTextSelectable: isTextSelectable, callback: callback, selectFullWord: selectFullWord, canCopy: canCopy, _copyToClipboard: _copyToClipboard, textFont: textFont)
    }, makeRTMPStreamKeyItem: { initialSize, stableId, label, copyMenuText, labelColor, textColor, text, context, viewType, isTextSelectable, callback, selectFullWord, canCopy, _copyToClipboard, textFont, hideText, toggleHide in
        return TextAndLabelItem(initialSize, stableId: stableId, label: label, copyMenuText: copyMenuText, labelColor: labelColor, textColor: textColor, text: text, context: context as? AccountContext, viewType: viewType, isTextSelectable: isTextSelectable, callback: callback, selectFullWord: selectFullWord, canCopy: canCopy, _copyToClipboard: _copyToClipboard, textFont: textFont, hideText: hideText, toggleHide: toggleHide)
    }, makeSettingsRTMPServerUrlItem: { initialSize, stableId, label, copyMenuText, labelColor, textColor, backgroundColor, text, context, viewType, isTextSelectable, callback, selectFullWord, canCopy, _copyToClipboard, textFont, accentColor, borderColor in
        return TextAndLabelItem(initialSize, stableId: stableId, label: label, copyMenuText: copyMenuText, labelColor: labelColor, textColor: textColor, backgroundColor: backgroundColor, text: text, context: context as? AccountContext, viewType: viewType, isTextSelectable: isTextSelectable, callback: callback, selectFullWord: selectFullWord, canCopy: canCopy, _copyToClipboard: _copyToClipboard, textFont: textFont, accentColor: accentColor, borderColor: borderColor)
    }, makeSettingsRTMPStreamKeyItem: { initialSize, stableId, label, copyMenuText, labelColor, textColor, backgroundColor, text, context, viewType, isTextSelectable, callback, selectFullWord, canCopy, _copyToClipboard, textFont, hideText, toggleHide, accentColor, borderColor in
        return TextAndLabelItem(initialSize, stableId: stableId, label: label, copyMenuText: copyMenuText, labelColor: labelColor, textColor: textColor, backgroundColor: backgroundColor, text: text, context: context as? AccountContext, viewType: viewType, isTextSelectable: isTextSelectable, callback: callback, selectFullWord: selectFullWord, canCopy: canCopy, _copyToClipboard: _copyToClipboard, textFont: textFont, hideText: hideText, toggleHide: toggleHide, accentColor: accentColor, borderColor: borderColor)
    }, groupCallContext: { sharedContext in
        return sharedContext.concrete.groupCallContext
    }, cachedGroupCallContexts: { context in
        return context.concrete.cachedGroupCallContexts
    }))
}
