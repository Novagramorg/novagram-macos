import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramTheme
import TelegramContext
import GeneralRows
import AvatarUI
import TelegramUtils

public final class ChangePeerRowItem: GeneralRowItem {

    fileprivate let fromPeer: EnginePeer
    fileprivate let toPeer: EnginePeer
    fileprivate let context: any AccountContextProtocol
    public init(
        _ initialSize: NSSize,
        stableId: AnyHashable,
        context: any AccountContextProtocol,
        fromPeer: EnginePeer,
        toPeer: EnginePeer
    ) {
        self.fromPeer = fromPeer
        self.toPeer = toPeer
        self.context = context
        super.init(initialSize, stableId: stableId)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        return true
    }
    
    public override var height: CGFloat {
        return 55
    }
    
    public override func viewClass() -> AnyClass {
        return ChangePeerRowItemView.self
    }

    public override var accessibilityLabel: String? {
        return "\(fromPeer._asPeer().displayTitle) → \(toPeer._asPeer().displayTitle)"
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }
}

private final class ChangePeerRowItemView: GeneralRowView {
    
    private let fromAvatar = AvatarControl(font: .avatar(15))
    private let toAvatar = AvatarControl(font: .avatar(15))
    private let chevron = ImageView()
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        addSubview(fromAvatar)
        addSubview(toAvatar)
        addSubview(chevron)
        
        fromAvatar.userInteractionEnabled = false
        toAvatar.userInteractionEnabled = false
        
        fromAvatar.setFrameSize(NSMakeSize(45, 45))
        toAvatar.setFrameSize(NSMakeSize(45, 45))
        
        chevron.image = TelegramThemeHooks.shared.image(.iconAffiliateChevron).precomposed(theme.colors.grayIcon)
        chevron.sizeToFit()
        chevron.isAccessibilityDecorative = true
    }
    
    override var backdorColor: NSColor {
        return .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? ChangePeerRowItem else { return }
        
        let account = item.context.account
        
        fromAvatar.setPeer(account: account, peer: item.fromPeer._asPeer())
        toAvatar.setPeer(account: account, peer: item.toPeer._asPeer())

        needsLayout = true
    }
    
    override func layout() {
        super.layout()
        
        let totalWidth = fromAvatar.frame.width + 12 + chevron.frame.width + 12 + toAvatar.frame.width
        let originX = floor((bounds.width - totalWidth) / 2.0)
        
        fromAvatar.centerY(x: originX, addition: -5)
        chevron.centerY(x: fromAvatar.frame.maxX + 12, addition: -5)
        toAvatar.centerY(x: chevron.frame.maxX + 12, addition: -5)
    }
}
