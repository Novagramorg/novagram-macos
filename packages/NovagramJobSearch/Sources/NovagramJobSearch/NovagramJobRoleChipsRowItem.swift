import Cocoa
import TGUIKit
import TelegramTheme
import GeneralRows

final class NovagramJobRoleChipsRowItem: GeneralRowItem {
    fileprivate static let chipHeight: CGFloat = 30
    fileprivate static let chipPadding: CGFloat = 12
    private static let spacing: CGFloat = 8
    private static let padding: CGFloat = 12

    let roles: [String]
    let select: (String) -> Void
    fileprivate private(set) var frames: [NSRect] = []

    init(_ initialSize: NSSize, stableId: AnyHashable, roles: [String], viewType: GeneralViewType, select: @escaping (String) -> Void) {
        self.roles = roles
        self.select = select
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        let padding = NovagramJobRoleChipsRowItem.padding
        let spacing = NovagramJobRoleChipsRowItem.spacing
        let height = NovagramJobRoleChipsRowItem.chipHeight
        let maxX = blockWidth - padding
        var x = padding
        var y = padding
        var frames: [NSRect] = []
        for role in roles {
            let textWidth = ceil(NSAttributedString(string: role, attributes: [.font: NSFont.normal(.text)]).size().width)
            let chipWidth = min(textWidth + NovagramJobRoleChipsRowItem.chipPadding * 2, maxX - padding)
            if x > padding && x + chipWidth > maxX {
                x = padding
                y += height + spacing
            }
            frames.append(NSRect(x: x, y: y, width: chipWidth, height: height))
            x += chipWidth + spacing
        }
        self.frames = frames
        return true
    }

    override var height: CGFloat {
        return (frames.map { $0.maxY }.max() ?? 0) + NovagramJobRoleChipsRowItem.padding
    }

    override func viewClass() -> AnyClass {
        return NovagramJobRoleChipsRowView.self
    }
}

private final class NovagramJobRoleChipsRowView: GeneralContainableRowView {
    private var buttons: [TextButton] = []

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? NovagramJobRoleChipsRowItem else {
            return
        }
        while buttons.count < item.roles.count {
            let button = TextButton()
            button.scaleOnClick = true
            button.layer?.cornerRadius = NovagramJobRoleChipsRowItem.chipHeight / 2
            button.set(handler: { [weak self] control in
                guard let self, let item = self.item as? NovagramJobRoleChipsRowItem, let index = self.buttons.firstIndex(where: { $0 === control }), index < item.roles.count else {
                    return
                }
                item.select(item.roles[index])
            }, for: .Click)
            containerView.addSubview(button)
            buttons.append(button)
        }
        while buttons.count > item.roles.count {
            buttons.removeLast().removeFromSuperview()
        }
        for (index, button) in buttons.enumerated() {
            button.set(font: .normal(.text), for: .Normal)
            button.set(color: theme.colors.accent, for: .Normal)
            button.set(background: theme.colors.accent.withAlphaComponent(0.12), for: .Normal)
            button.set(background: theme.colors.accent.withAlphaComponent(0.2), for: .Highlight)
            button.set(text: item.roles[index], for: .Normal)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? NovagramJobRoleChipsRowItem else {
            return
        }
        for (index, button) in buttons.enumerated() where index < item.frames.count {
            button.frame = item.frames[index]
        }
    }
}
