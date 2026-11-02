import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import TelegramContext
import TelegramTheme
import GeneralRows
import AvatarUI
import NovagramCore
import NovagramSearchKit

final class NovagramSuperSearchResultRowItem: GeneralRowItem {
    fileprivate static let padding: CGFloat = 12
    fileprivate static let avatarSize: CGFloat = 36
    fileprivate static let spacing: CGFloat = 6
    private static let snippetLines: Int32 = 3

    let context: any AccountContextProtocol
    let item: NovagramSuperSearchItem
    let headerLayout: TextViewLayout
    let snippetLayout: TextViewLayout
    let open: () -> Void

    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, item: NovagramSuperSearchItem, viewType: GeneralViewType, open: @escaping () -> Void) {
        self.context = context
        self.item = item
        self.open = open
        let hit = item.hit
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        var details = [formatter.string(from: Date(timeIntervalSince1970: TimeInterval(hit.date))), novagramSuperSearchSourceTitle(hit.source)]
        if item.isDeleted {
            details.append(NovagramL10n.current.superSearch_deleted)
        }
        let header = NSMutableAttributedString()
        header.append(NSAttributedString(string: hit.chatTitle, attributes: [.font: NSFont.medium(.text), .foregroundColor: theme.colors.text]))
        header.append(NSAttributedString(string: "\n" + details.joined(separator: " · "), attributes: [.font: NSFont.normal(.small), .foregroundColor: theme.colors.grayText]))
        self.headerLayout = TextViewLayout(header, maximumNumberOfLines: 2)
        let text = hit.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = text.isEmpty ? novagramSuperSearchMediaTitle(hit.mediaKind) : text
        let color = text.isEmpty ? theme.colors.grayText : theme.colors.text
        self.snippetLayout = TextViewLayout(NSAttributedString(string: snippet, attributes: [.font: NSFont.normal(.text), .foregroundColor: color]), maximumNumberOfLines: NovagramSuperSearchResultRowItem.snippetLines)
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    var contentWidth: CGFloat {
        return blockWidth - NovagramSuperSearchResultRowItem.padding * 2
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        headerLayout.measure(width: contentWidth - NovagramSuperSearchResultRowItem.avatarSize - 10)
        snippetLayout.measure(width: contentWidth)
        return true
    }

    override var height: CGFloat {
        let padding = NovagramSuperSearchResultRowItem.padding
        let spacing = NovagramSuperSearchResultRowItem.spacing
        return padding + max(NovagramSuperSearchResultRowItem.avatarSize, headerLayout.layoutSize.height) + spacing + snippetLayout.layoutSize.height + padding
    }

    override func viewClass() -> AnyClass {
        return NovagramSuperSearchResultRowView.self
    }
}

private final class NovagramSuperSearchResultRowView: GeneralContainableRowView {
    private let avatar = AvatarControl(font: .avatar(13))
    private let headerView = TextView()
    private let snippetView = TextView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        avatar.setFrameSize(NSSize(width: NovagramSuperSearchResultRowItem.avatarSize, height: NovagramSuperSearchResultRowItem.avatarSize))
        avatar.userInteractionEnabled = false
        for view in [headerView, snippetView] {
            view.userInteractionEnabled = false
            view.isSelectable = false
            containerView.addSubview(view)
        }
        containerView.addSubview(avatar)
        containerView.set(handler: { [weak self] _ in
            (self?.item as? NovagramSuperSearchResultRowItem)?.open()
        }, for: .Click)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? NovagramSuperSearchResultRowItem else {
            return
        }
        avatar.setPeer(account: item.context.account, peer: item.item.peer?._asPeer())
        headerView.update(item.headerLayout)
        snippetView.update(item.snippetLayout)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? NovagramSuperSearchResultRowItem else {
            return
        }
        let padding = NovagramSuperSearchResultRowItem.padding
        let spacing = NovagramSuperSearchResultRowItem.spacing
        avatar.setFrameOrigin(NSPoint(x: padding, y: padding))
        let headerHeight = max(NovagramSuperSearchResultRowItem.avatarSize, item.headerLayout.layoutSize.height)
        headerView.setFrameOrigin(NSPoint(x: avatar.frame.maxX + 10, y: padding + floor((headerHeight - item.headerLayout.layoutSize.height) / 2)))
        snippetView.setFrameOrigin(NSPoint(x: padding, y: padding + headerHeight + spacing))
    }
}
