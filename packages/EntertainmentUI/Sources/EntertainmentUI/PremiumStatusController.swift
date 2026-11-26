import Foundation
import Cocoa
import TGUIKit
import TelegramCore
import SwiftSignalKit
import Postbox
import TelegramContext
import TelegramUtils

private func animateStatusAppearance(_ items: [TableRowItem]) {
    let sections = items.compactMap {
        $0 as? EmojiesSectionRowItem
    }
    let tabs = items.compactMap {
        $0 as? StickerPackRowItem
    }
    let firstTab = items.compactMap {
        $0 as? ETabRowItem
    }
    
    let duration: Double = 0.35
    let itemDelay: Double = duration / Double(sections.count)
    var delay: Double = itemDelay
    
    firstTab.first?.animateAppearance(delay: 0, duration: duration, ignoreCount: 0)
    
    for tab in tabs {
        tab.animateAppearance(delay: 0, duration: duration, ignoreCount: 0)
    }
    
    for section in sections {
        section.animateAppearance(delay: delay, duration: duration, initialPlayers: [:])
        delay += itemDelay
    }
}

public final class PremiumStatusController<Context: AccountContextProtocol> : TelegramViewController<Context> {

    public override var defaultBarTitle: String {
        return localizedString("Telegram.PremiumStatusController")
    }
    
    private let emojis: EmojiesController<Context>
    
    public let callback: (TelegramMediaFile, StarGift.UniqueGift?, Int32?, CGRect?)->Void
    public init(_ context: Context, callback: @escaping(TelegramMediaFile, StarGift.UniqueGift?, Int32?, CGRect?)->Void, peer: TelegramUser) {
        
        
        var selected: [EmojiesSectionRowItem.SelectedItem] = []
        if let fileId = peer.emojiStatus?.fileId {
            selected.append(.init(source: .custom(fileId), type: .normal))
        } else {
            selected.append(.init(source: .custom(0), type: .normal))
        }
        self.emojis = .init(context, mode: .status, selectedItems: selected)
        self.callback = callback
        super.init(context)
        bar = .init(height: 0)
        _frameRect = NSMakeRect(0, 0, 350, 300)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        emojis._frameRect = self.bounds
        self.view.addSubview(emojis.view)
        self.ready.set(self.emojis.ready.get())
        
        let chatInteraction = EntertainmentUIHooks.shared.makeChatInteraction(context, context.peerId)
        
        let interactions = EntertainmentInteractions(.emoji, peerId: context.peerId)
        
        interactions.sendAnimatedEmoji = { [weak self] item, starGift, _, timeout, rect in
            self?.callback(item.file._parse(), starGift, timeout, rect)
            self?.closePopover()
        }
        
        emojis.update(with: interactions, chatInteraction: chatInteraction)
        
        emojis.animateAppearance = { [weak self] items in
            self?.animateAppearanceItems(items)
        }
    }
    
    private func animateAppearanceItems(_ items: [TableRowItem]) {
        animateStatusAppearance(items)
    }
    
    public override func escapeKeyAction() -> KeyHandlerResult {
        return emojis.escapeKeyAction()
    }
}




public final class SetupQuickReactionController<Context: AccountContextProtocol> : TelegramViewController<Context> {

    public override var defaultBarTitle: String {
        return localizedString("Telegram.SetupQuickReactionController")
    }
    
    private let emojis: EmojiesController<Context>
    
    public let callback: (TelegramMediaFile)->Void
    public init(_ context: Context, callback: @escaping(TelegramMediaFile)->Void) {
        self.emojis = .init(context, mode: .quickReaction)
        self.callback = callback
        super.init(context)
        bar = .init(height: 0)
        _frameRect = NSMakeRect(0, 0, 350, 300)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        emojis._frameRect = self.bounds
        self.view.addSubview(emojis.view)
        self.ready.set(self.emojis.ready.get())
        
        let chatInteraction = EntertainmentUIHooks.shared.makeChatInteraction(context, context.peerId)
        
        let interactions = EntertainmentInteractions(.emoji, peerId: context.peerId)
        
        interactions.sendAnimatedEmoji = { [weak self] item, _, _, _, rect in
            self?.callback(item.file._parse())
            self?.closePopover()
        }
        
        emojis.update(with: interactions, chatInteraction: chatInteraction)
        
        emojis.animateAppearance = { [weak self] items in
            self?.animateAppearanceItems(items)
        }
    }
    
    private func animateAppearanceItems(_ items: [TableRowItem]) {
        animateStatusAppearance(items)
    }
    
    public override func escapeKeyAction() -> KeyHandlerResult {
        return emojis.escapeKeyAction()
    }
}
