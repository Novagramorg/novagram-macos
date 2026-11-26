import Cocoa
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import GeneralRows
import InputDataUI

import TGUIKit

class ChatListFiltersHeaderItem: GeneralRowItem {
    fileprivate let textLayout: TextViewLayout
    fileprivate let context: any AccountContextProtocol
    fileprivate let sticker: SidebarHeaderAnimation
    fileprivate let environment: SidebarUIEnvironment
    init(_ initialSize: NSSize, context: any AccountContextProtocol, environment: SidebarUIEnvironment, stableId: AnyHashable, sticker: SidebarHeaderAnimation, text: NSAttributedString) {
        self.textLayout = TextViewLayout(text, alignment: .center, alwaysStaticItems: true)
        self.context = context
        self.sticker = sticker
        self.environment = environment
        super.init(initialSize, stableId: stableId, inset: NSEdgeInsets(left: 20, right: 20, top: 0, bottom: 10))
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool {
        textLayout.measure(width: width - inset.left - inset.right)
        return super.makeSize(width, oldWidth: oldWidth)
    }

    override func viewClass() -> AnyClass {
        return ChatListFiltersHeaderView.self
    }

    override var height: CGFloat {
        return 112 + textLayout.layoutSize.height + (textLayout.layoutSize.height > 0 ? inset.bottom : 0)
    }

    override var accessibilityLabel: String? {
        let text = textLayout.attributedString.string
        return text.isEmpty ? nil : text
    }

    override var accessibilityIsSpacer: Bool {
        return textLayout.attributedString.string.isEmpty
    }
}


private final class ChatListFiltersHeaderView : TableRowView {
    private var stickerView: SidebarAnimatedHeaderView?
    private let textView = TextView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
    }

    override var backdorColor: NSColor {
        return theme.colors.listBackground
    }

    override func updateColors() {
        super.updateColors()
        textView.backgroundColor = backdorColor
    }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)

        guard let item = item as? ChatListFiltersHeaderItem else { return }

        if stickerView == nil {
            let view = item.environment.makeAnimatedHeader()
            stickerView = view
            addSubview(view)
        }
        stickerView?.update(animation: item.sticker, table: item.table, animated: animated)

        self.textView.update(item.textLayout)

        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? ChatListFiltersHeaderItem else { return }

        self.stickerView?.centerX(y: 0)
        self.textView.centerX(y: (self.stickerView?.frame.maxY ?? 0) + item.inset.bottom)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
