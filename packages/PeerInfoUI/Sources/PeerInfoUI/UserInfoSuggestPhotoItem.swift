import Foundation
import TelegramCore
import SwiftSignalKit
import Postbox
import TGUIKit
import TelegramMedia
import Cocoa
import TelegramContext
import TelegramUtils
import TelegramTheme
import Localization
import GeneralRows
import AvatarUI

final class UserInfoSuggestPhotoItem : GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let user: TelegramUser
    fileprivate let thumb: URL
    fileprivate let textLayout: TextViewLayout
    
    init(_ initialSize: NSSize, context: any AccountContextProtocol, stableId: AnyHashable, user: TelegramUser, thumb: URL, type: UserInfoArgumentsSetPhotoType, viewType: GeneralViewType) {
        self.context = context
        self.user = user
        self.thumb = thumb
        let text: String
        switch type {
        case .set:
            text = strings().userInfoSetPhotoConfirm(user.compactDisplayTitle, user.compactDisplayTitle)
        case .suggest:
            text = strings().userInfoSuggestConfirm(user.compactDisplayTitle)
        }
        self.textLayout = .init(.initialize(string: text, color: theme.colors.listGrayText, font: .normal(.text)), alignment: .center)
        
        super.init(initialSize, stableId: stableId, viewType: viewType)
        
        _ = makeSize(initialSize.width)
    }
    
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        self.textLayout.measure(width: blockWidth - viewType.innerInset.left - viewType.innerInset.right)
        
        return true
    }
    
    override var height: CGFloat {
        return 50 + viewType.innerInset.top + textLayout.layoutSize.height
    }
    
    override func viewClass() -> AnyClass {
        return UserInfoSuggestPhotoView.self
    }
    
    override var accessibilityLabel: String? {
        let text = textLayout.attributedString.string
        return text.isEmpty ? nil : text
    }
}


private final class UserInfoSuggestPhotoView: GeneralContainableRowView {
    private let textView = TextView()
    private let imageContainer = View()
    private let imageView = ImageView()
    private let newPhoto = ImageView()
    private let currentPhoto = AvatarControl(font: .avatar(20))
    
    private var photoVideoView: MediaPlayerView?
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        addSubview(imageContainer)
        imageContainer.addSubview(imageView)
        imageContainer.addSubview(newPhoto)
        imageContainer.addSubview(currentPhoto)
        
        currentPhoto.setFrameSize(NSMakeSize(50, 50))
        newPhoto.setFrameSize(NSMakeSize(50, 50))

        imageView.image = TelegramThemeHooks.shared.image(.iconContactPhotoChevron).precomposed(theme.colors.grayIcon)
        imageView.sizeToFit()
        imageView.isAccessibilityDecorative = true
        newPhoto.setAccessibilityLabel(strings().voiceOverCommonPhoto)
        
        newPhoto.contentGravity = .resizeAspect
        
        newPhoto.layer?.cornerRadius = newPhoto.frame.height / 2
        
        imageContainer.setFrameSize(NSMakeSize(50 + 50 + 50, 50))
        textView.isSelectable = false
        textView.userInteractionEnabled = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        
        guard item is GeneralRowItem else {
            return
        }
        
        imageContainer.centerX(y: 0)
        imageView.center()
        
        currentPhoto.centerY(x: 0)
        newPhoto.centerY(x: imageContainer.frame.width - newPhoto.frame.width)
        
        photoVideoView?.frame = newPhoto.frame

        textView.centerX(y: containerView.frame.height - textView.frame.height)
    }
    
    override var backdorColor: NSColor {
        return .clear
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? UserInfoSuggestPhotoItem else {
            return
        }
        
        currentPhoto.setPeer(account: item.context.account, peer: item.user)
        
        newPhoto.image = NSImage(contentsOf: item.thumb)?._cgImage
        
        textView.update(item.textLayout)
    }
}
