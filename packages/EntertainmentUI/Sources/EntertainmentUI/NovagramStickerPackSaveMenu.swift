import Cocoa
import TGUIKit
import TelegramCore
import TelegramContext
import LocalAnimations
import NovagramCore

// "Save All" in the sticker and emoji pack menu, only while the Developer switch "Save sticker packs" is on.
func novagramStickerPackSaveMenuItems(context: any AccountContextProtocol, packs: [(info: StickerPackCollectionInfo, items: [StickerPackItem])]) -> [ContextMenuItem] {
    guard NovagramDeveloperFlags.isStickerPackSaveEnabled, !packs.isEmpty else {
        return []
    }
    let packs = packs.map { NovagramStickerPack(info: $0.info, items: $0.items) }
    return [ContextMenuItem(NovagramL10n.current.stickerPack_saveAll, handler: {
        NovagramStickerPackSaver.save(packs, context: context)
    }, itemImage: MenuAnimation.menu_save_as.value)]
}
