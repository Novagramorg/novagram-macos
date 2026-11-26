import Cocoa
import TGUIKit
import TelegramMedia
import TelegramTheme
import Localization

func walletRecipientQueryLooksLikeAddress(_ query: String) -> Bool {
    if query.lowercased().hasPrefix("ton://") {
        return true
    }
    if let separator = query.firstIndex(of: ":"), Int(query[..<separator]) != nil {
        return true
    }
    guard !query.hasPrefix("@"), !query.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains) else {
        return false
    }
    return query.count == 48 || (query.count > 32 && ["EQ", "UQ", "kQ", "0Q", "Ef", "Uf", "kf", "0f"].contains(where: query.hasPrefix))
}

func walletRecipientNoResultsText(query: String) -> String {
    return walletRecipientQueryLooksLikeAddress(query)
        ? strings().walletRecipientNoResultsItemInvalidAddress
        : strings().walletRecipientNoResultsItemNoResultsFor(query)
}

final class WalletRecipientNoResultsItem: TableRowItem {
    let title: TextViewLayout
    let message: TextViewLayout

    init(_ initialSize: NSSize, stableId: AnyHashable, query: String) {
        let title = strings().walletRecipientNoResultsItemTitle
        let message = walletRecipientNoResultsText(query: query)
        self.title = TextViewLayout(.initialize(string: title, color: theme.colors.grayText, font: .medium(17)), alignment: .center)
        self.message = TextViewLayout(.initialize(string: message, color: theme.colors.grayText, font: .normal(15)), alignment: .center)
        super.init(initialSize, stableId: stableId)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool {
        title.measure(width: max(1, width - 88))
        message.measure(width: max(1, width - 88))
        return super.makeSize(width, oldWidth: oldWidth)
    }

    override var height: CGFloat {
        return 96 + 148 + 8 + title.layoutSize.height + 8 + message.layoutSize.height
    }

    override func viewClass() -> AnyClass {
        return WalletRecipientNoResultsView.self
    }

    override var accessibilityLabel: String? {
        return title.attributedString.string
    }

    override var accessibilityValue: String? {
        let text = message.attributedString.string
        return text.isEmpty ? nil : text
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .staticText
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }
}

private final class WalletRecipientNoResultsView: TableRowView {
    private let animationView = LottiePlayerView(frame: NSMakeRect(0, 0, 148, 148))
    private let titleView = TextView()
    private let messageView = TextView()
    private var didStartAnimation = false

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(animationView)
        addSubview(titleView)
        addSubview(messageView)
        for view in [titleView, messageView] {
            view.isSelectable = false
            view.userInteractionEnabled = false
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return theme.colors.listBackground
    }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? WalletRecipientNoResultsItem else { return }
        titleView.update(item.title)
        messageView.update(item.message)
        startAnimationIfNeeded()
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            animationView.set(nil)
            didStartAnimation = false
        } else {
            startAnimationIfNeeded()
        }
    }

    private func startAnimationIfNeeded() {
        if window != nil, !didStartAnimation, let url = Bundle.module.url(forResource: "ChatListNoResults", withExtension: "tgs"), let data = try? Data(contentsOf: url) {
            didStartAnimation = true
            animationView.set(LottieAnimation(compressed: data, key: .init(key: .bundle("WalletChatListNoResults"), size: NSMakeSize(148, 148)), cachePurpose: .none, playPolicy: .onceEnd))
        }
    }

    override func layout() {
        super.layout()
        animationView.centerX(y: 48)
        titleView.centerX(y: animationView.frame.maxY + 8)
        messageView.centerX(y: titleView.frame.maxY + 8)
    }
}
