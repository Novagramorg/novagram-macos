import Foundation
import Cocoa
import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramContext
import TelegramUtils
import TelegramTheme
import Localization

public class ContextAccountMenuItem : ContextMenuItem {

    private let account: AccountWithInfo
    private let context: any AccountContextProtocol
    private let showBadge: Bool
    public init(account: AccountWithInfo, context: any AccountContextProtocol, showBadge: Bool = true, handler: (() -> Void)? = nil) {
        self.account = account
        self.context = context
        self.showBadge = showBadge
        super.init(account.peer.displayTitle.prefixWithDots(20), handler: handler)
    }

    public required init(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func rowItem(presentation: AppMenu.Presentation, interaction: AppMenuBasicItem.Interaction) -> TableRowItem {
        let badge: GlobalBadgeNode? = showBadge ? GlobalBadgeNode(account.account, sharedContext: context.sharedContext, getColor: { selected in
            theme.colors.accent
        }) : nil
        return ContextAccountMenuRowItem(.zero, item: self, interaction: interaction, presentation: presentation, account: account, badge: badge)
    }
}


private final class ContextAccountMenuRowItem : AppMenuRowItem {
    let badge: GlobalBadgeNode?
    private let peerTitle: String
    private let disposable = MetaDisposable()
    init(_ initialSize: NSSize, item: ContextMenuItem, interaction: AppMenuBasicItem.Interaction, presentation: AppMenu.Presentation, account: AccountWithInfo, badge: GlobalBadgeNode?) {
        self.badge = badge
        self.peerTitle = account.peer.displayTitle
        badge?.customLayout = true

        item.image = NSImage(size: NSMakeSize(18, 18))

        super.init(initialSize, item: item, interaction: interaction, presentation: presentation)

        let signal: Signal<(CGImage?, Bool), NoError>
        signal = peerAvatarImage(account: account.account, photo: .peer(account.peer, account.peer.smallProfileImage, account.peer.namePeerColor, TelegramUtilsHooks.shared.peerLetters(account.peer), nil, nil), displayDimensions: NSMakeSize(18 * System.backingScale, 18 * System.backingScale), font: .avatar(13), genCap: true, synchronousLoad: false) |> deliverOnMainQueue
        disposable.set(signal.start(next: { [weak item] image, _ in
            if let image = image {
                item?.image = NSImage(cgImage: image, size: NSMakeSize(18, 18))
            }
        }))
    }

    deinit {
        disposable.dispose()
    }

    override var effectiveSize: NSSize {
        var size = super.effectiveSize
        if let badge = badge {
            size.width += max(40, badge.size.width)
        }
        return size
    }

    override func viewClass() -> AnyClass {
        return ContextAccountMenuRowView.self
    }

    override var accessibilityLabel: String? {
        return peerTitle.isEmpty ? super.accessibilityLabel : peerTitle
    }

    override var accessibilityValue: String? {
        if let badge = badge, badge.unreadCount > 0 {
            return strings().voiceOverChatUnreadMessagesOther(Int(badge.unreadCount))
        }
        return super.accessibilityValue
    }
}

private final class ContextAccountMenuRowView : AppMenuRowView {
    private let badgeView = View()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(badgeView)
    }

    override func layout() {
        super.layout()
        badgeView.centerY(x: self.rightX - badgeView.frame.width)
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? ContextAccountMenuRowItem else {
            return
        }
        if let badge = item.badge {
            badgeView.isHidden = false
            self.badgeView.setFrameSize(badge.size)
            badge.view = badgeView

            badge.onUpdate = { [weak item, weak self] in
                if let badge = item?.badge, let view = self?.badgeView {
                    view.setFrameSize(badge.size)
                }
                self?.needsLayout = true
            }
        } else {
            badgeView.isHidden = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
