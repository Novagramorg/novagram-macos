import Foundation
import Cocoa
import TelegramCore
import Postbox
import SwiftSignalKit
import TGUIKit
import AvatarUI
import GeneralRows
import Localization
import TelegramTheme
import ColorPalette

public final class JoinVoiceChatAlertRowItem : GeneralRowItem {
    fileprivate let account: Account
    fileprivate let peer: Peer
    fileprivate let titleLayout: TextViewLayout
    public init(_ initialSize: NSSize, stableId: AnyHashable, account: Account, peer: Peer, title: String, participantsCount: Int) {
        self.account = account
        self.peer = peer
        
        let attr = NSMutableAttributedString()
        
        _ = attr.append(string: title, color: theme.colors.text, font: .medium(.title))
        _ = attr.append(string: "\n")
        _ = attr.append(string: strings().chatVoiceChatJoinLinkParticipantsOther(participantsCount), color: theme.colors.grayText, font: .normal(.text))
        
        
        self.titleLayout = TextViewLayout(attr, alignment: .center)
     
        super.init(initialSize, stableId: stableId)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        self.titleLayout.measure(width: width - 60)
        return true
    }
    
    public override var height: CGFloat {
        return 70 + 10 + self.titleLayout.layoutSize.height
    }

    public override var accessibilityLabel: String? {
        return titleLayout.attributedString.string
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }
    
    public override func viewClass() -> AnyClass {
        return JoinVoiceChatAlertRowView.self
    }
}

private final class JoinVoiceChatAlertRowView : TableRowView {
    private let avatar: AvatarControl = AvatarControl(font: .avatar(20))
    private let title: TextView = TextView()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        avatar.setFrameSize(NSMakeSize(70, 70))
        addSubview(avatar)
        addSubview(title)
        title.userInteractionEnabled = false
        title.isSelectable = false
    }
    
    public override func updateColors() {
        super.updateColors()
        self.title.backgroundColor = backdorColor
    }
    
    public override func layout() {
        super.layout()
        avatar.centerX(y: 0)
        title.centerX(y: avatar.frame.maxY + 10)
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? JoinVoiceChatAlertRowItem else {
            return
        }
        title.update(item.titleLayout)
        avatar.setPeer(account: item.account, peer: item.peer)
    }
    
    public override var backdorColor: NSColor {
        return theme.colors.listBackground
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
