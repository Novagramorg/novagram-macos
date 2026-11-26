import Cocoa
import TGUIKit
import SwiftSignalKit
import WalletUI
import StarsUI

func installWalletUIHooks() {
    var hooks = WalletUIHooks()
    hooks.appPasslock = {
        return (NSApp.delegate as? AppDelegate)?.passlock ?? .single(false)
    }
    hooks.openTonEarnings = { context in
        showModal(with: Star_ListScreen(context: context, currency: .ton, source: .account), for: context.window)
    }
    hooks.openGiftVariants = { context, gift, key in
        let section: StarGift_Builder_Section
        switch key {
        case "model": section = .models
        case "backdrop": section = .backdrops
        case "symbol": section = .symbols
        default: return
        }
        showModal(with: StarGift_ModelBuilderController(context: context, gift: .unique(gift), giftId: gift.giftId, defaultMode: section), for: context.window)
    }
    WalletUIHooks.install(hooks)
}
