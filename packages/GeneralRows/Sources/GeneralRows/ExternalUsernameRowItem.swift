import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import TelegramTheme
import ColorPalette

public final class ExternalUsernameRowItem : GeneralRowItem {
    public let username: TelegramPeerUsername
    fileprivate let title: TextViewLayout
    fileprivate let status: TextViewLayout
    public init(_ initialSize: NSSize, stableId: AnyHashable, username: TelegramPeerUsername, viewType: GeneralViewType, activate: @escaping()->Void) {
        self.username = username
        
        self.title = .init(.initialize(string: "@\(username.username)", color: theme.colors.text, font: .normal(.text)), maximumNumberOfLines: 1)
        
        let status: String = username.flags.contains(.isActive) ? strings().usernameActive : strings().usernameNotActive
        let statusColor = username.flags.contains(.isActive) ? theme.colors.accent : theme.colors.grayText
        
        self.status = .init(.initialize(string: status, color: statusColor, font: .normal(.text)), maximumNumberOfLines: 1)
        
        super.init(initialSize, height: 50, stableId: stableId, viewType: viewType, action: activate)
        _ = makeSize(initialSize.width)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        title.measure(width: width - viewType.innerInset.right - viewType.innerInset.left * 2 - 40 - 40)
        status.measure(width: width - viewType.innerInset.right - viewType.innerInset.left * 2 - 40 - 40)

        
        return true
    }
    
    public override func viewClass() -> AnyClass {
        return ExternalUsernameRowView.self
    }

    public override var accessibilityLabel: String? {
        return title.attributedString.string
    }

    public override var accessibilityValue: String? {
        return status.attributedString.string
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


private final class ExternalUsernameRowView: GeneralContainableRowView {
    private let resort = ImageButton()
    private let title = TextView()
    private let status = TextView()
    private let imageView = ImageView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        addSubview(resort)
        addSubview(title)
        addSubview(status)
        addSubview(imageView)
        
        resort.setAccessibilityLabel(strings().voiceOverCommonReorder)
        imageView.isAccessibilityDecorative = true
        
        title.isSelectable = false
        title.userInteractionEnabled = false
        
        status.isSelectable = false
        status.userInteractionEnabled = false

        
        resort.set(handler: { [weak self] _ in
            if let event = NSApp.currentEvent {
                self?.mouseDown(with: event)
            }
        }, for: .Down)
        
        resort.set(handler: { [weak self] _ in
            if let event = NSApp.currentEvent {
                self?.mouseDragged(with: event)
            }
        }, for: .MouseDragging)
        
        resort.set(handler: { [weak self] _ in
            if let event = NSApp.currentEvent {
                self?.mouseUp(with: event)
            }
        }, for: .Up)
        
        containerView.set(handler: { [weak self] _ in
            if let item = self?.item as? GeneralRowItem {
                item.action()
            }
        }, for: .Click)
        
    }
    
    override func updateColors() {
        super.updateColors()
        containerView.set(background: backdorColor, for: .Normal)
        containerView.set(background: backdorColor.lighter(), for: .Highlight)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        
        guard let item = item as? GeneralRowItem else {
            return
        }
        
        resort.centerY(x: containerView.frame.width - resort.frame.width -  item.viewType.innerInset.right)
        
        imageView.centerY(x: item.viewType.innerInset.left)
        
        title.setFrameOrigin(NSMakePoint(imageView.frame.maxX + item.viewType.innerInset.left, 7))
        status.setFrameOrigin(NSMakePoint(imageView.frame.maxX + item.viewType.innerInset.left, containerView.frame.height - status.frame.height - 7))

    }
    
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? ExternalUsernameRowItem else {
            return
        }
        
        resort.isHidden = !item.username.flags.contains(.isActive)
        
        imageView.setFrameSize(NSMakeSize(35, 35))
        imageView.layer?.cornerRadius = 17.5
        imageView.contentGravity = .center
        if item.username.flags.contains(.isActive) {
            imageView.background = theme.colors.accent
            imageView.image = TelegramThemeHooks.shared.image(.iconExportedInvitationLink).precomposed(.white)
        } else {
            imageView.background = theme.colors.grayBackground.darker()
            imageView.image = TelegramThemeHooks.shared.image(.iconExportedInvitationExpired).precomposed(.white)
        }
        if animated {
            imageView.layer?.animateBackground()
            imageView.layer?.animateContents()
        }
        
        self.title.update(item.title)
        self.status.update(item.status)

        resort.autohighlight = false
        resort.scaleOnClick = true
        
        resort.set(image: theme.icons.resort, for: .Normal)
        resort.sizeToFit()
        
        needsLayout = true
    }
    
}
