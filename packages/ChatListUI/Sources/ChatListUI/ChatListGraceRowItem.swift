import Foundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Cocoa
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import InputDataUI

public final class ChatListGraceRowItem : GeneralRowItem {
    public let title: TextViewLayout
    public let info: TextViewLayout
    public let context: any AccountContextProtocol
    public let canClose: Bool
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, canClose: Bool) {
        self.context = context
        self.canClose = canClose
        self.title = .init(.initialize(string: strings().chatListGracePeriodTitle, color: theme.colors.text, font: .medium(.text)), maximumNumberOfLines: 1)
        self.info = .init(.initialize(string: strings().chatListGracePeriodInfo, color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 2)
        super.init(initialSize, stableId: stableId)
    }

    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)

        self.title.measure(width: width - 20 - 15)
        self.info.measure(width: width - 20 - 15)
        return true
    }

    public func invoke() {
        FeatureNavigationHooks.shared.showPremiumBoarding(context, context.window, .gracePeriod, false, nil)
        let _ = self.context.engine.notices.dismissServerProvidedSuggestion(suggestion: ServerProvidedSuggestion.gracePremium.id).startStandalone()
    }

    public func dismiss() {
    }

    public override func viewClass() -> AnyClass {
        return ChatListGraceRowView.self
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
        guard canClose else {
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


private final class ChatListGraceRowView: TableRowView {
    private let container = View()
    private let titleView = TextView()
    private let infoView = TextView()
    private let overlay = Control()
    private let dismiss = ImageButton()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        container.layer?.cornerRadius = 10
        if #available(macOS 10.15, *) {
            container.layer?.cornerCurve = .continuous
        }
        container.layer?.borderWidth = 1

        addSubview(container)
        container.addSubview(titleView)
        container.addSubview(infoView)
        container.addSubview(overlay)
        container.addSubview(dismiss)
        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false

        infoView.userInteractionEnabled = false
        infoView.isSelectable = false

        overlay.set(handler: { [weak self] control in
            if let item = self?.item as? ChatListGraceRowItem {
                item.invoke()
            }

        }, for: .Click)

        dismiss.set(handler: { [weak self] control in
            if let item = self?.item as? ChatListGraceRowItem {
                item.dismiss()
            }
        }, for: .Click)
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 10
        let padding: CGFloat = 5
        container.frame = NSMakeRect(inset, padding, frame.width - inset * 2, frame.height - padding)
        overlay.frame = container.bounds
        titleView.setFrameOrigin(NSMakePoint(10, 8))
        infoView.setFrameOrigin(NSMakePoint(10, container.frame.height - infoView.frame.height - 8))

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

        guard let item = item as? ChatListGraceRowItem else {
            return
        }

        self.titleView.update(item.title)
        self.infoView.update(item.info)
        overlay.setAccessibilityLabel(item.title.attributedString.string)

        dismiss.set(image: TelegramThemeHooks.shared.image(.iconVoiceChatTooltipClose).precomposed(theme.colors.grayIcon), for: .Normal)
        dismiss.autohighlight = false
        dismiss.scaleOnClick = true
        dismiss.sizeToFit(NSMakeSize(10, 10))

        dismiss.isHidden = !item.canClose

        container.backgroundColor = theme.colors.background.withAlphaComponent(0.4)
        container.layer?.borderColor = theme.colors.border.cgColor
    }
}
