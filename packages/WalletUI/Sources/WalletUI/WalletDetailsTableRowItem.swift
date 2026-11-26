import Cocoa
import TGUIKit
import TelegramTheme
import TelegramContext
import GeneralRows

func walletDetailsAddressDisplaysAction(availableWidth: CGFloat, addressLineCount: Int) -> Bool {
    return availableWidth > 0 && addressLineCount <= 3
}

public final class WalletDetailsTableRowItem: GeneralRowItem {
    public struct Row {
        public let label: String
        public let value: String
        public let isAddress: Bool
        public let icon: CGImage?
        public let secondaryValue: String?
        public let badge: (text: String, color: NSColor?)?
        public let valueColor: NSColor?
        public let onClick: (() -> Void)?
        public let action: (title: String, handler: () -> Void)?
        public let isLoading: Bool

        public init(label: String, value: String, isAddress: Bool = false, icon: CGImage? = nil, secondaryValue: String? = nil, badge: (text: String, color: NSColor?)? = nil, valueColor: NSColor? = nil, onClick: (() -> Void)? = nil, action: (title: String, handler: () -> Void)? = nil, isLoading: Bool = false) {
            self.label = label
            self.value = value
            self.isAddress = isAddress
            self.icon = icon
            self.secondaryValue = secondaryValue
            self.badge = badge
            self.valueColor = valueColor
            self.onClick = onClick
            self.action = action
            self.isLoading = isLoading
        }
    }

    fileprivate final class MeasuredRow {
        public let row: Row
        public let labelLayout: TextViewLayout
        public let valueLayout: TextViewLayout
        public let secondaryLayout: TextViewLayout?
        public let badgeLayout: TextViewLayout?
        public let badgeColor: NSColor
        public let actionLayout: TextViewLayout?
        public var displaysAction = true
        public var height: CGFloat = 40

        public var badgeSize: NSSize {
            guard let badgeLayout else {
                return .zero
            }
            return NSMakeSize(badgeLayout.layoutSize.width + WalletDetailsTableRowItem.badgeHorizontalInset * 2, badgeLayout.layoutSize.height + WalletDetailsTableRowItem.badgeVerticalInset * 2)
        }

        public var actionSize: NSSize {
            guard let actionLayout else {
                return .zero
            }
            let height = WalletDetailsTableRowItem.actionHeight
            let width = actionLayout.layoutSize.width + WalletDetailsTableRowItem.actionHorizontalInset * 2
            return NSMakeSize(max(width, height), height)
        }

        public init(row: Row) {
            self.row = row
            self.labelLayout = TextViewLayout(.initialize(string: row.label, color: theme.colors.text, font: .normal(.text)), maximumNumberOfLines: 1)
            if row.isAddress {
                self.valueLayout = TextViewLayout(walletAddressGrid(row.value, font: .code(.text)))
            } else {
                self.valueLayout = TextViewLayout(.initialize(string: row.value, color: row.valueColor ?? theme.colors.text, font: .normal(.text)))
            }
            if let secondaryValue = row.secondaryValue {
                self.secondaryLayout = TextViewLayout(.initialize(string: secondaryValue, color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1)
            } else {
                self.secondaryLayout = nil
            }
            let badgeColor = row.badge?.color ?? walletClassicAccent
            self.badgeColor = badgeColor
            if let badge = row.badge {
                self.badgeLayout = TextViewLayout(.initialize(string: badge.text, color: badgeColor, font: .normal(.small)), maximumNumberOfLines: 1)
            } else {
                self.badgeLayout = nil
            }
            if let action = row.action {
                self.actionLayout = TextViewLayout(.initialize(string: action.title, color: walletClassicAccent, font: .normal(.small)), maximumNumberOfLines: 1)
            } else {
                self.actionLayout = nil
            }
        }
    }

    public static let horizontalPadding: CGFloat = 12
    public static let verticalPadding: CGFloat = 11
    public static let iconSize: CGFloat = 16
    public static let badgeHorizontalInset: CGFloat = 5
    public static let actionHorizontalInset: CGFloat = 6
    public static let actionHeight: CGFloat = 18
    public static let badgeVerticalInset: CGFloat = 2
    public static let badgeSpacing: CGFloat = 6
    public static let placeholderSize = NSMakeSize(128, 16)

    fileprivate let measuredRows: [MeasuredRow]
    fileprivate private(set) var labelColumnWidth: CGFloat = 0
    var intro: WalletOpenIntro?

    public init(_ initialSize: NSSize, stableId: AnyHashable, rows: [Row], viewType: GeneralViewType) {
        self.measuredRows = rows.map { MeasuredRow(row: $0) }
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)

        var maxLabelWidth: CGFloat = 0
        for measured in measuredRows {
            measured.labelLayout.measure(width: 160)
            maxLabelWidth = max(maxLabelWidth, measured.labelLayout.layoutSize.width)
        }
        labelColumnWidth = min(160, maxLabelWidth + WalletDetailsTableRowItem.horizontalPadding * 2)

        for measured in measuredRows {
            var availableWidth = blockWidth - labelColumnWidth - WalletDetailsTableRowItem.horizontalPadding * 2
            if measured.row.icon != nil {
                availableWidth -= WalletDetailsTableRowItem.iconSize + 5
            }
            if let badgeLayout = measured.badgeLayout {
                badgeLayout.measure(width: max(0, availableWidth))
                availableWidth -= measured.badgeSize.width + WalletDetailsTableRowItem.badgeSpacing
            }
            if let actionLayout = measured.actionLayout {
                actionLayout.measure(width: max(0, availableWidth))
                availableWidth -= measured.actionSize.width + WalletDetailsTableRowItem.badgeSpacing
            }
            if let secondaryLayout = measured.secondaryLayout {
                secondaryLayout.measure(width: max(0, availableWidth))
                availableWidth -= secondaryLayout.layoutSize.width + 5
            }
            measured.displaysAction = true
            if measured.row.isAddress, measured.actionLayout != nil {
                measured.valueLayout.measure(width: max(0, availableWidth))
                measured.displaysAction = walletDetailsAddressDisplaysAction(availableWidth: availableWidth, addressLineCount: measured.valueLayout.numberOfLines)
                if !measured.displaysAction {
                    availableWidth += measured.actionSize.width + WalletDetailsTableRowItem.badgeSpacing
                }
            }
            measured.valueLayout.measure(width: max(0, availableWidth))

            var contentHeight = measured.valueLayout.layoutSize.height
            if measured.row.icon != nil {
                contentHeight = max(contentHeight, WalletDetailsTableRowItem.iconSize)
            }
            if measured.badgeLayout != nil {
                contentHeight = max(contentHeight, measured.badgeSize.height)
            }
            if measured.actionLayout != nil, measured.displaysAction {
                contentHeight = max(contentHeight, measured.actionSize.height)
            }
            if measured.row.isLoading {
                contentHeight = max(contentHeight, WalletDetailsTableRowItem.placeholderSize.height)
            }
            measured.height = max(measured.labelLayout.layoutSize.height, contentHeight) + WalletDetailsTableRowItem.verticalPadding * 2
        }

        return true
    }

    public override var height: CGFloat {
        return measuredRows.reduce(0, { $0 + $1.height })
    }

    public override func viewClass() -> AnyClass {
        return WalletDetailsTableRowView.self
    }

    public override var accessibilityLabel: String? {
        let labels = measuredRows.map { $0.row.label }.filter { !$0.isEmpty }
        return labels.isEmpty ? nil : labels.joined(separator: ", ")
    }

    public override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        let actions = measuredRows.compactMap { measured -> NSAccessibilityCustomAction? in
            guard let onClick = measured.row.onClick else {
                return nil
            }
            return NSAccessibilityCustomAction(name: measured.row.label, handler: {
                onClick()
                return true
            })
        }
        return actions.isEmpty ? nil : actions
    }
}

private final class WalletDetailsTableRowView: GeneralContainableRowView, WalletIntroParticipant {
    private enum IntroPhase {
        case idle
        case pending
        case playing
    }

    private final class RowViews {
        public let labelView = TextView()
        public let valueView = TextView()
        public var iconView: ImageView?
        public var secondaryView: TextView?
        public var badgeView: View?
        public var actionView: Control?
        public var placeholderView: ShimmerEffectView?
        public var separator: View?
    }

    private let labelColumnBackground = View()
    private let verticalSeparator = View()
    private var rowViews: [RowViews] = []
    private var introPhase: IntroPhase = .idle
    private var addressReveal: WalletAddressReveal?
    private var addressAnimator: ConstantDisplayLinkAnimator?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        containerView.addSubview(labelColumnBackground)
        containerView.addSubview(verticalSeparator)
        containerView.layer?.cornerRadius = containerView.cornerRadius
        containerView.layer?.borderWidth = .borderSize

        containerView.set(handler: { [weak self] _ in
            self?.handleClick()
        }, for: .Click)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func handleClick() {
        guard let item = item as? WalletDetailsTableRowItem, let window = self.window else {
            return
        }
        let point = containerView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        var y: CGFloat = 0
        for (index, measured) in item.measuredRows.enumerated() {
            let rect = NSMakeRect(0, y, containerView.frame.width, measured.height)
            if NSPointInRect(point, rect) {
                if rowViews.indices.contains(index), let actionView = rowViews[index].actionView, !actionView.isHidden, NSPointInRect(point, actionView.frame) {
                    return
                }
                measured.row.onClick?()
                return
            }
            y += measured.height
        }
    }

    private var lineColor: NSColor {
        return theme.colors.isDark ? theme.colors.text.withAlphaComponent(0.1) : theme.colors.grayForeground
    }

    public override func updateColors() {
        super.updateColors()
        labelColumnBackground.backgroundColor = theme.colors.isDark ? theme.colors.grayBackground : theme.colors.listBackground
        verticalSeparator.backgroundColor = lineColor
        containerView.layer?.borderColor = lineColor.cgColor
        for rowView in rowViews {
            rowView.separator?.backgroundColor = lineColor
        }
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? WalletDetailsTableRowItem else {
            return
        }

        for rowView in rowViews {
            rowView.labelView.removeFromSuperview()
            rowView.valueView.removeFromSuperview()
            rowView.iconView?.removeFromSuperview()
            rowView.secondaryView?.removeFromSuperview()
            rowView.badgeView?.removeFromSuperview()
            rowView.actionView?.removeFromSuperview()
            rowView.placeholderView?.removeFromSuperview()
            rowView.separator?.removeFromSuperview()
        }
        rowViews.removeAll()

        for (index, measured) in item.measuredRows.enumerated() {
            let rowView = RowViews()

            for textView in [rowView.labelView, rowView.valueView] {
                textView.userInteractionEnabled = false
                textView.isSelectable = false
            }

            rowView.labelView.update(measured.labelLayout)
            rowView.valueView.update(measured.valueLayout)
            containerView.addSubview(rowView.labelView)
            containerView.addSubview(rowView.valueView)

            if let icon = measured.row.icon {
                let iconView = ImageView(frame: NSMakeRect(0, 0, WalletDetailsTableRowItem.iconSize, WalletDetailsTableRowItem.iconSize))
                iconView.contentGravity = .resizeAspect
                iconView.isAccessibilityDecorative = true
                iconView.image = icon
                containerView.addSubview(iconView)
                rowView.iconView = iconView
            }

            if let badgeLayout = measured.badgeLayout {
                let badgeView = View(frame: NSMakeRect(0, 0, measured.badgeSize.width, measured.badgeSize.height))
                badgeView.backgroundColor = measured.badgeColor.withAlphaComponent(0.2)
                badgeView.layer?.cornerRadius = measured.badgeSize.height / 2
                let badgeTextView = TextView()
                badgeTextView.userInteractionEnabled = false
                badgeTextView.isSelectable = false
                badgeTextView.isEventLess = true
                badgeTextView.update(badgeLayout)
                badgeView.addSubview(badgeTextView)
                badgeTextView.center()
                containerView.addSubview(badgeView)
                rowView.badgeView = badgeView
            }

            if let secondaryLayout = measured.secondaryLayout {
                let secondaryView = TextView()
                secondaryView.userInteractionEnabled = false
                secondaryView.isSelectable = false
                secondaryView.update(secondaryLayout)
                containerView.addSubview(secondaryView)
                rowView.secondaryView = secondaryView
            }

            if let actionLayout = measured.actionLayout, let action = measured.row.action {
                let actionView = Control(frame: NSMakeRect(0, 0, measured.actionSize.width, measured.actionSize.height))
                actionView.backgroundColor = walletClassicAccent.withAlphaComponent(0.1)
                actionView.layer?.cornerRadius = measured.actionSize.height / 2
                actionView.scaleOnClick = true
                actionView.setAccessibilityLabel(action.title)
                let actionTextView = TextView()
                actionTextView.userInteractionEnabled = false
                actionTextView.isSelectable = false
                actionTextView.isEventLess = true
                actionTextView.isAccessibilityDecorative = true
                actionTextView.update(actionLayout)
                actionView.addSubview(actionTextView)
                actionTextView.center()
                actionView.set(handler: { _ in
                    action.handler()
                }, for: .Click)
                containerView.addSubview(actionView)
                rowView.actionView = actionView
            }

            if measured.row.isLoading {
                let placeholderView = ShimmerEffectView()
                placeholderView.isEventLess = true
                containerView.addSubview(placeholderView)
                rowView.placeholderView = placeholderView
            }

            if index > 0 {
                let separator = View()
                separator.backgroundColor = lineColor
                containerView.addSubview(separator)
                rowView.separator = separator
            }

            rowViews.append(rowView)
        }

        item.intro?.attach(self)
        applyAddressVisibility()
        if introPhase == .playing, let reveal = addressReveal {
            for (_, view) in addressViews {
                reveal.addFade(to: view.layer)
            }
            renderAddressReveal(force: true)
        }

        needsLayout = true
    }

    private var addressViews: [(measured: WalletDetailsTableRowItem.MeasuredRow, view: TextView)] {
        guard let item = item as? WalletDetailsTableRowItem else {
            return []
        }
        return zip(item.measuredRows, rowViews).compactMap { measured, rowView in
            return measured.row.isAddress ? (measured, rowView.valueView) : nil
        }
    }

    private func applyAddressVisibility() {
        for (_, view) in addressViews {
            view.layer?.opacity = introPhase == .pending ? 0.0 : 1.0
        }
    }

    func prepareIntro() {
        introPhase = .pending
        applyAddressVisibility()
    }

    func cancelIntro() {
        finishAddressReveal()
    }

    func playIntro(at time: CFTimeInterval, pace: Double) {
        guard introPhase == .pending else {
            return
        }
        introPhase = .playing
        let reveal = WalletAddressReveal(startTime: time, scrambleDuration: WalletTransactionIntro.addressScrambleDuration * pace, speed: WalletTransactionIntro.addressRevealSpeed / pace)
        addressReveal = reveal
        applyAddressVisibility()
        for (_, view) in addressViews {
            reveal.addFade(to: view.layer)
        }
        renderAddressReveal(force: true)
        let animator = ConstantDisplayLinkAnimator(update: { [weak self] in
            self?.addressRevealTick()
        }, fps: 60)
        animator.isPaused = false
        addressAnimator = animator
    }

    private func addressRevealTick() {
        guard let reveal = addressReveal else {
            finishAddressReveal()
            return
        }
        reveal.advance(to: CACurrentMediaTime())
        if reveal.isFinished {
            finishAddressReveal()
        } else {
            renderAddressReveal(force: false)
        }
    }

    private func renderAddressReveal(force: Bool) {
        guard let reveal = addressReveal else {
            return
        }
        var changed = force
        for (measured, view) in addressViews {
            let grid = measured.valueLayout.attributedString
            guard let characters = reveal.characters(for: grid.string, force: changed) else {
                return
            }
            changed = true
            let text = NSMutableAttributedString(attributedString: grid)
            for (index, (character, isSettled)) in characters.enumerated() where index < text.length {
                let range = NSRange(location: index, length: 1)
                text.replaceCharacters(in: range, with: String(character))
                if !isSettled, let color = grid.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor {
                    text.addAttribute(.foregroundColor, value: color.withAlphaComponent(color.alphaComponent * 0.35), range: range)
                }
            }
            let layout = TextViewLayout(text)
            layout.measure(width: measured.valueLayout.layoutSize.width + 1)
            view.update(layout)
        }
    }

    private func finishAddressReveal() {
        addressAnimator?.invalidate()
        addressAnimator = nil
        addressReveal = nil
        introPhase = .idle
        for (measured, view) in addressViews {
            view.layer?.removeAnimation(forKey: WalletAddressReveal.fadeKey)
            view.update(measured.valueLayout)
        }
        applyAddressVisibility()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil, introPhase == .playing {
            finishAddressReveal()
        }
    }

    public override func layout() {
        super.layout()

        guard let item = item as? WalletDetailsTableRowItem else {
            return
        }

        labelColumnBackground.frame = NSMakeRect(0, 0, item.labelColumnWidth, containerView.frame.height)
        verticalSeparator.frame = NSMakeRect(item.labelColumnWidth, 0, .borderSize, containerView.frame.height)

        let padding = WalletDetailsTableRowItem.horizontalPadding
        var y: CGFloat = 0
        for (index, measured) in item.measuredRows.enumerated() {
            guard rowViews.indices.contains(index) else {
                break
            }
            let rowView = rowViews[index]

            rowView.separator?.frame = NSMakeRect(0, y, containerView.frame.width, .borderSize)
            rowView.labelView.setFrameOrigin(NSMakePoint(padding, y + WalletDetailsTableRowItem.verticalPadding))

            var contentX = item.labelColumnWidth + padding
            let firstLineHeight = min(measured.valueLayout.layoutSize.height, 22)
            if let iconView = rowView.iconView {
                iconView.setFrameOrigin(NSMakePoint(contentX, y + WalletDetailsTableRowItem.verticalPadding + floorToScreenPixels(backingScaleFactor, (firstLineHeight - iconView.frame.height) / 2)))
                contentX += iconView.frame.width + 5
            }
            rowView.valueView.setFrameOrigin(NSMakePoint(contentX, y + WalletDetailsTableRowItem.verticalPadding))
            var trailingX = rowView.valueView.frame.maxX
            if let badgeView = rowView.badgeView {
                badgeView.setFrameOrigin(NSMakePoint(trailingX + WalletDetailsTableRowItem.badgeSpacing, y + WalletDetailsTableRowItem.verticalPadding + floorToScreenPixels(backingScaleFactor, (firstLineHeight - badgeView.frame.height) / 2)))
                trailingX = badgeView.frame.maxX
            }
            if let secondaryView = rowView.secondaryView {
                secondaryView.setFrameOrigin(NSMakePoint(trailingX + 5, y + WalletDetailsTableRowItem.verticalPadding + floorToScreenPixels(backingScaleFactor, (firstLineHeight - secondaryView.frame.height) / 2)))
                trailingX = secondaryView.frame.maxX
            }
            if let actionView = rowView.actionView {
                actionView.isHidden = !measured.displaysAction
                actionView.setFrameOrigin(NSMakePoint(trailingX + WalletDetailsTableRowItem.badgeSpacing, y + WalletDetailsTableRowItem.verticalPadding + floorToScreenPixels(backingScaleFactor, (firstLineHeight - actionView.frame.height) / 2)))
            }
            if let placeholderView = rowView.placeholderView {
                let size = NSMakeSize(max(0, min(WalletDetailsTableRowItem.placeholderSize.width, containerView.frame.width - contentX - padding)), WalletDetailsTableRowItem.placeholderSize.height)
                placeholderView.frame = NSMakeRect(contentX, y + floorToScreenPixels(backingScaleFactor, (measured.height - size.height) / 2), size.width, size.height)
                placeholderView.updateAbsoluteRect(placeholderView.frame, within: containerView.frame.size)
                placeholderView.update(backgroundColor: theme.colors.background, foregroundColor: theme.colors.grayBackground, shimmeringColor: theme.colors.background.withAlphaComponent(0.6), shapes: [.roundedRect(rect: NSMakeRect(0, 0, size.width, size.height), cornerRadius: size.height / 2)], horizontal: true, size: size)
            }

            y += measured.height
        }
    }
}
