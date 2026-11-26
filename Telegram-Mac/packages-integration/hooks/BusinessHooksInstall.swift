import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import BusinessUI
import TelegramUtils

extension StickerMediaContentView: @retroactive BusinessStickerPreviewView {
    public func updateBusinessSticker(file: TelegramMediaFile, size: NSSize, context: any AccountContextProtocol) {
        guard let context = context as? AccountContext else {
            return
        }
        self.update(with: file, size: size, context: context, parent: nil, table: nil)
    }
}

private final class AppBusinessStickerPicker: BusinessStickerPicker {
    private let stickers: NStickersViewController

    init(_ context: AccountContext, picked: @escaping (TelegramMediaFile) -> Void) {
        self.stickers = NStickersViewController(context)
        self.stickers.mode = .intro
        let interactions = EntertainmentInteractions(.stickers, peerId: context.peerId)
        interactions.sendSticker = { [weak self] sticker, _, _, _ in
            picked(sticker)
            self?.stickers.closePopover()
        }
        self.stickers.update(with: interactions, chatInteraction: ChatInteraction(chatLocation: .peer(context.peerId), context: context))
    }

    func showStickerPicker(for control: Control) {
        showPopover(for: control, with: stickers, edge: .maxY, static: true)
    }
}

private func filterCategory(_ category: BusinessChatCategory) -> ChatListFilterPeerCategories {
    switch category {
    case .existingChats:
        return .existingChats
    case .newChats:
        return .newChats
    case .contacts:
        return .contacts
    case .nonContacts:
        return .nonContacts
    }
}

func installBusinessUIHooks() {
    installBusinessHooks(.init(makeStickerPreviewView: { frame in
        return StickerMediaContentView(frame: frame)
    }, makeStickerPicker: { context, picked in
        return AppBusinessStickerPicker(context as! AccountContext, picked: picked)
    }, makeStickerHeaderRow: { initialSize, stableId, context, sticker, text in
        guard let context = context as? AccountContext else {
            preconditionFailure("business header row requires a concrete AccountContext")
        }
        return AnimatedStickerHeaderItem(initialSize, stableId: stableId, context: context, sticker: sticker, text: text)
    }, openCustomChat: { context, mode, initialAction in
        guard let context = context as? AccountContext else {
            return
        }
        context.bindings.rootNavigation().push(ChatAdditionController(context: context, chatLocation: .peer(context.peerId), mode: mode, initialAction: initialAction))
    }, shareLink: { context, link in
        guard let context = context as? AccountContext else {
            return
        }
        showModal(with: ShareModalController(ShareLinkObject(context, link: link)), for: context.window)
    }, selectChats: { context, request in
        guard let context = context as? AccountContext else {
            return
        }
        let items = request.categories.map { ShareAdditionItem(peer: TelegramFilterCategory(category: filterCategory($0)), status: "") }
        let additionTopItems = items.isEmpty ? nil : ShareAdditionItems(items: items, topSeparator: request.categoriesTopSeparator, bottomSeparator: request.categoriesBottomSeparator)
        showModal(with: ShareModalController(BusinessSelectChatsCallbackObject(context, defaultSelectedIds: request.selected, contacts: request.contacts, additionTopItems: additionTopItems, limit: request.limit, limitReachedText: request.limitReachedText, callback: request.callback, excludePeerIds: request.excludePeerIds)), for: context.window)
    }))
}
