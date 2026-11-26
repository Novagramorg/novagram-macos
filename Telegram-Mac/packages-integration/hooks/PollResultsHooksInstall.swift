import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import PollResultsUI

func installPollResultsUIHooks() {
    PollResultsHooks.install(PollResultsHooks(
        openPeerInfo: { context, peerId in
        guard let context = context as? AccountContext else {
            return
        }
        PeerInfoController.push(navigation: context.bindings.rootNavigation(), context: context, peerId: peerId) },
        makeStickersPicker: { context, peerId, interaction, invokeSticker in
            guard let context = context as? AccountContext, let chatInteraction = interaction as? ChatInteraction else {
                return ViewController()
            }
            let stickersController = NStickersViewController(context)
            stickersController.mode = .intro
            let stickerInteractions = EntertainmentInteractions(.stickers, peerId: peerId)
            stickerInteractions.sendSticker = { [weak stickersController] file, _, _, _ in
                invokeSticker(file)
                stickersController?.closePopover()
            }
            stickersController.update(with: stickerInteractions, chatInteraction: chatInteraction)
            return stickersController
        },
        generateMedia: { container, account, isSecretRelated in
            return Sender.generateMedia(for: container, account: account, isSecretRelated: isSecretRelated)
        }
    ))
}

