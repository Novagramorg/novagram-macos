import Foundation
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import Cocoa
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMedia
import TelegramMediaUtils
import TelegramMediaResources
import InAppSettings
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils
import ChatHistoryModel
import AvatarUI
import GeneralRows
import PremiumUI



public final class ChatInputSendAsView : Control {
    private weak var chatInteraction: ChatInteraction?
    private var peers: [SendAsPeer]?
    private var currentPeerId: PeerId?
    private var avatar: AvatarControl?
    
    public var menuPresentation: AppMenu.Presentation?
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.scaleOnClick = true

        
        
        self.contextMenu = { [weak self] in
            
            let menu = ContextMenu(presentation: self?.menuPresentation ?? .init(colors: theme.colors), betterInside: true)
            
            guard let list = self?.peers else {
                return nil
            }
            guard let chatInteraction = self?.chatInteraction else {
                return nil
            }
            let currentPeerId = self?.currentPeerId
            
            let context = chatInteraction.interactionContext
            
            var items:[ContextMenuItem] = []
            
            var peers = list
            if let index = peers.firstIndex(where: { $0.peer.id == currentPeerId }) {
                peers.move(at: index, to: 0)
            }
            let header = ContextMenuItem(strings().chatSendAsHeader)
            header.isEnabled = false
            items.append(header)
            
            for (i, peer) in peers.enumerated() {
                items.append(ContextSendAsMenuItem(peer: peer, context: context, isSelected: i == 0, handler: { [weak self] in
                    self?.toggleSendAs(peer, context: context)
                }))
            }
                    
            for item in items {
                menu.addItem(item)
            }
            return menu
        }
        
    }
    
    
    private func toggleSendAs(_ peer: SendAsPeer, context: any AccountContextProtocol) {
        if peer.isPremiumRequired && !context.isPremium {
            prem(with: PremiumBoardingController(context: context, source: .send_as), for: context.window)
        } else {
            self.chatInteraction?.toggleSendAs(peer.peer.id)
        }
    }
    
    public override func layout() {
        super.layout()
        guard let avatar = self.avatar else {
            return
        }
        if avatar.frame.width == 30 {
            avatar.centerY(x: frame.width - avatar.frame.width)
        } else {
            avatar.center()
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public var first: Bool = true
    
    public func update(_ peers: [SendAsPeer], currentPeerId: PeerId, chatInteraction: ChatInteraction, animated: Bool, photoSize: CGFloat = 30) {
        let currentIsUpdated = self.currentPeerId != currentPeerId
        self.currentPeerId = currentPeerId
        self.peers = peers
        self.chatInteraction = chatInteraction
        
        let currentPeer = peers.first(where: { $0.peer.id == currentPeerId })
        if currentIsUpdated {
            
            if let view = self.avatar {
                if animated {
                    view.layer?.animateScaleSpring(from: 1, to: 0.1, duration: 0.3, removeOnCompletion: false, completion: { [weak view] _ in
                        view?.removeFromSuperview()
                    })
                } else {
                    view.removeFromSuperview()
                }
            }
            let avatar = AvatarControl(font: .avatar(13))
            avatar.frame = NSMakeRect(0, 0, photoSize, photoSize)
            avatar.userInteractionEnabled = false
            avatar.setPeer(account: chatInteraction.interactionContext.account, peer: currentPeer?.peer._asPeer())
            self.addSubview(avatar)
            if photoSize != 30 {
                avatar.center()
            } else {
                avatar.centerY(x: frame.width - avatar.frame.width)
            }
            self.avatar = avatar
            
            if animated, !first {
                avatar.layer?.animateScaleSpring(from: 0.1, to: 1.0, duration: 0.3)
            }
            first = false
        }
    }
}
