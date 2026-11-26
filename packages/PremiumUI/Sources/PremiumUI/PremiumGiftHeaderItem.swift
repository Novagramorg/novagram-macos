import Cocoa
import Foundation
import TGUIKit
import TelegramMedia
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import LocalAnimations
import CurrencyFormat
import SceneEffects
import InAppPurchaseManager
import InlineStickers
import ObjcUtils

public final class PremiumGiftHeaderItem : GeneralRowItem {
    
    public enum Source {
        case gift(Peer)
        case giftLink
    }
    
    public let textLayout: TextViewLayout
    public let titleLayout: TextViewLayout?

    public let photoSize = NSMakeSize(100, 100)
    
    public let source: Source
    public let context: (any AccountContextProtocol)
    
    
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), source: Source) {
        
        self.source = source
        self.context = context
        
        switch source {
        case let .gift(peer):
            titleLayout = .init(.initialize(string: strings().premiumGiftTitle, color: theme.colors.text, font: .bold(18)), alignment: .center)
            
            let text = NSMutableAttributedString()
            _ = text.append(string: strings().premiumGiftText(peer.displayTitle), color: theme.colors.text, font: .normal(.text))
            text.detectBoldColorInString(with: .medium(.text))
            textLayout = .init(text, alignment: .center)
        case .giftLink:
            let text = NSMutableAttributedString()
            _ = text.append(string: strings().giftLinkInfoNotUsed, color: theme.colors.text, font: .normal(.text))
            text.detectBoldColorInString(with: .medium(.text))
            textLayout = .init(text, alignment: .center)
            self.titleLayout = nil
        }
        

        super.init(initialSize, stableId: stableId)
        
        _ = makeSize(initialSize.width)
    }
    
    public override var accessibilityLabel: String? {
        return titleLayout?.attributedString.string ?? textLayout.attributedString.string
    }

    public override var accessibilityValue: String? {
        return titleLayout != nil ? textLayout.attributedString.string : nil
    }

    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        titleLayout?.measure(width: width - 40)
        textLayout.measure(width: width - 40)
        
        return true
    }
    
    public override var height: CGFloat {
        if let titleLayout = titleLayout {
            return photoSize.height + 20 + titleLayout.layoutSize.height + 10 + textLayout.layoutSize.height
        } else {
            return photoSize.height + 20 + textLayout.layoutSize.height
        }
    }
    
    public override func viewClass() -> AnyClass {
        return PremiumGiftHeaderView.self
    }
}


private final class PremiumGiftHeaderView: TableRowView {
    
    private let avatar = AvatarControl(font: .avatar(.header))
    private let textView = TextView()
    private let titleView = TextView()
//    private let scene: PremiumGiftStarSceneView = PremiumGiftStarSceneView(frame: NSMakeRect(0, 0, 200, 200))
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        avatar.setFrameSize(NSMakeSize(100, 100))
        addSubview(textView)
        addSubview(titleView)
        
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        
        avatar.setFrameSize(NSMakeSize(100, 100))
//        addSubview(scene)
        
//        scene.updateLayout(size: scene.frame.size, transition: .immediate)
        addSubview(avatar)
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public override func layout() {
        super.layout()
        avatar.centerX(y: 0)
        titleView.centerX(y: avatar.frame.maxY + 20)
        textView.centerX(y: titleView.frame.maxY + 10)
//        scene.centerX(y: -50)
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? PremiumGiftHeaderItem else {
            return
        }
        
        titleView.update(item.titleLayout)
        textView.update(item.textLayout)
        switch item.source {
        case let .gift(peer):
            avatar.setPeer(account: item.context.account, peer: peer)
            avatar.isHidden = false
        case .giftLink:
            avatar.isHidden = true
        }
        
        needsLayout = true
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
