import Foundation
import TGUIKit
import Cocoa
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows

public final class ChatListTextActionRowItem : GeneralRowItem {
    public let title: TextViewLayout
    public let info: TextViewLayout
    public let context: any AccountContextProtocol
    public let canDismiss: Bool
    public let icon: CGImage?
    public let dismiss: ()->Void
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, title: NSAttributedString, info: NSAttributedString, icon: CGImage? = nil, canDismiss: Bool, action: @escaping()->Void, dismiss:@escaping()->Void) {
        self.context = context
        self.icon = icon
        self.dismiss = dismiss
        self.title = .init(title, maximumNumberOfLines: 1)
        self.info = .init(info)
        self.canDismiss = canDismiss

        self.info.interactions = LinkHooks.shared.globalLinkExecutor()

        super.init(initialSize, stableId: stableId, action: action)
    }

    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)

        self.title.measure(width: width - 20 - 15 - textInset)
        self.info.measure(width: width - 20 - 15 - textInset)
        return true
    }

    var textInset: CGFloat {
        return icon != nil ? 40 : 0
    }

    public func invoke() {
        action()
    }


    public override func viewClass() -> AnyClass {
        return ChatListTextActionRowView.self
    }

    public override var accessibilityLabel: String? {
        return title.attributedString.string
    }
    
    public override var accessibilityValue: String? {
        return info.attributedString.string
    }
    
    public override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }
    
    public override var accessibilityIncludesChildren: Bool {
        return false
    }
    
    public override func accessibilityPerformPress() -> Bool {
        invoke()
        return true
    }
    
    public override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        guard canDismiss else {
            return nil
        }
        return [NSAccessibilityCustomAction(name: strings().voiceOverCommonClose, handler: { [weak self] in
            self?.dismiss()
            return true
        })]
    }

    public override var height: CGFloat {
        return 5 + 8 + title.layoutSize.height + 3 + info.layoutSize.height + 8
    }
}


private final class ChatListTextActionRowView: TableRowView {
    private let container = View()
    private let titleView = InteractiveTextView()
    private let infoView = InteractiveTextView()
    private let overlay = Control()
    private let dismiss = ImageButton()
    private let iconView = ImageView(frame: NSMakeRect(0, 0, 30, 30))
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        container.layer?.cornerRadius = 10
        if #available(macOS 10.15, *) {
            container.layer?.cornerCurve = .continuous
        }
        container.layer?.borderWidth = 1

        addSubview(container)
        container.addSubview(iconView)
        container.addSubview(titleView)
        container.addSubview(infoView)
        container.addSubview(overlay)
        iconView.isEventLess = true
        iconView.isAccessibilityDecorative = true
        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)
        container.addSubview(dismiss)
        titleView.userInteractionEnabled = false

        infoView.userInteractionEnabled = false


        overlay.set(handler: { [weak self] control in
            if let item = self?.item as? ChatListTextActionRowItem {
                item.invoke()
            }

        }, for: .Click)

        dismiss.set(handler: { [weak self] control in
            if let item = self?.item as? ChatListTextActionRowItem {
                item.dismiss()
            }
        }, for: .Click)
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 5
        let padding: CGFloat = 5
        container.frame = NSMakeRect(inset, padding, frame.width - inset * 2, frame.height - padding)
        overlay.frame = container.bounds
        let textX: CGFloat = 10 + ((item as? ChatListTextActionRowItem)?.textInset ?? 0)
        iconView.centerY(x: 10)
        titleView.setFrameOrigin(NSMakePoint(textX, 8))
        infoView.setFrameOrigin(NSMakePoint(textX, container.frame.height - infoView.frame.height - 8))

        dismiss.centerY(x: container.frame.width - 10 - dismiss.frame.width)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? ChatListTextActionRowItem else {
            return
        }

        overlay.set(background: theme.colors.grayForeground.withAlphaComponent(0.1), for: .Highlight)
        overlay.set(background: .clear, for: .Hover)
        overlay.set(background: .clear, for: .Normal)

        dismiss.isHidden = !item.canDismiss
        iconView.image = item.icon
        iconView.isHidden = item.icon == nil

        self.titleView.set(text: item.title, context: item.context)
        self.infoView.set(text: item.info, context: item.context)
        overlay.setAccessibilityLabel(item.title.attributedString.string)

        dismiss.set(image: TelegramThemeHooks.shared.image(.iconVoiceChatTooltipClose).precomposed(theme.colors.grayIcon), for: .Normal)
        dismiss.autohighlight = false
        dismiss.scaleOnClick = true
        dismiss.sizeToFit(NSMakeSize(10, 10))

        container.backgroundColor = theme.colors.background.withAlphaComponent(0.4)
        container.layer?.borderColor = theme.colors.border.cgColor
        needsLayout = true
    }
}
