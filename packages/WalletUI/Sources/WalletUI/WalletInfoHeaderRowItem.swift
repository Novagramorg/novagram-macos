import Cocoa
import TGUIKit
import GeneralRows
import TelegramTheme
import SceneEffects

final class WalletInfoHeaderRowItem: GeneralRowItem {
    fileprivate let diamondSize: NSSize
    fileprivate let titleLayout: TextViewLayout
    fileprivate let textLayout: TextViewLayout

    init(_ initialSize: NSSize, stableId: AnyHashable, diamondSize: NSSize, title: NSAttributedString, text: NSAttributedString) {
        self.diamondSize = diamondSize
        self.titleLayout = TextViewLayout(title, alignment: .center, alwaysStaticItems: true)
        self.textLayout = TextViewLayout(text, alignment: .center, alwaysStaticItems: true)
        super.init(initialSize, stableId: stableId, viewType: .singleItem, inset: NSEdgeInsets(left: 20, right: 20))
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        titleLayout.measure(width: width - inset.left - inset.right)
        textLayout.measure(width: width - inset.left - inset.right)
        return super.makeSize(width, oldWidth: oldWidth)
    }

    override var height: CGFloat {
        return 10 + diamondSize.height + 10 + titleLayout.layoutSize.height + 10 + textLayout.layoutSize.height
    }

    override func viewClass() -> AnyClass {
        return WalletInfoHeaderRowView.self
    }

    override var accessibilityLabel: String? {
        let title = titleLayout.attributedString.string
        return title.isEmpty ? nil : title
    }

    override var accessibilityValue: String? {
        let text = textLayout.attributedString.string
        return text.isEmpty ? nil : text
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .staticText
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }
}

#if arch(arm64)
let walletInfoDiamondHeight: CGFloat = 164

func walletInfoDiamondFrame(rowWidth: CGFloat, logoSize: NSSize) -> NSRect {
    return NSMakeRect(0, 10 + logoSize.height / 2 - walletInfoDiamondHeight / 2, rowWidth, walletInfoDiamondHeight)
}

final class WalletInfoDiamondView: View {
    let diamondLayer = InteractiveDiamondLayer()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.addSublayer(diamondLayer)
        addGestureRecognizer(NSPanGestureRecognizer(target: diamondLayer, action: #selector(InteractiveDiamondLayer.handlePan(_:))))
        addGestureRecognizer(NSClickGestureRecognizer(target: diamondLayer, action: #selector(InteractiveDiamondLayer.handleTap(_:))))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(lightBackground: Bool) {
        diamondLayer.lightBackground = lightBackground
        diamondLayer.setNeedsUpdate()
    }

    override func layout() {
        super.layout()
        diamondLayer.frame = bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        diamondLayer.isInHierarchy = window != nil
    }
}
#endif

private final class WalletInfoHeaderRowView: TableRowView {
    #if arch(arm64)
    private let diamondView = WalletInfoDiamondView(frame: NSZeroRect)
    #else
    private let diamondView = WalletDiamondHeroView(frame: NSZeroRect)
    #endif
    private let titleView = TextView()
    private let textView = TextView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false

        for view in [titleView, textView] {
            view.userInteractionEnabled = false
            view.isSelectable = false
        }

        addSubview(diamondView)
        addSubview(titleView)
        addSubview(textView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? WalletInfoHeaderRowItem else {
            return
        }

        #if arch(arm64)
        diamondView.update(lightBackground: !theme.colors.isDark)
        #else
        diamondView.setFrameSize(item.diamondSize)
        diamondView.isActive = true
        #endif
        titleView.update(item.titleLayout)
        textView.update(item.textLayout)

        needsLayout = true
    }

    override func layout() {
        super.layout()

        guard let item = item as? WalletInfoHeaderRowItem else {
            return
        }

        #if arch(arm64)
        diamondView.frame = walletInfoDiamondFrame(rowWidth: frame.width, logoSize: item.diamondSize)
        #else
        diamondView.centerX(y: 10)
        #endif
        titleView.centerX(y: 10 + item.diamondSize.height + 10)
        textView.centerX(y: titleView.frame.maxY + 10)
    }
}
