import AppKit
import TGUIKit
import GeneralRows
import TelegramTheme
import Localization
@testable import PeerInfoUI

final class LegacyTextAndLabelRowView: GeneralRowView {
    private let containerView = GeneralRowContainerView(frame: NSZeroRect)
    private var labelView:InteractiveTextView = InteractiveTextView()
    private let moreView: TextView = TextView()
    private var descView: TextView?
    private let shadowView = ShadowView()

    private let copyView: ImageButton = ImageButton()
    private let toggleVisibility = ImageButton()
    override func draw(_ layer: CALayer, in ctx: CGContext) {
        
        if let item = item as? TextAndLabelItem, let label = item.labelLayout, layer == containerView.layer {
            switch item.viewType {
            case .legacy:
                label.1.draw(NSMakeRect(item.inset.left, item.labelY, label.0.size.width, label.0.size.height), in: ctx, backingScaleFactor: backingScaleFactor, backgroundColor: backdorColor)
                if item.drawCustomSeparator {
                    ctx.setFillColor(item.borderColor.cgColor)
                    ctx.fill(NSMakeRect(item.inset.left, frame.height - .borderSize, frame.width - item.inset.left - item.inset.right, .borderSize))
                }
            case let .modern(position, insets):
                label.1.draw(NSMakeRect(insets.left, item.labelY, label.0.size.width, label.0.size.height), in: ctx, backingScaleFactor: backingScaleFactor, backgroundColor: backdorColor)
                if position.border {
                    ctx.setFillColor(item.borderColor.cgColor)
                    ctx.fill(NSMakeRect(insets.left, self.containerView.frame.height - .borderSize, self.containerView.frame.width - insets.left - insets.right, .borderSize))
                }
            }
        }
        
    }
    
    
    
    override var backdorColor: NSColor {
        if let item = item as? TextAndLabelItem {
            return item.backgroundColor
        } else {
            return theme.colors.background
        }
    }
    override func updateColors() {
        if let item = item as? TextAndLabelItem {
            self.labelView.backgroundColor = backdorColor
            self.containerView.backgroundColor = backdorColor
            self.background = item.viewType.rowBackground
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if mouseInside() {
            if let item = item as? TextAndLabelItem {
                item.action()
            }
        } else {
            super.mouseUp(with: event)
        }
    }
    
    private var launchAppButton: TextButton?
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        containerView.addSubview(labelView)
        containerView.addSubview(toggleVisibility)
        
        toggleVisibility.scaleOnClick = true
        toggleVisibility.autohighlight = false
        
        self.addSubview(self.containerView)
        self.containerView.displayDelegate = self
        self.containerView.userInteractionEnabled = false
        containerView.addSubview(shadowView)
        containerView.addSubview(moreView)
        

        
        labelView.set(handler: { [weak self] _ in
            if let item = self?.item as? TextAndLabelItem {
                item.action()
            }
        }, for: .Click)
        
        copyView.autohighlight = false
        copyView.scaleOnClick = true
        
        copyView.set(handler: { [weak self] _ in
            if let item = self?.item as? TextAndLabelItem {
                if let gift = item.gift {
                    gift()
                } else {
                    item._copyToClipboard?()
                }
            }
        }, for: .Click)
        
        toggleVisibility.set(handler: { [weak self] _ in
            if let item = self?.item as? TextAndLabelItem {
                item.toggleHide?()
            }
        }, for: .Click)
        
        containerView.addSubview(copyView)
    }
    
    override func layout() {
        super.layout()
        if let item = item as? TextAndLabelItem {
            switch item.viewType {
            case .legacy:
                self.containerView.frame = bounds

                if let _ = item.labelLayout {
                    labelView.setFrameOrigin(item.inset.left, item.textY)
                } else {
                    labelView.centerY(x:item.inset.left)
                }
                
                if let label = item.labelLayout {
                    toggleVisibility.setFrameOrigin(NSMakePoint(item.inset.left + label.0.size.width + 3, item.labelY))
                }
                copyView.centerY(x: containerView.frame.width - copyView.frame.width - item.inset.left)
            case let .modern(_, innerInsets):
                self.containerView.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - item.blockWidth) / 2), item.inset.top, item.blockWidth, frame.height - item.inset.bottom - item.inset.top)

                if let _ = item.labelLayout {
                    labelView.setFrameOrigin(innerInsets.left, item.textY)
                } else {
                    labelView.centerY(x: innerInsets.left)
                }
                
                if let label = item.labelLayout {
                    toggleVisibility.setFrameOrigin(NSMakePoint(innerInsets.left + label.0.size.width + 3, item.labelY))
                }
                
                copyView.centerY(x: containerView.frame.width - copyView.frame.width - innerInsets.right)

                moreView.setFrameOrigin(NSMakePoint(containerView.frame.width - moreView.frame.width - innerInsets.right, containerView.frame.height - innerInsets.bottom - moreView.frame.height + 3))
                shadowView.frame = NSMakeRect(containerView.frame.width - 100 - innerInsets.right, self.containerView.frame.height - 20 - innerInsets.bottom + 3, 120, 20)
                
                if let descView {
                    descView.setFrameOrigin(NSMakePoint(containerView.frame.width - descView.frame.width - innerInsets.right, innerInsets.top))
                }

            }
            self.containerView.setCorners(item.viewType.corners)

            if let launchAppButton {
                launchAppButton.frame = NSMakeRect(10, containerView.frame.height - launchAppButton.frame.height - 10, containerView.frame.size.width - 20, 40)
            }
        }
        
    }
    
    
    override func set(item:TableRowItem, animated:Bool = false) {
        super.set(item: item, animated: animated)
        
        if let item = item as? TextAndLabelItem {
            
            shadowView.shadowBackground = theme.colors.background
            shadowView.direction = .horizontal(true)

            
            labelView.userInteractionEnabled = item.canCopy
            labelView.textView.userInteractionEnabled = item.canCopy
            labelView.textView.isSelectable = item.isTextSelectable
            labelView.set(text: item.textLayout, context: item.context)
            
            shadowView.isHidden = item.hasMore != true
            moreView.isHidden = item.hasMore != true
            moreView.update(item.moreLayout)
            moreView.setFrameSize(NSMakeSize(item.moreLayout.layoutSize.width + 10, item.moreLayout.layoutSize.height))
            moreView.background = theme.colors.background
            
            copyView.set(image: TelegramThemeHooks.shared.image(item.gift != nil ? .iconGiftBirthday : .iconFastCopyLink).precomposed(item.accentColor), for: .Normal)
            copyView.sizeToFit()
            copyView.scaleOnClick = true
            copyView.isHidden = item._copyToClipboard == nil && item.gift == nil
            toggleVisibility.isHidden = item.hideText == nil
            
            if let hideText = item.hideText {
                toggleVisibility.set(image: TelegramThemeHooks.shared.image(hideText ? .iconEyeOn : .iconEyeOff).precomposed(item.accentColor), for: .Normal)
                toggleVisibility.sizeToFit()
            }
            
            
            if let _ = item.launchApp {
                let current: TextButton
                if let view = self.launchAppButton {
                    current = view
                } else {
                    current = TextButton()
                    current.layer?.cornerRadius = 10
                    current.scaleOnClick = true
                    self.launchAppButton = current
                    containerView.addSubview(current)
                }
                current.removeAllHandlers()
                current.set(handler: { [weak item] _ in
                    item?.launchApp?()
                }, for: .Click)
                current.set(text: strings().botInfoOpenApp, for: .Normal)
                current.set(font: .medium(.text), for: .Normal)
                current.set(background: theme.colors.accent, for: .Normal)
                current.set(color: theme.colors.underSelectedColor, for: .Normal)
                current.setFrameSize(NSMakeSize(item.blockWidth - 40, 40))
            } else if let view = self.launchAppButton {
                performSubviewRemoval(view, animated: animated)
                self.launchAppButton = nil
            }
            
            if let descriptionLayout = item.descriptionLayout {
                let current: TextView
                if let view = self.descView {
                    current = view
                } else {
                    current = TextView()
                    self.descView = current
                    current.userInteractionEnabled = false
                    current.isSelectable = false
                    containerView.addSubview(current)
                }
                current.update(descriptionLayout)
            } else if let descView {
                performSubviewRemoval(descView, animated: animated)
                self.descView = nil
            }
        }
        containerView.needsDisplay = true
        needsLayout = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
}
