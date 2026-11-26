import Cocoa
import TGUIKit
import Foundation
import TelegramMedia
import TelegramCore
import TelegramContext
import TelegramTheme
import LocalAnimations
import Localization

public class AnimatedStickerHeaderItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let textLayout: TextViewLayout
    fileprivate let infoLayout: TextViewLayout?
    fileprivate let sticker: LocalAnimatedSticker?
    fileprivate let file: TelegramMediaFile?
    fileprivate let fileParameters: GeneralRowsStickerParameters?
    public let stickerSize: NSSize
    public let bgColor: NSColor?
    public let modify:[String]?
    public let isFullView: Bool
    public let image: CGImage?
    public let _hasBorder: Bool?
    fileprivate let dismiss: (() -> Void)?
    fileprivate let badge: CGImage?
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, sticker: LocalAnimatedSticker?, text: NSAttributedString, infoText: NSAttributedString? = nil, stickerSize: NSSize = NSMakeSize(120, 120), bgColor: NSColor? = nil, modify:[String]? = nil, isFullView: Bool = false, image: CGImage? = nil, viewType: GeneralViewType = .legacy, hasBorder: Bool? = nil, interactions: TextViewInteractions = GeneralRowsHooks.shared.linkExecutor(), dismiss: (() -> Void)? = nil, badge: CGImage? = nil, file: TelegramMediaFile? = nil, fileParameters: GeneralRowsStickerParameters? = nil) {
        self.context = context
        self.image = image
        self.sticker = sticker
        self.file = file
        self.fileParameters = fileParameters
        self.stickerSize = stickerSize
        self.bgColor = bgColor
        self.modify = modify
        self.isFullView = isFullView
        self._hasBorder = hasBorder
        self.dismiss = dismiss
        self.badge = badge
        self.textLayout = TextViewLayout(text, alignment: .center, alwaysStaticItems: true)
        if let infoText = infoText {
            self.infoLayout = TextViewLayout(infoText, alignment: .center, alwaysStaticItems: true)
        } else {
            self.infoLayout = nil
        }
        super.init(initialSize, stableId: stableId, viewType: viewType, inset: viewType == .legacy ? NSEdgeInsets(left: 20, right: 20, top: 0, bottom: 10) : NSEdgeInsets(left: 20, right: 20))

        self.textLayout.interactions = interactions
        self.infoLayout?.interactions = interactions
    }
    
    public override var hasBorder: Bool {
        return _hasBorder ?? super.hasBorder
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool {
        textLayout.measure(width: width - inset.left - inset.right)
        infoLayout?.measure(width: width - inset.left - inset.right)
        return super.makeSize(width, oldWidth: oldWidth)
    }
    
    public override func viewClass() -> AnyClass {
        return AnimtedStickerHeaderView.self
    }

    public override var accessibilityLabel: String? {
        let text = textLayout.attributedString.string
        return text.isEmpty ? nil : text
    }

    public override var accessibilityValue: String? {
        guard let text = infoLayout?.attributedString.string, !text.isEmpty else {
            return nil
        }
        return text
    }
    
    public override var height: CGFloat {
        if isFullView {
            if let table = table {
                var basic:CGFloat = 0
                table.enumerateItems(with: { [weak self] item in
                    if let strongSelf = self {
                        if item.index < strongSelf.index {
                            basic += item.height
                        }
                    }
                    return true
                })
                return table.frame.height - basic
            } else {
                return initialSize.height
            }
        }
        var height: CGFloat = 10 + inset.bottom + stickerSize.height + 10 + textLayout.layoutSize.height
        if let infoLayout = infoLayout {
            height += 10 + infoLayout.layoutSize.height
        }
        return height
    }
}


private final class AnimtedStickerHeaderView : GeneralContainableRowView {
    private var animationView: GeneralRowsAnimatedItemView?
    private var imageView: ImageView?
    private let textView: TextView = TextView()
    private var infoTextView: TextView?
    private var bgView: View?
    private var dismissButton: ImageButton?
    private var badgeView: ImageView?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)

        textView.isSelectable = false
        textView.userInteractionEnabled = true
    }
    
    override var backdorColor: NSColor {
        guard let item = item as? AnimatedStickerHeaderItem else { return super.backdorColor }
        return item.isFullView ? (item.bgColor ?? theme.colors.listBackground) : (item.viewType == .legacy ? theme.colors.listBackground : super.backdorColor)
    }
    
    override func updateColors() {
        super.updateColors()
        textView.backgroundColor = backdorColor
        infoTextView?.backgroundColor = backdorColor
    }
    
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? AnimatedStickerHeaderItem else { return }
        
        if let file = item.file, let params = item.fileParameters {
            if let view = self.imageView {
                performSubviewRemoval(view, animated: animated)
                self.imageView = nil
            }

            let current: GeneralRowsAnimatedItemView
            if let view = self.animationView {
                current = view
            } else {
                current = GeneralRowsHooks.shared.makeStickerHeaderView(item.stickerSize.bounds)
                self.animationView = current
                addSubview(current)
            }

            current.updateStickerHeader(with: file, size: item.stickerSize, context: item.context, parent: nil, table: item.table, parameters: params, animated: animated, positionFlags: nil, approximateSynchronousValue: false)
        } else if let sticker = item.sticker {
            if let view = self.imageView {
                performSubviewRemoval(view, animated: animated)
                self.imageView = nil
            }

            let current: GeneralRowsAnimatedItemView
            if let view = self.animationView {
                current = view
            } else {
                current = GeneralRowsHooks.shared.makeStickerHeaderView(item.stickerSize.bounds)
                self.animationView = current
                addSubview(current)
            }
            let params = GeneralRowsHooks.shared.localStickerParameters(sticker)

            if let modify = item.modify, let color = item.bgColor {
                params.colors = modify.map {
                    .init(keyPath: $0, color: color)
                }
            }

            current.updateStickerHeader(with: sticker.file, size: item.stickerSize, context: item.context, parent: nil, table: item.table, parameters: params, animated: animated, positionFlags: nil, approximateSynchronousValue: false)
        } else {
            if let view = self.animationView {
                performSubviewRemoval(view, animated: animated)
                self.animationView = nil
            }
        }
        
        if let image = item.image {
            
            if let view = self.animationView {
                performSubviewRemoval(view, animated: animated)
                self.animationView = nil
            }
            
            let current: ImageView
            if let view = self.imageView {
                current = view
            } else {
                current = ImageView(frame: item.stickerSize.bounds)
                current.isAccessibilityDecorative = true
                self.imageView = current
                addSubview(current)
            }
            current.image = image
            current.sizeToFit()
        } else {
            if let view = self.imageView {
                performSubviewRemoval(view, animated: animated)
                self.imageView = nil
            }
        }
        
        
        
        
        self.textView.update(item.textLayout)

        if let infoLayout = item.infoLayout {
            let current: TextView
            if let view = self.infoTextView {
                current = view
            } else {
                current = TextView()
                current.isSelectable = false
                current.userInteractionEnabled = true
                self.infoTextView = current
                addSubview(current)
            }
            current.update(infoLayout)
            current.backgroundColor = backdorColor
        } else {
            if let view = self.infoTextView {
                performSubviewRemoval(view, animated: animated)
                self.infoTextView = nil
            }
        }

        if let badge = item.badge {
            let current: ImageView
            if let view = self.badgeView {
                current = view
            } else {
                current = ImageView()
                current.isAccessibilityDecorative = true
                self.badgeView = current
                addSubview(current)
            }
            current.image = badge
            current.sizeToFit()
        } else {
            if let view = self.badgeView {
                performSubviewRemoval(view, animated: animated)
                self.badgeView = nil
            }
        }

        if let bgColor = item.bgColor {
            if self.bgView == nil {
                self.bgView = View()
                self.addSubview(self.bgView!, positioned: .below, relativeTo: self.imageView)
            }
            self.bgView?.backgroundColor = bgColor
            self.bgView?.setFrameSize(item.stickerSize)
            self.bgView?.layer?.cornerRadius = 10
        }

        if let dismiss = item.dismiss {
            let current: ImageButton
            if let view = self.dismissButton {
                current = view
            } else {
                current = ImageButton()
                current.scaleOnClick = true
                current.autohighlight = false
                current.setAccessibilityLabel(strings().voiceOverCommonClose)
                self.dismissButton = current
                addSubview(current)
            }
            current.set(image: theme.icons.glass_close, for: .Normal)
            current.setGlassEffect(size: NSMakeSize(36, 36))
            current.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
            current.removeAllHandlers()
            current.set(handler: { _ in
                dismiss()
            }, for: .Click)
        } else {
            if let view = self.dismissButton {
                performSubviewRemoval(view, animated: animated)
                self.dismissButton = nil
            }
        }

        needsLayout = true
    }
    
    override func layout() {
        super.layout()
        guard let item = item as? AnimatedStickerHeaderItem else { return }

        let imageView = self.imageView ?? self.animationView

        guard let imageView else {
            return
        }

        if item.isFullView {
            imageView.center()
            imageView.setFrameOrigin(NSMakePoint(imageView.frame.minX, imageView.frame.minY - 40))
        } else {
            imageView.centerX(y: 10)
        }

        let textY = imageView.frame.maxY + 10
        if let badgeView = self.badgeView {
            let totalWidth = textView.frame.width + 5 + badgeView.frame.width
            let startX = (containerView.frame.width - totalWidth) / 2
            textView.setFrameOrigin(NSMakePoint(startX, textY))
            badgeView.setFrameOrigin(NSMakePoint(textView.frame.maxX + 5, textY + (textView.frame.height - badgeView.frame.height) / 2 - 1))
        } else {
            self.textView.centerX(y: textY)
        }

        if let infoTextView = self.infoTextView {
            infoTextView.centerX(y: textView.frame.maxY + 10)
        }

        self.bgView?.frame = imageView.frame

        self.dismissButton?.setFrameOrigin(NSMakePoint(0, 10))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
