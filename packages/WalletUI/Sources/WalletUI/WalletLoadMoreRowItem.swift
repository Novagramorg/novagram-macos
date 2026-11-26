import Cocoa
import TGUIKit
import GeneralRows
import TelegramTheme
import Localization

enum WalletLoadMoreMode: Equatable {
    case showMore
    case loading
}

final class WalletLoadMoreRowItem: GeneralRowItem {
    fileprivate let mode: WalletLoadMoreMode
    fileprivate let titleLayout: TextViewLayout

    init(_ initialSize: NSSize, stableId: AnyHashable, mode: WalletLoadMoreMode, viewType: GeneralViewType, action: @escaping () -> Void) {
        self.mode = mode
        self.titleLayout = TextViewLayout(.initialize(string: strings().walletLoadMoreRowItemShowMore, color: walletClassicAccent, font: .normal(.title)), maximumNumberOfLines: 1)
        self.titleLayout.measure(width: .greatestFiniteMagnitude)
        super.init(initialSize, height: 40, stableId: stableId, viewType: viewType, action: action)
    }

    override func viewClass() -> AnyClass {
        return WalletLoadMoreRowView.self
    }

    override var accessibilityLabel: String? {
        switch mode {
        case .showMore:
            return titleLayout.attributedString.string
        case .loading:
            return strings().voiceOverCommonLoading
        }
    }

    override var accessibilityRole: NSAccessibility.Role? {
        switch mode {
        case .showMore:
            return .button
        case .loading:
            return .busyIndicator
        }
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    override func accessibilityPerformPress() -> Bool {
        guard mode == .showMore else {
            return false
        }
        action()
        return true
    }
}

private final class WalletLoadMoreRowView: GeneralContainableRowView {
    private let titleView = TextView()
    private let progress = ProgressIndicator(frame: NSMakeRect(0, 0, 20, 20))

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        titleView.isEventLess = true
        progress.isEventLess = true
        addSubview(titleView)
        addSubview(progress)
        containerView.set(handler: { [weak self] _ in
            guard let item = self?.item as? WalletLoadMoreRowItem, item.mode == .showMore else {
                return
            }
            item.action()
        }, for: .Click)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        progress.animates = window != nil && (item as? WalletLoadMoreRowItem)?.mode == .loading
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? WalletLoadMoreRowItem else {
            return
        }
        titleView.update(item.titleLayout)
        titleView.isHidden = item.mode != .showMore
        progress.isHidden = item.mode != .loading
        progress.animates = item.mode == .loading && window != nil
        borderView.isHidden = !item.hasBorder
        needsLayout = true
    }

    override func layout() {
        super.layout()
        titleView.center()
        progress.center()
    }
}
