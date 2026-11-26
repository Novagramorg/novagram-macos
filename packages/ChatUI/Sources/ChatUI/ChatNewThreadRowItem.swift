import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import ChatHistoryModel
import GeneralRows
import TelegramContext
import TelegramTheme

public final class ChatNewThreadRowItem : GeneralRowItem {
    fileprivate let entry: ChatHistoryEntry
    fileprivate let chatInteraction: ChatInteraction
    fileprivate let presentation: TelegramPresentationTheme
    fileprivate let title: TextViewLayout
    fileprivate let info: TextViewLayout
    
    public init(_ initialSize: NSSize, entry: ChatHistoryEntry, chatInteraction: ChatInteraction, presentation: TelegramPresentationTheme) {
        self.entry = entry
        self.presentation = presentation
        self.chatInteraction = chatInteraction
        
        
        self.title = .init(.initialize(string: "New Thread", color: presentation.chatServiceItemTextColor, font: .medium(.title)))
        self.title.measure(width: 180)
        
        self.info = .init(.initialize(string: "Type any message to create a new thread.", color: presentation.chatServiceItemTextColor, font: .normal(.text)), alignment: .center)
        self.info.measure(width: 180)
        
        super.init(initialSize, stableId: entry.stableId)
    }
    
    public override var height: CGFloat {
        return 10 + 80 + 10 + title.layoutSize.height + 10 + info.layoutSize.height + 20 + 10 + 20
    }
    
    public var itemSize: NSSize {
        return NSMakeSize(200, height - 10)
    }
    
    public var shouldBlurService: Bool {
        if chatInteraction.interactionContext.isLite(.blur) {
            return false
        }
        return presentation.shouldBlurService
    }
    
    public override func viewClass() -> AnyClass {
        return ChatNewThreadRowView.self
    }

    public override var accessibilityLabel: String? {
        return title.attributedString.string
    }

    public override var accessibilityValue: String? {
        return info.attributedString.string
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }
}


private final class ChatNewThreadRowView: TableRowView {
    
    private class ItemView : Control {
        

        private let disposable = MetaDisposable()
        private let photo: ImageView = ImageView()
        
        private var visualEffect: VisualEffect?
        
        private let textView = TextView()
        private let infoView = TextView()
        private let chevron = ImageView()
                
        
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(textView)
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            
            addSubview(infoView)
            infoView.userInteractionEnabled = false
            infoView.isSelectable = false
            
            addSubview(photo)
            addSubview(chevron)
            photo.isAccessibilityDecorative = true
            chevron.isAccessibilityDecorative = true
            
            layer?.cornerRadius = 10
        }
        
        
        func update(item: ChatNewThreadRowItem, animated: Bool) {
            
            _ = NSMakeSize(100, 100)
            
            if item.shouldBlurService {
                let current: VisualEffect
                if let view = self.visualEffect {
                    current = view
                } else {
                    current = VisualEffect(frame: bounds)
                    self.visualEffect = current
                    addSubview(current, positioned: .below, relativeTo: self.subviews.first)
                }
                current.bgColor = item.presentation.blurServiceColor
                
                self.backgroundColor = .clear
                
            } else if let view = visualEffect {
                performSubviewRemoval(view, animated: animated)
                self.visualEffect = nil
                self.backgroundColor = item.presentation.chatServiceItemColor
            }
                        
            textView.update(item.title)
            infoView.update(item.info)

            photo.image = generateImage(NSMakeSize(80, 80), contextGenerator: { size, ctx in
                ctx.clear(size.bounds)
                let image = TelegramThemeHooks.shared.image(.iconNewThreadLarge).precomposed(item.presentation.chatServiceItemTextColor)
                ctx.setFillColor(item.presentation.chatServiceItemTextColor.withAlphaComponent(0.1).cgColor)
                ctx.fillEllipse(in: size.bounds)
                ctx.draw(image, in: size.bounds.focus(image.backingSize))
            })
            photo.sizeToFit()
            
            chevron.image = TelegramThemeHooks.shared.image(.iconSmallChevronDown).precomposed(item.presentation.chatServiceItemTextColor)
            chevron.sizeToFit()
            
            needsLayout = true
        }
        
        
        override func layout() {
            super.layout()
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }
        
        func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            if let visualEffect = visualEffect {
                transition.updateFrame(view: visualEffect, frame: NSRect(origin: .zero, size: size))
            }

            transition.updateFrame(view: photo, frame: photo.centerFrameX(y: 15))

            transition.updateFrame(view: textView, frame: textView.centerFrameX(y: photo.frame.maxY + 10)) // 110 + 10
            transition.updateFrame(view: infoView, frame: infoView.centerFrameX(y: textView.frame.maxY + 10)) // 110 + 10

            
            transition.updateFrame(view: chevron, frame: chevron.centerFrameX(y: infoView.frame.maxY + 10))
        }

        
        deinit {
            disposable.dispose()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    
    private let itemView = ItemView(frame: NSMakeRect(0, 0, 240, 100))
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(itemView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? ChatNewThreadRowItem else {
            return
        }
        itemView.update(item: item, animated: animated)
        itemView.setFrameSize(item.itemSize)
        
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate
        updateLayout(size: frame.size, transition: transition)
    }
    
    
    override var backdorColor: NSColor {
        return .clear
    }
    
    override func layout() {
        super.layout()
        
        self.updateLayout(size: frame.size, transition: .immediate)
    }
    
    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        guard let item = item as? ChatNewThreadRowItem else {
            return
        }
        
        let offset: CGFloat = item.entry.additionalData.monoforumState == .vertical ? 40 : 0

        transition.updateFrame(view: itemView, frame: itemView.centerFrame().offsetBy(dx: offset, dy: 0))
    }
}
