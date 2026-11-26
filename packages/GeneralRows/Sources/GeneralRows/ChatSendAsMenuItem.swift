import Foundation
import Cocoa
import TGUIKit
import TelegramTheme
import ColorPalette
import Localization
import TelegramContext
import TelegramUtils
import Postbox
import SwiftSignalKit
import TelegramCore

public class ContextSendAsMenuItem : ContextMenuItem {
    
    private let peer: SendAsPeer
    private let context: (any AccountContextProtocol)
    private let isSelected: Bool
    public init(peer: SendAsPeer, context: (any AccountContextProtocol), isSelected: Bool, handler: (() -> Void)? = nil) {
        self.peer = peer
        self.context = context
        self.isSelected = isSelected
        super.init(peer.peer._asPeer().displayTitle.prefixWithDots(20), handler: handler)
    }
    
    public required init(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func rowItem(presentation: AppMenu.Presentation, interaction: AppMenuBasicItem.Interaction) -> TableRowItem {
        return ContextSendAsMenuRowItem(.zero, item: self, interaction: interaction, presentation: presentation, peer: peer, context: context, isSelected: isSelected)
    }
}


private final class ContextSendAsMenuRowItem : AppMenuRowItem {
    private let disposable = MetaDisposable()
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let statusLayout: TextViewLayout
    fileprivate let peer: SendAsPeer
    fileprivate let selected: Bool
    public init(_ initialSize: NSSize, item: ContextMenuItem, interaction: AppMenuBasicItem.Interaction, presentation: AppMenu.Presentation, peer: SendAsPeer, context: (any AccountContextProtocol), isSelected: Bool) {
        
        self.peer = peer
        self.context = context
        self.selected = isSelected
        let status: String
        if peer.peer._asPeer().isUser {
            status = strings().chatSendAsPersonalAccount
        } else {
            if peer.peer._asPeer().isGroup || peer.peer._asPeer().isSupergroup {
                if peer.subscribers != nil {
                    status = strings().chatSendAsGroupOther(Int(peer.subscribers ?? 0))
                } else {
                    status = strings().peerStatusGroup
                }
            } else {
                if peer.subscribers != nil {
                    status = strings().chatSendAsChannelOther(Int(peer.subscribers ?? 0))
                } else {
                    status = strings().peerStatusChannel
                }
            }
        }
        self.statusLayout = .init(.initialize(string: status, color: presentation.disabledTextColor, font: .normal(.text)))
        
        super.init(initialSize, item: item, interaction: interaction, presentation: presentation)
        
        let signal:Signal<(CGImage?, Bool), NoError>
        
        let peer = self.peer.peer._asPeer()

        signal = peerAvatarImage(account: context.account, photo: .peer(peer, peer.smallProfileImage, peer.namePeerColor, peer.displayLetters, nil, nil), displayDimensions: NSMakeSize(25 * System.backingScale, 25 * System.backingScale), font: .avatar(14), genCap: true, synchronousLoad: false, disableForum: true) |> deliverOnMainQueue
        disposable.set(signal.start(next: { [weak item] image, _ in
            if let image = image {
                item?.image = NSImage(cgImage: image, size: NSMakeSize(25, 25))
            }
        }))
    }
    
    public override var imageSize: CGFloat {
        return 25
    }
    
    deinit {
        disposable.dispose()
    }
    
    public override var textSize: CGFloat {
        return max(text.layoutSize.width, statusLayout.layoutSize.width) + leftInset * 2 + innerInset * 2
    }
    
    public override var effectiveSize: NSSize {
        var size = super.effectiveSize
        
        if peer.isPremiumRequired && !context.isPremium {
            size.width += 15
        }
        
        return size
    }
    
    public override var height: CGFloat {
        return 35
    }
    
    public override func makeSize(_ width: CGFloat = CGFloat.greatestFiniteMagnitude, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        self.statusLayout.measure(width: width - leftInset * 2 - innerInset * 2)

        return true
    }
    
    public override func viewClass() -> AnyClass {
        return ContextAccountMenuRowView.self
    }

    public override var accessibilityLabel: String? {
        let title = peer.peer._asPeer().displayTitle
        return title.isEmpty ? super.accessibilityLabel : title
    }

    public override var accessibilityValue: String? {
        var values: [String] = []
        if selected {
            values.append(strings().voiceOverCommonSelected)
        }
        let status = statusLayout.attributedString.string
        if !status.isEmpty {
            values.append(status)
        }
        if peer.isPremiumRequired && !context.isPremium {
            values.append(strings().voiceOverCommonPremium)
        }
        return values.isEmpty ? nil : values.joined(separator: ", ")
    }
}

private final class ContextAccountMenuRowView : AppMenuRowView {
    private let statusView: TextView = TextView()
    private var borderView: View?
    private var lockView: ImageView?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(statusView)
        statusView.userInteractionEnabled = false
        statusView.isSelectable = false
        
    }
    
    public override func layout() {
        super.layout()
        
        guard let item = item as? ContextSendAsMenuRowItem else {
            return
        }
        
        statusView.setFrameOrigin(NSMakePoint(textX, textY + 14))
        if let borderView = borderView {
            borderView.frame = imageFrame.insetBy(dx: -2, dy: -2)
        }
        if let lockView = lockView {
            lockView.setFrameOrigin(textX + item.text.layoutSize.width, textY)
        }
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? ContextSendAsMenuRowItem else {
            return
        }
        
        statusView.update(item.statusLayout)
        
        if item.peer.isPremiumRequired && !item.context.isPremium {
            let current: ImageView
            if let view = self.lockView {
                current = view
            } else {
                current = ImageView()
                current.isAccessibilityDecorative = true
                addSubview(current)
                self.lockView = current
            }
            current.image = TelegramThemeHooks.shared.image(.iconEmojiLock).precomposed(item.presentation.disabledTextColor)
            current.sizeToFit()
        } else if let view = self.lockView {
            performSubviewRemoval(view, animated: animated)
            self.lockView = nil
        }
        if item.selected {
            let current: View
            if let view = borderView {
                current = view
            } else {
                current = View()
                self.borderView = current
                addSubview(current)
            }
            current.setFrameSize(NSMakeSize(item.imageSize + 4, item.imageSize + 4))
            current.layer?.cornerRadius = current.frame.height / 2
            current.layer?.borderWidth = 1
            current.layer?.borderColor = item.presentation.colors.accent.cgColor
        } else if let view = borderView {
            performSubviewRemoval(view, animated: animated)
        }
    }
    
    
    public override var textY: CGFloat {
        return 2
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
