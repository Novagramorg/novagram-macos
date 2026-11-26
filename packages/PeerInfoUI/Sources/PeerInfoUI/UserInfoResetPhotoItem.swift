import Foundation
import Cocoa
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramTheme
import TelegramContext
import GeneralRows
import AvatarUI

public final class UserInfoResetPhotoItem : GeneralRowItem {
    fileprivate let image: TelegramMediaImage?
    private let _user: TelegramUser
    let nameLayout: TextViewLayout
    let context: any AccountContextProtocol
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, string: String, style: ControlStyle = blueActionButton, user: TelegramUser, image: TelegramMediaImage?, viewType: GeneralViewType, action: @escaping()->Void) {
        self.image = image
        self._user = user
        self.context = context
        self.nameLayout = TextViewLayout(.initialize(string: string, color: style.foregroundColor, font: style.font))
        super.init(initialSize, height: 42, stableId: stableId, viewType: viewType, action: action)
    }
    
    var user: TelegramUser {
        return _user.withUpdatedPhoto(image?.representations ?? [])
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        self.nameLayout.measure(width: width - viewType.innerInset.left - viewType.innerInset.right - 24 - viewType.innerInset.left)
        return true
    }
    
    var textInset: CGFloat {
        return viewType.innerInset.left * 2 + 24
    }
    
    public override func viewClass() -> AnyClass {
        return UserInfoResetPhotoView.self
    }
    
    public override var accessibilityLabel: String? {
        let text = nameLayout.attributedString.string
        return text.isEmpty ? nil : text
    }
    
    public override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }
    
    public override var accessibilityIncludesChildren: Bool {
        return false
    }
    
    public override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }
    
}

private final class UserInfoResetPhotoView: GeneralContainableRowView {
    private let textView: TextView = TextView()
    private let avatar = AvatarControl(font: .avatar(12))
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        addSubview(avatar)
        avatar.setFrameSize(NSMakeSize(30, 30))
        textView.isSelectable = false
        textView.userInteractionEnabled = false
        avatar.userInteractionEnabled = false
        
        containerView.setStateChangeHandler { [weak self] in
            self?.updateColors()
        }
        
        
        containerView.set(handler: { [weak self] _ in
            if let item = self?.item as? GeneralRowItem {
                item.action()
            }
        }, for: .Click)
        
    }
    
    override func updateColors() {
        super.updateColors()
        if let item = item as? GeneralRowItem {
            self.background = item.viewType.rowBackground
            let highlighted = isSelect ? self.backdorColor : highlightColor
            textView.backgroundColor = containerView.controlState == .Highlight && !isSelect ? .clear : self.backdorColor
            containerView.set(background: self.backdorColor, for: .Normal)
            containerView.set(background: highlighted, for: .Highlight)
        }
    }
    
    var highlightColor: NSColor {
        return theme.colors.grayHighlight
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        guard let item = item as? UserInfoResetPhotoItem else {
            return
        }
        transition.updateFrame(view: avatar, frame: avatar.centerFrameY(x: item.viewType.innerInset.left))
        transition.updateFrame(view: textView, frame: textView.centerFrameY(x: item.textInset))
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? UserInfoResetPhotoItem else {
            return
        }
        
        avatar.setPeer(account: item.context.account, peer: item.user)
        
        textView.update(item.nameLayout)
    }
}
