import Cocoa
import TGUIKit
import TelegramTheme
import TelegramContext
import GeneralRows

func walletInfoParagraphTextY(iconMidY: CGFloat, textHeight: CGFloat, topInset: CGFloat) -> CGFloat {
    if textHeight <= 20 {
        return iconMidY - textHeight / 2 + 1
    }
    return topInset
}

public final class WalletInfoParagraphRowItem: GeneralRowItem {
    fileprivate let icon: CGImage?
    fileprivate let titleLayout: TextViewLayout?
    fileprivate let textLayout: TextViewLayout
    fileprivate let textIcon: CGImage?
    fileprivate let inlineTextIcon: CGImage?
    fileprivate let centered: Bool

    fileprivate let iconColumnWidth: CGFloat = 30
    fileprivate let iconSpacing: CGFloat = 14
    fileprivate let sidePadding: CGFloat = 16
    fileprivate let verticalPadding: CGFloat = 10
    fileprivate var titleSpacing: CGFloat {
        return centered ? 5 : 3
    }

    private var contentHeight: CGFloat = 0

    public init(_ initialSize: NSSize, stableId: AnyHashable, icon: CGImage?, title: String?, text: String, viewType: GeneralViewType, centered: Bool = false, titleFont: NSFont = .medium(15), textFont: NSFont = .normal(13), textColor: NSColor? = nil, textIcon: CGImage? = nil, inlineTextIcon: NSImage? = nil, detectBold: Bool = false) {
        self.icon = icon
        self.textIcon = textIcon
        self.centered = centered
        self.titleLayout = title.map {
            TextViewLayout(.initialize(string: $0, color: theme.colors.text, font: titleFont), maximumNumberOfLines: centered ? 0 : 1, alignment: centered ? .center : .left)
        }
        let resolvedTextColor = textColor ?? theme.colors.grayText
        let attributedText = NSAttributedString.initialize(string: text, color: resolvedTextColor, font: textFont).mutableCopy() as! NSMutableAttributedString
        if detectBold {
            attributedText.detectBoldColorInString(with: .medium(13))
        }
        if let inlineTextIcon = inlineTextIcon?.precomposed(resolvedTextColor), let range = attributedText.string.range(of: "#") {
            let iconRange = NSRange(range, in: attributedText.string)
            let placeholderWidth = attributedText.attributedSubstring(from: iconRange).size().width
            attributedText.addAttributes([
                TextInputAttributes.embedded: "inlineTextIcon",
                .kern: inlineTextIcon.backingSize.width - placeholderWidth
            ], range: iconRange)
            self.inlineTextIcon = inlineTextIcon
        } else {
            self.inlineTextIcon = nil
        }
        self.textLayout = TextViewLayout(attributedText, alignment: centered ? .center : .left)
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    public override var height: CGFloat {
        return contentHeight
    }

    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)

        let contentWidth = blockWidth - sidePadding * 2 - (centered ? 0 : iconColumnWidth + iconSpacing)
        if centered, let titleLayout {
            walletMeasureBalanced(titleLayout, width: contentWidth)
        } else {
            titleLayout?.measure(width: contentWidth)
        }
        textLayout.measure(width: contentWidth - (centered && textIcon != nil ? 20 : 0))

        if centered {
            contentHeight = verticalPadding / 2 + 88 + 18 + (titleLayout?.layoutSize.height ?? 0) + (titleLayout == nil ? 0 : titleSpacing) + textLayout.layoutSize.height + verticalPadding
        } else if let titleLayout {
            contentHeight = verticalPadding + titleLayout.layoutSize.height + 3 + textLayout.layoutSize.height + verticalPadding
        } else {
            contentHeight = verticalPadding + max(iconColumnWidth, textLayout.layoutSize.height) + verticalPadding
        }

        return true
    }

    public override func viewClass() -> AnyClass {
        return WalletInfoParagraphRowView.self
    }

    private var accessibilityText: String {
        let text = textLayout.attributedString.string
        return inlineTextIcon != nil ? text.replacingOccurrences(of: "#", with: "") : text
    }

    public override var accessibilityLabel: String? {
        if let title = titleLayout?.attributedString.string, !title.isEmpty {
            return title
        }
        let text = accessibilityText
        return text.isEmpty ? nil : text
    }

    public override var accessibilityValue: String? {
        guard let title = titleLayout?.attributedString.string, !title.isEmpty else {
            return nil
        }
        let text = accessibilityText
        return text.isEmpty ? nil : text
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .staticText
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }
}

private final class WalletInfoParagraphRowView: TableRowView {
    private let iconView = ImageView()
    private let titleView = TextView()
    private let textView = TextView()
    private let textIconView = ImageView()
    private var inlineTextIconLayer: SimpleLayer?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        textView.userInteractionEnabled = false
        textView.isSelectable = false

        iconView.isAccessibilityDecorative = true
        textIconView.isAccessibilityDecorative = true

        addSubview(iconView)
        addSubview(titleView)
        addSubview(textView)
        addSubview(textIconView)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var backdorColor: NSColor {
        return .clear
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? WalletInfoParagraphRowItem else {
            return
        }

        iconView.image = item.icon
        if item.centered {
            iconView.contentGravity = .resizeAspectFill
            iconView.setFrameSize(NSMakeSize(88, 88))
            iconView.layer?.cornerRadius = 44
            iconView.layer?.masksToBounds = true
        } else {
            iconView.contentGravity = .resizeAspect
            iconView.layer?.cornerRadius = 0
            iconView.layer?.masksToBounds = false
            iconView.sizeToFit()
            if iconView.frame.width > item.iconColumnWidth || iconView.frame.height > item.iconColumnWidth {
                iconView.setFrameSize(NSMakeSize(item.iconColumnWidth, item.iconColumnWidth))
            }
        }

        if let titleLayout = item.titleLayout {
            titleView.update(titleLayout)
            titleView.isHidden = false
        } else {
            titleView.isHidden = true
        }
        textView.update(item.textLayout)
        if let inlineTextIcon = item.inlineTextIcon, let embedded = item.textLayout.embeddedItems.first {
            let current: SimpleLayer
            if let layer = inlineTextIconLayer {
                current = layer
            } else {
                current = SimpleLayer()
                textView.addEmbeddedLayer(current)
                inlineTextIconLayer = current
            }
            let size = inlineTextIcon.backingSize
            current.contents = inlineTextIcon
            current.frame = CGRect(origin: NSMakePoint(floorToScreenPixels(backingScaleFactor, embedded.rect.midX - size.width / 2), floorToScreenPixels(backingScaleFactor, embedded.rect.midY - size.height / 2 + 1)), size: size)
        } else if let layer = inlineTextIconLayer {
            layer.removeFromSuperlayer()
            inlineTextIconLayer = nil
        }
        textIconView.image = item.textIcon
        textIconView.sizeToFit()
        textIconView.isHidden = item.textIcon == nil

        needsLayout = true
    }

    public override func layout() {
        super.layout()

        guard let item = item as? WalletInfoParagraphRowItem else {
            return
        }

        let blockX = floorToScreenPixels(backingScaleFactor, (frame.width - item.blockWidth) / 2)
        if item.centered {
            iconView.setFrameOrigin(NSMakePoint(blockX + floorToScreenPixels(backingScaleFactor, (item.blockWidth - iconView.frame.width) / 2), item.verticalPadding / 2))
            let titleY = iconView.frame.maxY + 18
            let textY: CGFloat
            if item.titleLayout != nil {
                titleView.setFrameOrigin(NSMakePoint(blockX + floorToScreenPixels(backingScaleFactor, (item.blockWidth - titleView.frame.width) / 2), titleY))
                textY = titleView.frame.maxY + item.titleSpacing
            } else {
                textY = titleY
            }
            if item.textIcon != nil {
                let contentWidth = textIconView.frame.width + 4 + textView.frame.width
                let contentX = blockX + floorToScreenPixels(backingScaleFactor, (item.blockWidth - contentWidth) / 2)
                textIconView.setFrameOrigin(NSMakePoint(contentX, textY + floorToScreenPixels(backingScaleFactor, (textView.frame.height - textIconView.frame.height) / 2)))
                textView.setFrameOrigin(NSMakePoint(textIconView.frame.maxX + 4, textY))
            } else {
                textView.setFrameOrigin(NSMakePoint(blockX + floorToScreenPixels(backingScaleFactor, (item.blockWidth - textView.frame.width) / 2), textY))
            }
            return
        }
        let iconX = blockX + item.sidePadding
        let textX = iconX + item.iconColumnWidth + item.iconSpacing

        iconView.setFrameOrigin(NSMakePoint(iconX + floorToScreenPixels(backingScaleFactor, (item.iconColumnWidth - iconView.frame.width) / 2), item.verticalPadding))
        if item.titleLayout != nil {
            titleView.setFrameOrigin(NSMakePoint(textX, item.verticalPadding))
            textView.setFrameOrigin(NSMakePoint(textX, titleView.frame.maxY + 3))
        } else {
            textView.setFrameOrigin(NSMakePoint(textX, floorToScreenPixels(backingScaleFactor, walletInfoParagraphTextY(iconMidY: iconView.frame.midY, textHeight: item.textLayout.layoutSize.height, topInset: item.verticalPadding))))
        }
    }
}
