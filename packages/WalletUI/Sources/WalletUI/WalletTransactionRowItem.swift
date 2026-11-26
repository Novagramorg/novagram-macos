import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import InputDataUI
import Localization
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import WalletContext

func walletTransactionDateText(_ timestamp: Int32, environment: WalletUIEnvironment) -> String {
    var t: time_t = Int(timestamp)
    var timeinfo = tm()
    localtime_r(&t, &timeinfo)

    let day = "\(timeinfo.tm_mday)"
    let time = environment.shortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min))

    switch timeinfo.tm_mon + 1 {
    case 1:
        return strings().timePreciseMediumDateM1(day, time)
    case 2:
        return strings().timePreciseMediumDateM2(day, time)
    case 3:
        return strings().timePreciseMediumDateM3(day, time)
    case 4:
        return strings().timePreciseMediumDateM4(day, time)
    case 5:
        return strings().timePreciseMediumDateM5(day, time)
    case 6:
        return strings().timePreciseMediumDateM6(day, time)
    case 7:
        return strings().timePreciseMediumDateM7(day, time)
    case 8:
        return strings().timePreciseMediumDateM8(day, time)
    case 9:
        return strings().timePreciseMediumDateM9(day, time)
    case 10:
        return strings().timePreciseMediumDateM10(day, time)
    case 11:
        return strings().timePreciseMediumDateM11(day, time)
    case 12:
        return strings().timePreciseMediumDateM12(day, time)
    default:
        return time
    }
}

private let walletTransactionAvatarSize = NSMakeSize(40, 40)
private let walletTransactionPendingBadgeSize = NSMakeSize(14, 14)
private let walletTransactionPendingIndicatorSize = NSMakeSize(9, 9)
private let walletTransactionCollectibleImageSize = NSMakeSize(40, 40)
private let walletTransactionCollectibleChipHeight: CGFloat = 44

@available(macOS 10.15, *)
private func walletTransactionCollectibleKindText(_ kind: WalletContext.Transaction.CollectibleTransfer.Kind) -> String {
    switch kind {
    case .gift:
        return strings().walletTransactionRowItemCollectibleGift
    case .username:
        return strings().walletTransactionRowItemUsername
    case .anonymousNumber:
        return strings().walletTransactionRowItemAnonymousNumber
    case .other:
        return strings().walletTransactionRowItemCollectible
    }
}

private func walletTransactionPendingBadgeFrame() -> NSRect {
    let circlePoint = NSMakePoint(
        walletTransactionAvatarSize.width / 2.0 + cos(CGFloat.pi / 4.0) * walletTransactionAvatarSize.width / 2.0 + 1.0,
        walletTransactionAvatarSize.height / 2.0 - sin(CGFloat.pi / 4.0) * walletTransactionAvatarSize.height / 2.0 - 1.0
    )
    return NSMakeRect(
        circlePoint.x - walletTransactionPendingBadgeSize.width / 2.0,
        circlePoint.y - walletTransactionPendingBadgeSize.height / 2.0,
        walletTransactionPendingBadgeSize.width,
        walletTransactionPendingBadgeSize.height
    )
}

private func walletTransactionPendingMaskPath(flipped: Bool) -> CGPath {
    let bounds = NSMakeRect(0, 0, walletTransactionAvatarSize.width, walletTransactionAvatarSize.height)
    var cutout = walletTransactionPendingBadgeFrame().insetBy(dx: -2.0, dy: -2.0)
    if !flipped {
        cutout.origin.y = bounds.height - cutout.maxY
    }
    let path = CGMutablePath()
    path.addRect(bounds)
    path.addEllipse(in: cutout)
    return path
}

@available(macOS 10.15, *)
private func walletTransactionKeyChangeImage() -> CGImage? {
    var symbol: CGImage? = nil
    if let url = Bundle.module.url(forResource: "WalletTransactionKey", withExtension: "pdf"), let image = NSImage(contentsOf: url) {
        symbol = image.precomposed(.white)
    } else if #available(macOS 11.0, *) {
        symbol = NSImage(systemSymbolName: "key.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold))?
            .precomposed(.white)
    }
    return walletTransactionServiceImage(symbol: symbol, symbolSize: symbol?.backingSize)
}

private func walletTransactionOnrampImage(providerName: String) -> CGImage? {
    let imageName: String
    switch providerName {
    case "MoonPay":
        imageName = "Wallet_TransactionCard"
    case "Walt":
        imageName = "Wallet_TransactionWalt"
    default:
        return nil
    }
    guard let symbol = NSImage(named: imageName)?.precomposed(.white) else {
        return nil
    }
    return walletTransactionServiceImage(symbol: symbol, symbolSize: symbol.backingSize)
}

private func walletTransactionServiceImage(symbol: CGImage?, symbolSize: NSSize?) -> CGImage? {
    let size = NSMakeSize(40, 40)
    return generateImage(size, contextGenerator: { size, ctx in
        ctx.clear(NSMakeRect(0, 0, size.width, size.height))
        ctx.saveGState()
        ctx.addEllipse(in: NSMakeRect(0, 0, size.width, size.height))
        ctx.clip()
        let gradientColors = [NSColor(rgb: 0x2a9ef1).cgColor, NSColor(rgb: 0x72d5fd).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: gradientColors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(gradient, start: NSMakePoint(0, 0), end: NSMakePoint(0, size.height), options: [])
        }
        ctx.restoreGState()
        if let symbol, let symbolSize {
            let rect = NSMakeRect((size.width - symbolSize.width) / 2, (size.height - symbolSize.height) / 2, symbolSize.width, symbolSize.height)
            ctx.draw(symbol, in: rect)
        }
    })
}

@available(macOS 10.15, *)
func walletTransactionAvatarImage(direction: WalletContext.Transaction.Direction) -> CGImage? {
    guard direction != .unknown else {
        return nil
    }

    let size = NSMakeSize(40, 40)
    let arrow = NSImage(named: "Wallet_TransactionArrow")?.precomposed(
        flipVertical: direction == .incoming,
        flipHorizontal: direction == .incoming
    )
    return generateImage(size, contextGenerator: { size, ctx in
        ctx.clear(NSMakeRect(0, 0, size.width, size.height))
        ctx.saveGState()
        ctx.addEllipse(in: NSMakeRect(0, 0, size.width, size.height))
        ctx.clip()
        let gradientColors: CFArray
        switch direction {
        case .incoming:
            gradientColors = [NSColor(rgb: 0x32b83b).cgColor, NSColor(rgb: 0x87d93b).cgColor] as CFArray
        case .outgoing, .unknown:
            gradientColors = [NSColor(rgb: 0x2a9ef1).cgColor, NSColor(rgb: 0x72d5fd).cgColor] as CFArray
        }
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: gradientColors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(gradient, start: NSMakePoint(0, 0), end: NSMakePoint(0, size.height), options: [])
        } else {
            ctx.setFillColor(walletClassicAccent.cgColor)
            ctx.fill(NSMakeRect(0, 0, size.width, size.height))
        }

        if let arrow {
            let arrowSize = NSMakeSize(28, 28)
            ctx.draw(arrow, in: NSMakeRect(
                floor((size.width - arrowSize.width) / 2.0),
                floor((size.height - arrowSize.height) / 2.0),
                arrowSize.width,
                arrowSize.height
            ))
        }

        ctx.restoreGState()
    })
}

private func walletTransactionPendingGramIcon() -> CGImage? {
    guard let icon = NSImage(named: "Wallet_TransactionGram")?.precomposed(theme.colors.grayText), let highlight = NSImage(named: "Wallet_TransactionGramHighlight")?.precomposed() else {
        return nil
    }
    let size = NSMakeSize(18, 18)
    return generateImage(size, contextGenerator: { size, ctx in
        ctx.clear(size.bounds)
        ctx.draw(icon, in: size.bounds)
        ctx.draw(highlight, in: size.bounds)
    })
}

private func formatWalletTokenAmountText(_ value: Int64, decimalDigits: Int, showPlus: Bool, maxDecimalPositions: Int) -> String {
    let decimalSeparator = Locale.current.decimalSeparator ?? "."
    var digits = String(value.magnitude)
    while digits.count <= decimalDigits {
        digits.insert("0", at: digits.startIndex)
    }

    let fractionStart = digits.index(digits.endIndex, offsetBy: -decimalDigits)
    let integralPart = String(digits[..<fractionStart])
    var fractionalPart = String(digits[fractionStart...])
    while fractionalPart.last == "0" {
        fractionalPart.removeLast()
    }
    if fractionalPart.count > maxDecimalPositions {
        fractionalPart = String(fractionalPart.prefix(maxDecimalPositions))
    }

    var result = integralPart
    if !fractionalPart.isEmpty {
        result.append(decimalSeparator)
        result.append(fractionalPart)
    }
    if value < 0 {
        result.insert("-", at: result.startIndex)
    } else if showPlus {
        result.insert("+", at: result.startIndex)
    }
    return result
}

let walletTransactionAddressTitleScale: CGFloat = 14.0 / 17.0
let walletTransactionAddressTitleContentSize = NSMakeSize(152, 22)

func walletTransactionAddressTitle(address: String, domain: String?) -> (title: String, chipAddress: String?) {
    if let domain {
        return (domain, nil)
    }
    var address = address
    if #available(macOS 10.15, *) {
        address = WalletContext.transferAddress(from: address, preserveBounce: true) ?? address
    }
    guard !address.isEmpty else {
        return (strings().walletTransactionRowItemUnknownAddress, nil)
    }
    let title = address.count > 8 ? "\(address.prefix(4))…\(address.suffix(4))" : address
    return (title, address.count > 12 ? address : nil)
}

func walletTransactionAddressTitleChipFrame(index: Int, scale: CGFloat) -> NSRect {
    return NSMakeRect(CGFloat(index) * 52 * scale, 0, 48 * scale, 22 * scale)
}

func walletTransactionAddressTitleGroups(_ address: String) -> [String] {
    return [
        String(address.prefix(4)),
        String(address.dropFirst(4).prefix(2)) + String(address.suffix(6).prefix(2)),
        String(address.suffix(4))
    ]
}

@available(macOS 10.15, *)
final class WalletTransactionRowItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    let environment: WalletUIEnvironment
    fileprivate let transaction: WalletContext.Transaction
    fileprivate let callback: (WalletContext.Transaction, (() -> NSView?)?) -> Void

    fileprivate let titleLayout: TextViewLayout
    fileprivate let subtitleLayout: TextViewLayout
    fileprivate let dateLayout: TextViewLayout
    fileprivate let sendingLayout: TextViewLayout
    fileprivate let amountLayout: TextViewLayout
    fileprivate let avatarImage: CGImage?
    fileprivate let peerId: PeerId?
    fileprivate let amountIcon: CGImage?
    fileprivate let isPending: Bool
    fileprivate let isFailed: Bool
    fileprivate let collectibleTitleLayout: TextViewLayout?
    fileprivate let collectibleSubtitleLayout: TextViewLayout?
    fileprivate let collectibleImage: TelegramMediaWebFile?
    fileprivate var collectibleContentWidth: CGFloat = 0
    fileprivate let titleAddress: String?
    fileprivate var addressTitleLayouts: [TextViewLayout] = []
    fileprivate var addressTitleScale: CGFloat = walletTransactionAddressTitleScale
    let transferAnimation: WalletPendingTransferAnimation?

    @available(macOS 10.15, *)
    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, environment: WalletUIEnvironment, transaction: WalletContext.Transaction, walletAddress: String? = nil, transferAnimation: WalletPendingTransferAnimation? = nil, viewType: GeneralViewType, callback: @escaping (WalletContext.Transaction, (() -> NSView?)?) -> Void) {
        self.context = context
        self.environment = environment
        self.transaction = transaction
        self.callback = callback
        self.transferAnimation = transferAnimation
        self.isPending = transaction.status == .pending && transaction.kind != .keyChange && transferAnimation == nil
        self.isFailed = transaction.status == .failed
        let displayedDirection: WalletContext.Transaction.Direction = transaction.isSelfTransfer(walletAddress: walletAddress) ? .incoming : transaction.direction

        let titleText: String
        var titleAddress: String? = nil
        var peerId: PeerId? = nil
        switch transaction.peer {
        case let .user(peer, _, _):
            let displayName = environment.peerTitle(peer._asPeer(), compact: false)
            titleText = displayName.isEmpty ? strings().walletTransactionRowItemTelegramUser : displayName
            peerId = peer.id
        case let .channel(peer, _, _):
            titleText = environment.peerTitle(peer._asPeer(), compact: false)
            peerId = peer.id
        case let .address(address, _):
            let addressTitle = walletTransactionAddressTitle(address: address, domain: transaction.peer.domain)
            titleText = addressTitle.title
            titleAddress = addressTitle.chipAddress
        case let .onramp(_, _, providerName):
            titleText = providerName == "MoonPay" ? strings().walletTransactionRowItemCardTopUp : strings().walletTransactionRowItemCryptoTopUp
        case .telegramGift:
            titleText = strings().walletTransactionRowItemTelegram
        case .unsupported:
            titleText = strings().walletTransactionRowItemUnknownAddress
        }
        self.titleLayout = TextViewLayout(.initialize(string: titleText, color: theme.colors.text, font: .medium(.title)), maximumNumberOfLines: 1)
        self.titleAddress = titleAddress

        var subtitleText: String
        var amountPrefix: String
        var amountColor: NSColor
        switch displayedDirection {
        case .incoming:
            if transaction.collectible != nil {
                subtitleText = strings().walletTransactionRowItemIncomingCollectible
            } else if case .user = transaction.peer {
                subtitleText = strings().walletTransactionRowItemIncomingTransfer
            } else {
                subtitleText = strings().walletTransactionRowItemDeposit
            }
            amountPrefix = "+"
            switch transaction.currency {
            case .ton:
                amountColor = theme.colors.greenUI
            case .usdt:
                amountColor = NSColor(rgb: 0x0B9696)
            }
        case .outgoing:
            if transaction.collectible != nil {
                subtitleText = strings().walletTransactionRowItemOutgoingCollectible
            } else if case .user = transaction.peer {
                subtitleText = strings().walletTransactionRowItemOutgoingTransfer
            } else {
                subtitleText = strings().walletTransactionRowItemWithdrawal
            }
            amountPrefix = "–"
            amountColor = theme.colors.text
        case .unknown:
            subtitleText = ""
            amountPrefix = ""
            amountColor = theme.colors.text
        }
        if case let .onramp(_, _, providerName) = transaction.peer {
            subtitleText = providerName
        }
        if case .telegramGift(true) = transaction.peer {
            switch displayedDirection {
            case .incoming: subtitleText = strings().walletTransactionRowItemMovedFromProfile
            case .outgoing: subtitleText = strings().walletTransactionRowItemMovedToProfile
            case .unknown: break
            }
        }
        if transaction.kind == .keyChange {
            subtitleText = strings().walletTransactionRowItemKeyUpdate
            amountPrefix = "–"
            amountColor = theme.colors.text
        }
        if self.isPending {
            amountColor = theme.colors.grayText
        }
        if self.isFailed {
            amountColor = theme.colors.redUI
        }
        let subtitleColor: NSColor = self.isFailed ? theme.colors.redUI : theme.colors.text
        let displayedSubtitleText = self.isFailed ? strings().walletTransactionRowItemFailed : subtitleText
        self.subtitleLayout = TextViewLayout(.initialize(string: displayedSubtitleText, color: subtitleColor, font: .normal(.text)), maximumNumberOfLines: 1)

        let dateText = walletTransactionDateText(transaction.timestamp, environment: environment)
        self.dateLayout = TextViewLayout(.initialize(string: dateText, color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1)
        self.sendingLayout = TextViewLayout(.initialize(string: strings().walletTransactionRowItemSending, color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1)

        let amountText: String
        if transaction.collectible != nil {
            amountText = displayedDirection == .incoming ? strings().walletTransactionRowItemIncomingItem : strings().walletTransactionRowItemOutgoingItem
            amountColor = displayedDirection == .incoming ? amountColor : theme.colors.grayText
            self.amountIcon = NSImage(named: "Wallet_TransactionCollectible")?.precomposed(amountColor)
        } else {
            let isKeyChange = transaction.kind == .keyChange
            let absoluteAmount = isKeyChange ? abs(transaction.amount) + transaction.fee : abs(transaction.amount)
            switch transaction.currency {
            case .ton:
                amountText = amountPrefix + formatTonAmountText(absoluteAmount, maxDecimalPositions: isKeyChange ? 5 : 3)
                self.amountIcon = self.isPending ? walletTransactionPendingGramIcon() : NSImage(named: "Wallet_TransactionGram")?.precomposed(self.isFailed ? theme.colors.redUI : nil)
            case .usdt:
                amountText = amountPrefix + formatWalletTokenAmountText(absoluteAmount, decimalDigits: 6, showPlus: false, maxDecimalPositions: 2)
                self.amountIcon = NSImage(named: "Wallet_TransactionUsdt")?.precomposed(self.isPending ? theme.colors.grayText : self.isFailed ? theme.colors.redUI : nil)
            }
        }
        self.amountLayout = TextViewLayout(tonAmountAttributedString(amountText, integralFont: .semibold(15), fractionalFont: .semibold(12), color: amountColor), maximumNumberOfLines: 1)

        if let collectible = transaction.collectible {
            let collectibleName = collectible.name.isEmpty ? walletTransactionCollectibleKindText(collectible.kind) : collectible.name
            self.collectibleTitleLayout = TextViewLayout(.initialize(string: collectibleName, color: theme.colors.text, font: .semibold(14)), maximumNumberOfLines: 1)
            self.collectibleSubtitleLayout = TextViewLayout(.initialize(string: walletTransactionCollectibleKindText(collectible.kind), color: theme.colors.grayText, font: .normal(13)), maximumNumberOfLines: 1)
            self.collectibleImage = walletCollectibleWebFile(collectible.thumbnail ?? collectible.image)
        } else {
            self.collectibleTitleLayout = nil
            self.collectibleSubtitleLayout = nil
            self.collectibleImage = nil
        }

        if transaction.kind == .keyChange {
            self.peerId = nil
            self.avatarImage = walletTransactionKeyChangeImage()
        } else if case let .onramp(_, _, providerName) = transaction.peer, let onrampImage = walletTransactionOnrampImage(providerName: providerName) {
            self.peerId = nil
            self.avatarImage = onrampImage
        } else {
            self.peerId = peerId
            self.avatarImage = walletTransactionAvatarImage(direction: displayedDirection)
        }

        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    override var height: CGFloat {
        if transaction.collectible != nil {
            return 132
        }
        let height = 7 + titleLayout.layoutSize.height + 2 + subtitleLayout.layoutSize.height + 3 + dateLayout.layoutSize.height + 7
        return max(58, height)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)

        amountLayout.measure(width: .greatestFiniteMagnitude)

        let leftInset = viewType.innerInset.left
        let rightInset = viewType.innerInset.right
        let amountIconSpacing: CGFloat = transaction.collectible == nil ? 3 : 1
        let amountZone = amountLayout.layoutSize.width + amountIconSpacing + 18
        let textWidth = blockWidth - leftInset - 40 - 10 - rightInset

        let titleWidth = max(0, textWidth - amountZone - 12)
        titleLayout.measure(width: titleWidth)
        if let titleAddress {
            addressTitleScale = min(walletTransactionAddressTitleScale, titleWidth / walletTransactionAddressTitleContentSize.width)
            let font = NSFont.monospacedSystemFont(ofSize: 16 * addressTitleScale, weight: .semibold)
            addressTitleLayouts = walletTransactionAddressTitleGroups(titleAddress).map { group in
                let layout = TextViewLayout(.initialize(string: group, color: theme.colors.text, font: font), maximumNumberOfLines: 1)
                layout.measure(width: .greatestFiniteMagnitude)
                return layout
            }
        }
        subtitleLayout.measure(width: textWidth)
        dateLayout.measure(width: textWidth)
        sendingLayout.measure(width: textWidth)
        if let collectibleTitleLayout, let collectibleSubtitleLayout {
            let collectibleTextWidth = max(0, textWidth - 50 - 8)
            collectibleTitleLayout.measure(width: collectibleTextWidth)
            collectibleSubtitleLayout.measure(width: collectibleTextWidth)
            collectibleContentWidth = min(max(0, textWidth), 50 + max(collectibleTitleLayout.layoutSize.width, collectibleSubtitleLayout.layoutSize.width) + 10)
        } else {
            collectibleContentWidth = 0
        }

        return true
    }

    override func viewClass() -> AnyClass {
        return WalletTransactionRowView.self
    }

    override var accessibilityLabel: String? {
        let title = titleLayout.attributedString.string
        return title.isEmpty ? nil : title
    }

    override var accessibilityValue: String? {
        var amount = amountLayout.attributedString.string
        if transaction.collectible == nil {
            switch transaction.currency {
            case .ton:
                amount = walletTonAccessibilityText(amount)
            case .usdt:
                amount += " " + strings().walletTransactionAmountRowItemUsdt
            }
        }
        let status = isPending ? sendingLayout.attributedString.string : dateLayout.attributedString.string
        let parts = [subtitleLayout.attributedString.string, amount, collectibleTitleLayout?.attributedString.string, status].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    override func accessibilityPerformPress() -> Bool {
        callback(transaction, nil)
        return true
    }
}

@available(macOS 10.15, *)
final class WalletTransactionRowView: GeneralContainableRowView {
    private let avatarView = ImageView(frame: NSMakeRect(0, 0, 40, 40))
    private let titleView = TextView()
    private let subtitleView = TextView()
    private let dateView = TextView()
    private let amountView = TextView()
    private let amountIconView = ImageView(frame: NSMakeRect(0, 0, 18, 18))
    private let collectibleBackgroundView = View()
    private let collectibleImagePlaceholderView = View(frame: NSMakeRect(0, 0, 40, 40))
    private let collectibleImageView = TransformImageView(frame: NSMakeRect(0, 0, 40, 40))
    private let collectibleTitleView = TextView()
    private let collectibleSubtitleView = TextView()
    private let collectibleImageFetchDisposable = MetaDisposable()
    private let peerDisposable = MetaDisposable()
    private var peerAvatarView: WalletUIAvatarView?
    private var addressTitleView: WalletTransactionAddressTitleView?
    private var pendingBadgeView: View?
    private var pendingIndicatorView: InfiniteProgressView?
    private var amountIconState: (id: AnyHashable, isPending: Bool)?
    private var transferAnimation: WalletPendingTransferAnimation?
    private var transferPresentation: (expansion: CGFloat, iconAlpha: CGFloat, iconScale: CGFloat, clockAlpha: CGFloat, time: Double)?
    private var pendingClockView: View?
    private var pendingStatusView: TextView?
    private let clockMinuteLayer = CALayer()
    private let clockHourLayer = CALayer()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        amountIconView.contentGravity = .resizeAspect
        amountIconView.isAccessibilityDecorative = true
        avatarView.isAccessibilityDecorative = true
        collectibleBackgroundView.layer?.cornerRadius = 10
        collectibleImagePlaceholderView.layer?.cornerRadius = 8

        for textView in [titleView, subtitleView, dateView, amountView, collectibleTitleView, collectibleSubtitleView] {
            textView.userInteractionEnabled = false
            textView.isSelectable = false
        }
        collectibleBackgroundView.userInteractionEnabled = false
        collectibleImagePlaceholderView.userInteractionEnabled = false

        addSubview(avatarView)
        addSubview(titleView)
        addSubview(subtitleView)
        addSubview(dateView)
        addSubview(amountView)
        addSubview(amountIconView)
        addSubview(collectibleBackgroundView)
        addSubview(collectibleImagePlaceholderView)
        addSubview(collectibleImageView)
        addSubview(collectibleTitleView)
        addSubview(collectibleSubtitleView)

        containerView.set(handler: { [weak self] _ in
            self?.updateColors()
        }, for: .Highlight)
        containerView.set(handler: { [weak self] _ in
            self?.updateColors()
        }, for: .Normal)
        containerView.set(handler: { [weak self] _ in
            self?.updateColors()
        }, for: .Hover)

        containerView.set(handler: { [weak self] _ in
            guard let item = self?.item as? WalletTransactionRowItem else {
                return
            }
            item.callback(item.transaction, { [weak self] in self?.containerView })
        }, for: .Click)
    }

    deinit {
        collectibleImageFetchDisposable.dispose()
        peerDisposable.dispose()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateColors() {
        super.updateColors()
        collectibleBackgroundView.backgroundColor = theme.colors.grayText.withAlphaComponent(0.08)
        collectibleImagePlaceholderView.backgroundColor = theme.colors.grayForeground
        if let item = item as? GeneralRowItem {
            self.background = item.viewType.rowBackground
            let lifted = (item as? WalletTransactionRowItem)?.transferAnimation != nil
            let highlighted = isSelect ? self.backdorColor : theme.colors.grayHighlight
            containerView.set(background: lifted ? .clear : self.backdorColor, for: .Normal)
            containerView.set(background: lifted ? .clear : highlighted, for: .Highlight)
        }
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? WalletTransactionRowItem else {
            return
        }

        if let current = transferAnimation, current !== item.transferAnimation {
            current.unbind(row: self)
        }
        transferAnimation = item.transferAnimation
        if item.transferAnimation == nil {
            resetTransferPresentation()
        }

        avatarView.image = item.avatarImage
        avatarView.isHidden = item.avatarImage == nil || item.peerId != nil

        if let peerId = item.peerId {
            let avatar: WalletUIAvatarView
            if let current = peerAvatarView {
                avatar = current
            } else {
                avatar = item.environment.makeAvatar(font: .avatar(15))
                avatar.userInteractionEnabled = false
                avatar.setFrameSize(walletTransactionAvatarSize)
                addSubview(avatar)
                peerAvatarView = avatar
            }
            let account = item.context.account
            peerDisposable.set((walletUIPeerView(peerId: peerId, postbox: account.postbox)
            |> deliverOnMainQueue).start(next: { [weak avatar] peer in
                avatar?.update(peer: peer)
            }))
        } else {
            peerDisposable.set(nil)
            peerAvatarView?.removeFromSuperview()
            peerAvatarView = nil
        }

        var avatarVisuals: [NSView] = [avatarView]
        if let peerAvatarView {
            avatarVisuals.append(peerAvatarView)
        }
        for view in avatarVisuals {
            if item.isPending {
                let maskLayer = CAShapeLayer()
                maskLayer.frame = NSMakeRect(0, 0, walletTransactionAvatarSize.width, walletTransactionAvatarSize.height)
                maskLayer.fillRule = .evenOdd
                maskLayer.path = walletTransactionPendingMaskPath(flipped: view.isFlipped)
                view.layer?.mask = maskLayer
            } else {
                view.layer?.mask = nil
            }
        }

        titleView.update(item.titleLayout)
        titleView.isHidden = item.titleAddress != nil
        if item.titleAddress != nil {
            let current: WalletTransactionAddressTitleView
            if let addressTitleView {
                current = addressTitleView
            } else {
                current = WalletTransactionAddressTitleView(frame: .zero)
                addSubview(current)
                addressTitleView = current
            }
            current.update(layouts: item.addressTitleLayouts, scale: item.addressTitleScale)
        } else {
            addressTitleView?.removeFromSuperview()
            addressTitleView = nil
        }
        subtitleView.update(item.subtitleLayout)
        dateView.update(item.dateLayout)
        amountView.update(item.amountLayout)
        amountIconView.image = item.amountIcon
        amountIconView.isHidden = item.amountIcon == nil
        if animated, let amountIconState, amountIconState.id == item.stableId, amountIconState.isPending != item.isPending {
            amountIconView.layer?.animateContents()
        }
        amountIconState = (item.stableId, item.isPending)

        let hasCollectible = item.transaction.collectible != nil
        collectibleBackgroundView.isHidden = !hasCollectible
        collectibleImagePlaceholderView.isHidden = !hasCollectible
        collectibleTitleView.isHidden = !hasCollectible
        collectibleSubtitleView.isHidden = !hasCollectible
        if let collectibleTitleLayout = item.collectibleTitleLayout, let collectibleSubtitleLayout = item.collectibleSubtitleLayout {
            collectibleTitleView.update(collectibleTitleLayout)
            collectibleSubtitleView.update(collectibleSubtitleLayout)
        }

        collectibleImageView.clear()
        collectibleImageFetchDisposable.set(nil)
        if hasCollectible, let image = item.collectibleImage {
            collectibleImageView.isHidden = false
            collectibleImageView.setSignal(item.environment.webFilePhoto( photo: image, scale: backingScaleFactor, useActualDimensions: true), clearInstantly: true)
            collectibleImageFetchDisposable.set(fetchedMediaResource(mediaBox: item.context.account.postbox.mediaBox, userLocation: .other, userContentType: .other, reference: MediaResourceReference.standalone(resource: image.resource)).start())
            collectibleImageView.set(arguments: TransformImageArguments(corners: ImageCorners(radius: 8), imageSize: walletTransactionCollectibleImageSize, boundingSize: walletTransactionCollectibleImageSize, intrinsicInsets: NSEdgeInsetsZero))
        } else {
            collectibleImageView.isHidden = true
        }

        if item.isPending, item.avatarImage != nil || item.peerId != nil {
            let badgeView: View
            let indicatorView: InfiniteProgressView
            if let currentBadge = pendingBadgeView, let currentIndicator = pendingIndicatorView {
                badgeView = currentBadge
                indicatorView = currentIndicator
            } else {
                badgeView = View(frame: NSMakeRect(0, 0, walletTransactionPendingBadgeSize.width, walletTransactionPendingBadgeSize.height))
                badgeView.userInteractionEnabled = false
                badgeView.layer?.cornerRadius = walletTransactionPendingBadgeSize.height / 2.0
                indicatorView = InfiniteProgressView(color: .white, lineWidth: 1.5)
                indicatorView.userInteractionEnabled = false
                indicatorView.setFrameSize(walletTransactionPendingIndicatorSize)
                indicatorView.progress = nil
                badgeView.addSubview(indicatorView)
                indicatorView.setFrameOrigin(NSMakePoint(
                    (walletTransactionPendingBadgeSize.width - walletTransactionPendingIndicatorSize.width) / 2.0,
                    (walletTransactionPendingBadgeSize.height - walletTransactionPendingIndicatorSize.height) / 2.0
                ))
                addSubview(badgeView)
                pendingBadgeView = badgeView
                pendingIndicatorView = indicatorView
            }
            badgeView.backgroundColor = theme.colors.grayText
            badgeView.isHidden = false
        } else {
            pendingBadgeView?.removeFromSuperview()
            pendingBadgeView = nil
            pendingIndicatorView = nil
        }
        pendingStatusView?.update(item.sendingLayout)

        needsLayout = true
        item.transferAnimation?.bind(row: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        transferAnimation?.updateLink()
    }

    var transferIconFrame: NSRect {
        return amountIconView.frame
    }

    var transferAmountFrame: NSRect {
        let frame = amountView.frame
        guard let presentation = transferPresentation, let item = item as? WalletTransactionRowItem else { return frame }
        let transform = walletPendingTransferAmountTransform(expansion: presentation.expansion, width: frame.width, verticalOffset: containerView.bounds.midY - frame.midY, isCollectible: item.transaction.collectible != nil)
        let size = NSMakeSize(frame.width * transform.scale, frame.height * transform.scale)
        return NSMakeRect(frame.midX - size.width / 2 + transform.translation.x, frame.midY - size.height / 2 + transform.translation.y, size.width, size.height)
    }

    var transferRightInset: CGFloat {
        return (item as? WalletTransactionRowItem)?.viewType.innerInset.right ?? 0.0
    }

    func applyTransferPresentation(expansion: CGFloat, iconAlpha: CGFloat, iconScale: CGFloat, clockAlpha: CGFloat, time: Double) {
        transferPresentation = (expansion, iconAlpha, iconScale, clockAlpha, time)
        guard let item = item as? WalletTransactionRowItem, item.transferAnimation != nil else {
            return
        }
        if let layer = amountView.layer {
            let transform = walletPendingTransferAmountTransform(expansion: expansion, width: amountView.frame.width, verticalOffset: containerView.bounds.midY - amountView.frame.midY, isCollectible: item.transaction.collectible != nil)
            layer.transform = walletAmountCenteredTransform(CATransform3DConcat(CATransform3DMakeScale(transform.scale, transform.scale, 1.0), CATransform3DMakeTranslation(transform.translation.x, transform.translation.y, 0.0)), layer: layer)
        }
        amountIconView.alphaValue = iconAlpha
        if let layer = amountIconView.layer {
            let scale = max(0.001, iconScale)
            layer.transform = walletAmountCenteredTransform(CATransform3DMakeScale(scale, scale, 1.0), layer: layer)
        }
        if clockAlpha > 0.0 && pendingClockView == nil {
            let clock = View(frame: NSMakeRect(0, 0, 17, 17))
            clock.userInteractionEnabled = false
            clock.layer?.cornerRadius = 8.5
            let ring = CAShapeLayer()
            ring.path = CGPath(ellipseIn: NSMakeRect(2.9, 2.9, 11.2, 11.2), transform: nil)
            ring.fillColor = nil
            ring.strokeColor = walletPendingTransferTint.cgColor
            ring.lineWidth = 1.3
            clock.layer?.addSublayer(ring)
            for (hand, length) in [(clockMinuteLayer, 5.6 * 0.62), (clockHourLayer, 5.6 * 0.42)] {
                hand.backgroundColor = walletPendingTransferTint.cgColor
                hand.bounds = NSMakeRect(0, 0, length + 1.3, 1.3)
                hand.anchorPoint = NSMakePoint(0.65 / (length + 1.3), 0.5)
                hand.position = NSMakePoint(8.5, 8.5)
                hand.cornerRadius = 0.65
                clock.layer?.addSublayer(hand)
            }
            addSubview(clock)
            pendingClockView = clock
            let status = TextView()
            status.userInteractionEnabled = false
            status.isSelectable = false
            status.update(item.sendingLayout)
            addSubview(status)
            pendingStatusView = status
        }
        pendingStatusView?.setFrameOrigin(dateView.frame.origin)
        pendingStatusView?.alphaValue = clockAlpha
        dateView.alphaValue = 1.0 - clockAlpha
        if let clock = pendingClockView {
            let avatarFrame = avatarView.frame
            clock.backgroundColor = backdorColor
            clock.setFrameOrigin(NSMakePoint(avatarFrame.maxX - 5.5 - clock.frame.width / 2.0, avatarFrame.maxY - 5.5 - clock.frame.height / 2.0))
            clock.alphaValue = clockAlpha
        }
        let hands = walletPendingTransferClockHandAngles(time: time)
        clockMinuteLayer.setAffineTransform(CGAffineTransform(rotationAngle: hands.minute))
        clockHourLayer.setAffineTransform(CGAffineTransform(rotationAngle: hands.hour))
    }

    func resetTransferPresentation() {
        transferPresentation = nil
        amountView.layer?.transform = CATransform3DIdentity
        amountIconView.layer?.transform = CATransform3DIdentity
        amountIconView.alphaValue = 1.0
        pendingClockView?.removeFromSuperview()
        pendingClockView = nil
        pendingStatusView?.removeFromSuperview()
        pendingStatusView = nil
        dateView.alphaValue = 1.0
    }

    override func layout() {
        super.layout()

        guard let item = item as? WalletTransactionRowItem else {
            return
        }

        let leftInset = item.viewType.innerInset.left
        let rightInset = item.viewType.innerInset.right
        let textX = leftInset + 40 + 10

        if item.transaction.collectible != nil {
            avatarView.setFrameOrigin(NSMakePoint(leftInset, 7))
        } else {
            avatarView.centerY(x: leftInset)
        }
        peerAvatarView?.frame = avatarView.frame
        if let pendingBadgeView {
            let badgeFrame = walletTransactionPendingBadgeFrame()
            pendingBadgeView.setFrameOrigin(NSMakePoint(
                avatarView.frame.minX + badgeFrame.minX,
                avatarView.frame.minY + badgeFrame.minY
            ))
        }

        titleView.setFrameOrigin(NSMakePoint(textX, 7))
        if let addressTitleView {
            addressTitleView.setFrameOrigin(NSMakePoint(textX, 7 + floorToScreenPixels(backingScaleFactor, (titleView.frame.height - addressTitleView.frame.height) / 2)))
        }
        subtitleView.setFrameOrigin(NSMakePoint(textX, titleView.frame.maxY + 2))
        dateView.setFrameOrigin(NSMakePoint(textX, subtitleView.frame.maxY + 3))

        let amountIconX = containerView.frame.width - rightInset - amountIconView.frame.width
        let amountIconSpacing: CGFloat = item.transaction.collectible == nil ? 3 : 1
        let amountX = amountIconX - amountIconSpacing - amountView.frame.width
        let amountY = 7 + floorToScreenPixels(backingScaleFactor, (titleView.frame.height - amountView.frame.height) / 2)
        amountView.setFrameOrigin(NSMakePoint(amountX, amountY))
        amountIconView.setFrameOrigin(NSMakePoint(amountIconX, amountY + floorToScreenPixels(backingScaleFactor, (amountView.frame.height - amountIconView.frame.height) / 2) - 2))

        if item.transaction.collectible != nil {
            let collectibleFrame = NSMakeRect(textX, dateView.frame.maxY + 8, item.collectibleContentWidth, walletTransactionCollectibleChipHeight)
            collectibleBackgroundView.frame = collectibleFrame
            collectibleImagePlaceholderView.setFrameOrigin(NSMakePoint(collectibleFrame.minX + 2, collectibleFrame.minY + 2))
            collectibleImageView.frame = collectibleImagePlaceholderView.frame

            let collectibleTextX = collectibleFrame.minX + 50
            collectibleTitleView.setFrameOrigin(NSMakePoint(collectibleTextX, collectibleFrame.minY + 5 + 1 / backingScaleFactor))
            collectibleSubtitleView.setFrameOrigin(NSMakePoint(collectibleTextX, collectibleFrame.minY + 23))
        }

        if let presentation = transferPresentation, item.transferAnimation != nil {
            applyTransferPresentation(expansion: presentation.expansion, iconAlpha: presentation.iconAlpha, iconScale: presentation.iconScale, clockAlpha: presentation.clockAlpha, time: presentation.time)
        }
    }

    override var additionBorderInset: CGFloat {
        return 40 + 10
    }
}

@available(macOS 10.15, *)
private final class WalletTransactionAddressTitleView: View {
    private let chips: [CALayer] = (0 ..< 3).map { _ in CALayer() }
    private let textViews: [TextView] = (0 ..< 3).map { _ in TextView() }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        userInteractionEnabled = false
        for chip in chips {
            layer?.addSublayer(chip)
        }
        for textView in textViews {
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            addSubview(textView)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(layouts: [TextViewLayout], scale: CGFloat) {
        setFrameSize(NSMakeSize(walletTransactionAddressTitleContentSize.width * scale, walletTransactionAddressTitleContentSize.height * scale))
        for index in 0 ..< min(layouts.count, chips.count) {
            let chipFrame = walletTransactionAddressTitleChipFrame(index: index, scale: scale)
            chips[index].frame = chipFrame
            chips[index].cornerRadius = 6 * scale
            chips[index].backgroundColor = theme.colors.grayText.withAlphaComponent(0.08).cgColor
            let textView = textViews[index]
            textView.update(layouts[index])
            textView.setFrameOrigin(NSMakePoint(
                chipFrame.minX + floorToScreenPixels(backingScaleFactor, (chipFrame.width - textView.frame.width) / 2),
                chipFrame.minY + floorToScreenPixels(backingScaleFactor, (chipFrame.height - textView.frame.height) / 2)
            ))
        }
    }
}
