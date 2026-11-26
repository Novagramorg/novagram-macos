import Cocoa
import TGUIKit
import GeneralRows
import TelegramTheme
import TelegramCore
import Localization

private let walletRecipientAvatarSize: CGFloat = 36
private let walletRecipientTextInset: CGFloat = 60
private let walletRecipientTitleSpacing: CGFloat = 2
private let walletRecipientUsernameSpacing: CGFloat = 6
private let walletRecipientInfoSize: CGFloat = 44
private let walletRecipientScrambleAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
private let walletRecipientScrambleFlipDuration: Double = 0.14
private let walletRecipientScrambleSweepDuration: Double = 0.4
private let walletRecipientScrambleSettleDuration: Double = 0.546
private let walletRecipientNameFont: NSFont = .medium(.title)
private let walletRecipientUsernameFont: NSFont = .normal(.text)
let walletRecipientAddressFont: NSFont = .menlo(11.5)
private let walletRecipientAddressKerning = ("0" as NSString).size(withAttributes: [.font: walletRecipientAddressFont]).width * 0.08
private let walletRecipientAddressAttributes: [NSAttributedString.Key: Any] = [.font: walletRecipientAddressFont, .kern: walletRecipientAddressKerning]

func walletRecipientDisplaysPlaceholder(address: String?, hasPeer: Bool, isLoading: Bool) -> Bool {
    return hasPeer && (isLoading || (address ?? "").isEmpty)
}

func walletRecipientAddressText(address: String?, hasPeer: Bool, isLoading: Bool) -> String {
    if walletRecipientDisplaysPlaceholder(address: address, hasPeer: hasPeer, isLoading: isLoading) {
        return String(repeating: "0", count: walletAddressLength)
    }
    return address ?? "—"
}

final class WalletLinkedRecipientRowItem: GeneralRowItem {
    fileprivate let environment: WalletUIEnvironment
    fileprivate let peer: EnginePeer?
    fileprivate let address: String?
    fileprivate let isLoading: Bool
    fileprivate let copyAddress: () -> Void
    fileprivate let openPeer: (() -> Void)?
    fileprivate let openingTime: () -> Double?
    fileprivate let nameLayout: TextViewLayout
    fileprivate let usernameLayout: TextViewLayout?
    fileprivate private(set) var addressLayout = TextViewLayout(NSAttributedString())

    init(_ initialSize: NSSize, stableId: AnyHashable, environment: WalletUIEnvironment, peer: EnginePeer?, address: String?, isLoading: Bool, action: @escaping () -> Void, copyAddress: @escaping () -> Void, openPeer: (() -> Void)?, openingTime: @escaping () -> Double? = { nil }) {
        self.environment = environment
        self.peer = peer
        self.address = address
        self.isLoading = isLoading
        self.copyAddress = copyAddress
        self.openPeer = openPeer
        self.openingTime = openingTime
        let name = peer.map { environment.peerTitle($0._asPeer(), compact: false) } ?? strings().walletLinkedRecipientRowItemGramWallet
        self.nameLayout = TextViewLayout(.initialize(string: name, color: theme.colors.text, font: walletRecipientNameFont), maximumNumberOfLines: 1)
        if let username = peer?.addressName, !username.isEmpty {
            self.usernameLayout = TextViewLayout(.initialize(string: "@\(username)", color: theme.colors.grayText, font: walletRecipientUsernameFont), maximumNumberOfLines: 1)
        } else {
            self.usernameLayout = nil
        }
        super.init(initialSize, stableId: stableId, action: action)
    }

    fileprivate var canOpenInfo: Bool {
        return !isLoading && address != nil
    }

    fileprivate var titleHeight: CGFloat {
        return max(17, nameLayout.layoutSize.height, usernameLayout?.layoutSize.height ?? 0)
    }

    fileprivate var textHeight: CGFloat {
        return titleHeight + walletRecipientTitleSpacing + addressLayout.layoutSize.height
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        let textWidth = max(1, width - inset.left - inset.right - walletRecipientTextInset - 42)

        var usernameWidth: CGFloat = 0
        if let usernameLayout {
            usernameLayout.measure(width: floor(textWidth * 0.45))
            usernameWidth = usernameLayout.layoutSize.width + walletRecipientUsernameSpacing
        }
        nameLayout.measure(width: max(1, textWidth - usernameWidth))

        let groupsPerLine = (1 ... 6).last { count in
            let sample = Array(repeating: "0000", count: count).joined(separator: " ")
            return ceil((sample as NSString).size(withAttributes: walletRecipientAddressAttributes).width) <= textWidth
        } ?? 1
        let grid = NSMutableAttributedString(attributedString: walletAddressGrid(walletRecipientAddressText(address: address, hasPeer: peer != nil, isLoading: isLoading), font: walletRecipientAddressFont, columnCount: groupsPerLine))
        grid.addAttribute(.kern, value: walletRecipientAddressKerning, range: NSMakeRange(0, grid.length))
        addressLayout = makeAddressLayout(grid)
        return result
    }

    fileprivate func makeAddressLayout(_ text: NSAttributedString) -> TextViewLayout {
        let lineHeight = ceil(walletRecipientAddressFont.ascender - walletRecipientAddressFont.descender + walletRecipientAddressFont.leading)
        let layout = TextViewLayout(text, lineSpacing: floor(lineHeight * 0.2), alwaysStaticItems: true)
        layout.measure(width: .greatestFiniteMagnitude)
        return layout
    }

    override var height: CGFloat {
        return max(60, textHeight + 12)
    }

    override func viewClass() -> AnyClass {
        return WalletLinkedRecipientRowView.self
    }

    override var accessibilityLabel: String? {
        let name = nameLayout.attributedString.string
        return name.isEmpty ? nil : name
    }

    override var accessibilityValue: String? {
        let parts = [usernameLayout?.attributedString.string, isLoading ? Optional(strings().voiceOverCommonLoading) : address].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

struct WalletRecipientAddressRenderStep: Equatable {
    let tick: Int
    let revealStep: Int
}

enum WalletRecipientAddressPhase {
    case loading
    case revealing
    case ready
}

struct WalletRecipientAddressScramble {
    private struct Source: Equatable {
        let peerId: EnginePeer.Id?
        let address: String?
        let isLoading: Bool
    }

    private(set) var phase: WalletRecipientAddressPhase = .ready
    private(set) var animationElapsed: Double = 0
    private(set) var revealElapsed: Double = 0
    private var source: Source?

    mutating func update(peerId: EnginePeer.Id?, address: String?, isLoading: Bool, isOpening: Bool = false) {
        let source = Source(peerId: peerId, address: address, isLoading: isLoading)
        guard self.source != source else {
            return
        }
        let continuesLoading = self.source != nil && self.source?.peerId == peerId && phase == .loading
        if !continuesLoading {
            animationElapsed = 0
        }
        revealElapsed = 0
        if walletRecipientDisplaysPlaceholder(address: address, hasPeer: peerId != nil, isLoading: isLoading) {
            phase = .loading
        } else if peerId != nil && continuesLoading && !isOpening {
            phase = .revealing
        } else {
            phase = .ready
        }
        self.source = source
    }

    mutating func advance(by delta: Double, isOpening: Bool = false) {
        animationElapsed += delta
        if phase == .revealing && !isOpening {
            revealElapsed += delta
            if revealElapsed >= walletRecipientScrambleSettleDuration {
                phase = .ready
            }
        }
    }

    mutating func skipReveal() {
        if phase == .revealing {
            phase = .ready
        }
    }

    mutating func beginScramble() {
        source = nil
        phase = .loading
        animationElapsed = 0
        revealElapsed = 0
    }

    mutating func beginReveal() {
        guard phase == .loading else {
            return
        }
        phase = .revealing
        revealElapsed = 0
    }

    func renderStep(_ text: String) -> WalletRecipientAddressRenderStep {
        let total = text.filter { $0 != "\n" }.count
        return WalletRecipientAddressRenderStep(
            tick: phase == .ready ? -1 : Int(animationElapsed / walletRecipientScrambleFlipDuration),
            revealStep: phase == .revealing ? Int(revealElapsed / walletRecipientScrambleSweepDuration * Double(max(total - 1, 1))) : -1
        )
    }

    func displayedCharacters(_ text: String) -> [(character: Character, isSettled: Bool)] {
        let total = text.filter { $0 != "\n" }.count
        let tick = Int(animationElapsed / walletRecipientScrambleFlipDuration)
        var place = 0
        var result: [(character: Character, isSettled: Bool)] = []
        for character in text {
            if character == "\n" {
                result.append((character, true))
                continue
            }
            if character == " " || phase == .ready {
                result.append((character, true))
            } else if phase == .revealing && revealElapsed >= walletRecipientScrambleSweepDuration * Double(place) / Double(max(total - 1, 1)) {
                result.append((character, true))
            } else {
                let hash = (place &* 2_654_435_761) ^ (tick &* 40_503)
                result.append((walletRecipientScrambleAlphabet[(hash & 0x7fff_ffff) % walletRecipientScrambleAlphabet.count], false))
            }
            place += 1
        }
        return result
    }
}

final class WalletLinkedRecipientRowView: GeneralRowView {
    private let cardView = View()
    private let avatarControl = Control()
    private var avatarView: WalletUIAvatarView?
    private var tonIconView: ImageView?
    private let nameView = TextView()
    private let usernameView = TextView()
    private let addressControl = Control()
    private let addressView = TextView()
    private let infoControl = Control()
    private let infoIconView = ImageView()
    private var scramble = WalletRecipientAddressScramble()
    private var lastAnimationTimestamp: CFTimeInterval?
    private var animationTimer: Foundation.Timer?
    private var renderedAddressStep: WalletRecipientAddressRenderStep?
    private var introView: WalletSendRecipientIntroView?
    private var openingTime: Double?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cardView.layer?.masksToBounds = true
        for view in [nameView, usernameView, addressView] {
            view.userInteractionEnabled = false
            view.isSelectable = false
            view.isEventLess = true
            view.isAccessibilityDecorative = true
        }
        avatarControl.setAccessibilityLabel(strings().voiceOverCommonProfilePhoto)
        addressControl.setAccessibilityLabel(strings().voiceOverCommonCopy)
        infoControl.setAccessibilityLabel(strings().voiceOverCommonInfo)
        infoIconView.isAccessibilityDecorative = true
        cardView.addSubview(nameView)
        cardView.addSubview(usernameView)
        addressControl.addSubview(addressView)
        cardView.addSubview(addressControl)
        addressControl.set(handler: { [weak self] _ in
            (self?.item as? WalletLinkedRecipientRowItem)?.copyAddress()
        }, for: .Click)
        avatarControl.setFrameSize(NSMakeSize(walletRecipientAvatarSize, walletRecipientAvatarSize))
        avatarControl.set(handler: { [weak self] _ in
            (self?.item as? WalletLinkedRecipientRowItem)?.openPeer?()
        }, for: .Click)
        cardView.addSubview(avatarControl)
        infoIconView.isEventLess = true
        infoIconView.contentGravity = .resizeAspect
        infoIconView.setFrameSize(NSMakeSize(24, 24))
        infoControl.addSubview(infoIconView)
        infoControl.scaleOnClick = true
        infoControl.set(handler: { [weak self] _ in
            (self?.item as? WalletLinkedRecipientRowItem)?.action()
        }, for: .Click)
        cardView.addSubview(infoControl)
        addSubview(cardView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        animationTimer?.invalidate()
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAddressAnimation()
    }

    private func advanceAnimation(to timestamp: CFTimeInterval) {
        guard let previousTimestamp = lastAnimationTimestamp else {
            return
        }
        lastAnimationTimestamp = timestamp
        scramble.advance(by: max(0, timestamp - previousTimestamp), isOpening: openingTime != nil)
    }

    private func updateAddressAnimation(force: Bool = false) {
        let timestamp = CACurrentMediaTime()
        advanceAnimation(to: timestamp)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            scramble.skipReveal()
            openingTime = nil
            refreshOpeningContents()
        }
        updateAddressText(force: force)

        if scramble.phase != .ready && window != nil && !reduceMotion && openingTime == nil {
            if animationTimer == nil {
                lastAnimationTimestamp = timestamp
                let timer = Foundation.Timer(timeInterval: 0.035, repeats: true, block: { [weak self] _ in
                    self?.updateAddressAnimation()
                })
                animationTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        } else {
            animationTimer?.invalidate()
            animationTimer = nil
            lastAnimationTimestamp = openingTime != nil && window != nil ? timestamp : nil
        }
    }

    func updateOpening(time: Double?) {
        advanceAnimation(to: CACurrentMediaTime())
        openingTime = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : time
        updateAddressAnimation()
        refreshOpeningContents()
    }

    private func refreshOpeningContents() {
        guard let item = item as? WalletLinkedRecipientRowItem else {
            return
        }
        let active = openingTime != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if active, let time = openingTime {
            let intro: WalletSendRecipientIntroView
            if let current = introView {
                intro = current
            } else {
                intro = WalletSendRecipientIntroView(frame: cardView.bounds)
                introView = intro
                cardView.addSubview(intro)
            }
            intro.frame = cardView.bounds
            let titleViews = item.usernameLayout != nil ? [nameView, usernameView] : [nameView]
            intro.updateTitle(titleViews, frames: titleViews.map { $0.frame }, primary: theme.colors.text, secondary: theme.colors.grayText)
            intro.updateAddress(addressView, frame: addressView.convert(addressView.bounds, to: cardView), loading: scramble.phase != .ready)
            if item.peer != nil, let avatarView {
                intro.updateAvatar(avatarView, frame: avatarControl.frame)
            } else if item.peer == nil, let tonIconView {
                intro.updateAvatar(tonIconView, frame: tonIconView.frame)
            }
            intro.update(time: time)
            let omega = 2.0 * Double.pi / 0.52
            let wd = omega * sqrt(1.0 - 0.36 * 0.36)
            let k = CGFloat(exp(-0.36 * omega * time) * (cos(wd * time) + 0.36 * omega / wd * sin(wd * time)))
            if let layer = cardView.layer {
                layer.transform = walletAmountCenteredTransform(CATransform3DScale(CATransform3DMakeTranslation(0, 26 * k, 0), 1 - 0.07 * k, 1 - 0.07 * k, 1), layer: layer)
            }
        } else {
            introView?.removeFromSuperview()
            introView = nil
            cardView.layer?.transform = CATransform3DIdentity
        }
        layer?.masksToBounds = !active
        nameView.alphaValue = active ? 0 : 1
        usernameView.alphaValue = active ? 0 : 1
        addressView.alphaValue = active ? 0 : 1
        avatarView?.alphaValue = active ? 0 : 1
        tonIconView?.alphaValue = active ? 0 : 1
        CATransaction.commit()
    }

    private func updateAddressText(force: Bool) {
        guard let item = item as? WalletLinkedRecipientRowItem else {
            return
        }
        let step = scramble.renderStep(item.addressLayout.attributedString.string)
        guard force || step != renderedAddressStep else {
            return
        }
        renderedAddressStep = step
        guard scramble.phase != .ready else {
            addressView.update(item.addressLayout)
            refreshOpeningContents()
            return
        }
        let source = item.addressLayout.attributedString
        let text = NSMutableAttributedString(attributedString: source)
        var index = 0
        for (character, isSettled) in scramble.displayedCharacters(source.string) {
            let length = String(character).utf16.count
            if !isSettled {
                let color = (source.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor) ?? theme.colors.text
                text.replaceCharacters(in: NSMakeRange(index, length), with: String(character))
                text.addAttribute(.foregroundColor, value: color.withMultipliedAlpha(0.35), range: NSMakeRange(index, length))
            }
            index += length
        }
        addressView.update(item.makeAddressLayout(text))
        refreshOpeningContents()
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        let previousPeerId = (self.item as? WalletLinkedRecipientRowItem)?.peer?.id
        super.set(item: item, animated: animated)
        guard let item = item as? WalletLinkedRecipientRowItem else {
            return
        }
        advanceAnimation(to: CACurrentMediaTime())
        openingTime = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : item.openingTime()
        if previousPeerId != item.peer?.id {
            introView?.removeFromSuperview()
            introView = nil
        }
        scramble.update(peerId: item.peer?.id, address: item.address, isLoading: item.isLoading, isOpening: openingTime != nil)
        cardView.backgroundColor = theme.colors.grayBackground
        if let peer = item.peer {
            let avatar: WalletUIAvatarView
            if let current = avatarView {
                avatar = current
            } else {
                avatar = item.environment.makeAvatar(font: .avatar(14))
                avatar.userInteractionEnabled = false
                avatar.isEventLess = true
                avatar.setFrameSize(NSMakeSize(walletRecipientAvatarSize, walletRecipientAvatarSize))
                avatarControl.addSubview(avatar)
                avatarView = avatar
            }
            avatar.update(peer: peer._asPeer(), synchronousLoad: true)
            avatarControl.isHidden = false
            tonIconView?.isHidden = true
        } else {
            avatarControl.isHidden = true
            let icon: ImageView
            if let current = tonIconView {
                icon = current
            } else {
                icon = ImageView()
                icon.isEventLess = true
                icon.isAccessibilityDecorative = true
                icon.contentGravity = .resizeAspectFill
                icon.layer?.masksToBounds = true
                icon.layer?.cornerRadius = walletRecipientAvatarSize / 2
                icon.setFrameSize(NSMakeSize(walletRecipientAvatarSize, walletRecipientAvatarSize))
                cardView.addSubview(icon)
                tonIconView = icon
            }
            icon.image = NSImage(named: "Wallet_Ton")?.precomposed()
            icon.isHidden = false
        }
        nameView.update(item.nameLayout)
        usernameView.update(item.usernameLayout)
        usernameView.isHidden = item.usernameLayout == nil
        updateAddressAnimation(force: true)
        addressControl.isEventLess = !item.canOpenInfo
        avatarControl.userInteractionEnabled = item.openPeer != nil
        infoIconView.image = walletAddressInfoIcon() ?? theme.icons.chat_gigagroup_info.highlight(color: walletClassicAccent)
        infoControl.isEnabled = item.canOpenInfo
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? WalletLinkedRecipientRowItem else {
            return
        }
        let cardFrame = NSMakeRect(item.inset.left, 0, max(1, frame.width - item.inset.left - item.inset.right), frame.height)
        cardView.frame = cardFrame
        cardView.layer?.cornerRadius = cardFrame.height / 2

        let avatarOrigin = NSMakePoint(16, floorToScreenPixels(backingScaleFactor, (cardFrame.height - walletRecipientAvatarSize) / 2))
        avatarControl.setFrameOrigin(avatarOrigin)
        tonIconView?.setFrameOrigin(avatarOrigin)

        let textY = floorToScreenPixels(backingScaleFactor, (cardFrame.height - item.textHeight) / 2)
        nameView.setFrameOrigin(NSMakePoint(walletRecipientTextInset, textY))
        let baselineOffset = floorToScreenPixels(backingScaleFactor, walletRecipientNameFont.ascender) - floorToScreenPixels(backingScaleFactor, walletRecipientUsernameFont.ascender)
        usernameView.setFrameOrigin(NSMakePoint(nameView.frame.maxX + walletRecipientUsernameSpacing, textY + baselineOffset))

        let addressFrame = NSMakeRect(walletRecipientTextInset, textY + 1 + item.titleHeight + walletRecipientTitleSpacing, item.addressLayout.layoutSize.width, item.addressLayout.layoutSize.height)
        addressControl.frame = addressFrame
        addressView.setFrameOrigin(.zero)

        infoControl.frame = NSMakeRect(cardFrame.width - 6 - walletRecipientInfoSize, floorToScreenPixels(backingScaleFactor, (cardFrame.height - walletRecipientInfoSize) / 2), walletRecipientInfoSize, walletRecipientInfoSize)
        infoIconView.center()
        refreshOpeningContents()
    }
}

private final class WalletLinkedRecipientInfoRowItem: TableRowItem {
    fileprivate let textLayout: TextViewLayout
    fileprivate let addressLayout: TextViewLayout
    fileprivate let copyAddress: () -> Void
    fileprivate let address: String
    private let openPeer: (() -> Void)?

    init(_ initialSize: NSSize, stableId: AnyHashable, text: NSAttributedString, address: String, openPeer: (() -> Void)?, copyAddress: @escaping () -> Void) {
        self.address = address
        self.openPeer = openPeer
        self.textLayout = TextViewLayout(text, alignment: .center, alwaysStaticItems: true)
        if let openPeer {
            self.textLayout.interactions = TextViewInteractions(processURL: { _ in
                openPeer()
            })
        }
        self.addressLayout = TextViewLayout(walletAddressGrid(address, font: .semiboldMonospace(15), secondaryColor: theme.colors.text.withMultipliedAlpha(0.32)), alignment: .center, lineSpacing: 4, alwaysStaticItems: true)
        self.copyAddress = copyAddress
        super.init(initialSize, stableId: stableId)
        _ = makeSize(initialSize.width, oldWidth: 0)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        self.textLayout.measure(width: width - 40)
        self.addressLayout.measure(width: width - 72)
        return result
    }

    fileprivate var addressBlockHeight: CGFloat {
        return self.addressLayout.layoutSize.height + 24
    }

    override var height: CGFloat {
        return self.textLayout.layoutSize.height + 16 + self.addressBlockHeight
    }

    override func viewClass() -> AnyClass {
        return WalletLinkedRecipientInfoRowView.self
    }

    override var accessibilityLabel: String? {
        let text = textLayout.attributedString.string
        return text.isEmpty ? address : text
    }

    override var accessibilityValue: String? {
        return address
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    override func accessibilityPerformPress() -> Bool {
        copyAddress()
        return true
    }

    override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        guard let openPeer else {
            return nil
        }
        return [NSAccessibilityCustomAction(name: strings().voiceOverCommonOpen, handler: {
            openPeer()
            return true
        })]
    }
}

private final class WalletLinkedRecipientInfoRowView: TableRowView {
    private let textView = TextView()
    private let addressBlockView = WalletAddressControl(frame: .zero)

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textView.isSelectable = false
        addSubview(textView)
        addSubview(addressBlockView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? WalletLinkedRecipientInfoRowItem else {
            return
        }
        textView.update(item.textLayout)
        addressBlockView.update(address: item.address, layout: item.addressLayout, copyAddress: item.copyAddress)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? WalletLinkedRecipientInfoRowItem else {
            return
        }
        textView.centerX(y: 0)
        addressBlockView.frame = NSMakeRect(20, textView.frame.maxY + 16, frame.width - 40, item.addressBlockHeight)
    }
}

private func walletLinkedRecipientInfoText(_ linkText: String?) -> NSAttributedString {
    guard let linkText else {
        let unlinked = NSMutableAttributedString()
        unlinked.append(string: strings().walletLinkedRecipientRowItemNotLinked, color: theme.colors.darkGrayText, font: .normal(.text))
        return unlinked
    }
    let format = strings().walletLinkedRecipientRowItemLinkedTo("%@")
    let parts = format.components(separatedBy: "%@")
    let text = NSMutableAttributedString()
    text.append(string: parts.first, color: theme.colors.darkGrayText, font: .normal(.text))
    let range = text.append(string: linkText, color: walletClassicAccent, font: .medium(.text))
    text.addAttribute(.link, value: linkText, range: range)
    text.append(string: parts.dropFirst().joined(separator: "%@"), color: theme.colors.darkGrayText, font: .normal(.text))
    return text
}

func showWalletLinkedRecipientInfo(environment: WalletUIEnvironment, window: Window, peer: EnginePeer?, address: String, openPeer: (() -> Void)?) {
    let linkText: String?
    let title: String
    if let peer {
        if let username = peer.addressName, !username.isEmpty {
            linkText = "@\(username)"
        } else {
            linkText = environment.peerTitle(peer._asPeer(), compact: false)
        }
        title = strings().walletLinkedRecipientRowItemPeerWallet(environment.peerTitle(peer._asPeer(), compact: true))
    } else {
        linkText = nil
        title = strings().walletLinkedRecipientRowItemUnlinkedWallet
    }
    let text = walletLinkedRecipientInfoText(linkText)
    environment.presentAlert(window: window, header: title, ok: strings().modalOK, content: { initialSize, stableId in
        return WalletLinkedRecipientInfoRowItem(initialSize, stableId: stableId, text: text, address: address, openPeer: openPeer, copyAddress: {
            walletCopyAddress(address, environment: environment, window: window)
        })
    })
}

private func walletAddressInfoIcon() -> CGImage? {
    guard let url = Bundle.module.url(forResource: "WalletAddressInfo", withExtension: "pdf"), let image = NSImage(contentsOf: url) else {
        return nil
    }
    return image.precomposed(walletClassicAccent)
}
