import Cocoa
import TGUIKit
import TelegramCore
import Localization
import TelegramContext
import TelegramMediaUtils
import TelegramUtils
import InlineStickerLayer



public class WPContentView: Control, MultipleSelectable, ModalPreviewRowViewProtocol {
    
    
    public func fileAtPoint(_ point: NSPoint) -> (QuickPreviewMedia, NSView?)? {
        return nil
    }
    
    public var header: String? {
        return nil
    }

    private let dashLayer = DashLayer()
    
    public var textView:TextView = TextView()
    private var inlineStickerItemViews: [InlineStickerItemLayer.Key: InlineStickerItemLayer] = [:]

    private var patternContentLayers: [SimpleLayer] = []
    private var patternTarget: InlineStickerItemLayer?

    
    public private(set) var containerView:View = View()
    public private(set) var content:WPLayout?
    private var action: TextButton? = nil
    
    
    public var whatThisView: TextView?
    
    public var selectableTextViews: [TextView] {
        return []
    }
    
    public func previewMediaIfPossible() -> Bool {
        return false
    }
    

    public override func layout() {
        super.layout()
        if let content = self.content {
            containerView.frame = content.contentRect
            textView.isHidden = content.textLayout == nil
            
            if content.isLeadingMedia {
                textView.setFrameOrigin(NSMakePoint(0, content.contentRect.height - textView.frame.height - (action != nil ? 36 : 0)))
            } else {
                textView.setFrameOrigin(.zero)
            }
            
            if let current = self.whatThisView, let line = textView.textLayout?.lines.first {
                current.setFrameOrigin(NSMakePoint(line.frame.maxX + 5, textView.frame.minY + 1))
            }
            if let action = action {
                _ = action.sizeToFit(NSZeroSize, NSMakeSize(content.contentRect.width, 36), thatFit: true)
                action.setFrameOrigin(0, content.contentRect.height - action.frame.height + content.imageInsets.top * 2)
            }
        }
        dashLayer.frame = NSMakeRect(0, 0, 3, frame.height)
        needsDisplay = true
    }
    
    public func convertWindowPointToContent(_ point: NSPoint) -> NSPoint {
        return convert(point, from: nil)
    }
    
    required public override convenience init() {
        self.init(frame: .zero)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        
        self.isDynamicColorUpdateLocked = true
        
        textView.isSelectable = false
        textView.userInteractionEnabled = false
        
        super.addSubview(containerView)
        self.layer?.addSublayer(dashLayer)
        addSubview(textView)
        
        
        
        layer?.cornerRadius = .cornerRadius
        
        set(handler: { [weak self] _ in
            self?.content?.invokeAction(morphSource: { [weak self] in self })
        }, for: .Down)
    }
    
    public override func addSubview(_ view: NSView) {
        containerView.addSubview(view)
    }
    
    deinit {
        containerView.removeAllSubviews()
    }
    
    public func updateMouse() {
        
    }

    public func update(with layout:WPLayout, animated: Bool) -> Void {
        self.content = layout
        
        self.scaleOnClick = layout.content.type != "edited"

        
        textView.update(layout.textLayout)
        
        if let text = layout.action_text {
            let current: TextButton
            if let view = self.action {
                current = view
            } else {
                current = TextButton()
                self.action = current
                current.disableActions()
                addSubview(current)
                current.userInteractionEnabled = false
                
            }

            current.border = [.Top]
            current.borderColor = layout.presentation.activity.main.withAlphaComponent(0.1)
            current.set(color: layout.presentation.activity.main, for: .Normal)
            current.set(font: .medium(.title), for: .Normal)
            current.set(background: .clear, for: .Normal)
            current.set(text: text, for: .Normal)
            _ = current.sizeToFit(NSZeroSize, NSMakeSize(layout.contentRect.width, 36), thatFit: false)
            
            current.set(color: layout.presentation.activity.main, for: .Normal)
            if layout.hasInstantPage {
                current.set(image: NSImage.init(named: "Icon_ChatIV")!.precomposed(layout.presentation.activity.main), for: .Normal)
            } else {
                current.removeImage(for: .Normal)
            }
        } else if let view = self.action {
            performSubviewRemoval(view, animated: animated)
            self.action = nil
        }
        
      
        
        if layout.presentation.pattern != nil {
            var maxIndex = 0
            
            struct Placement {
                var position: CGPoint
                var size: CGFloat
                
                init(_ position: CGPoint, _ size: CGFloat) {
                    self.position = position
                    self.size = size
                }
            }
            
            let placements: [Placement] = [
                Placement(CGPoint(x: 176.0, y: 13.0), 38.0),
                Placement(CGPoint(x: 51.0, y: 45.0), 58.0),
                Placement(CGPoint(x: 349.0, y: 36.0), 58.0),
                Placement(CGPoint(x: 132.0, y: 64.0), 46.0),
                Placement(CGPoint(x: 241.0, y: 64.0), 54.0),
                Placement(CGPoint(x: 68.0, y: 121.0), 44.0),
                Placement(CGPoint(x: 178.0, y: 122.0), 47.0),
                Placement(CGPoint(x: 315.0, y: 122.0), 47.0),
            ]
            
            for placement in placements {
                let patternContentLayer: SimpleLayer
                if maxIndex < self.patternContentLayers.count {
                    patternContentLayer = self.patternContentLayers[maxIndex]
                } else {
                    patternContentLayer = SimpleLayer()
                    patternContentLayer.layerTintColor = layout.presentation.activity.main.cgColor
                    self.layer?.addSublayer(patternContentLayer)
                    self.patternContentLayers.append(patternContentLayer)
                }
               // patternContentLayer.contents = patternTarget?.contents // self.patternContentsTarget?.contents
                
                var start = NSMakePoint(layout.size.width, 0)
                
                if let article = layout as? WPArticleLayout {
                    if let arguments = article.imageArguments {
                        if !article.isFullImageSize {
                            start.x -= (arguments.boundingSize.width + 5)
                        }
                    }
                    
                }
                
                let itemSize = CGSize(width: placement.size / 3.0, height: placement.size / 3.0)
                patternContentLayer.frame = CGRect(origin: CGPoint(x: start.x - placement.position.x / 3.0 - itemSize.width * 0.5, y: start.y + placement.position.y / 3.0 - itemSize.height * 0.5), size: itemSize)
                
                var alphaFraction = abs(placement.position.x) / 400.0
                alphaFraction = min(1.0, max(0.0, alphaFraction))
                patternContentLayer.opacity = 0.3 * Float(1.0 - alphaFraction)
                
                maxIndex += 1
            }
            
            if maxIndex < self.patternContentLayers.count {
                for i in maxIndex ..< self.patternContentLayers.count {
                    self.patternContentLayers[i].removeFromSuperlayer()
                }
                self.patternContentLayers.removeSubrange(maxIndex ..< self.patternContentLayers.count)
            }
        } else {
            for patternContentLayer in self.patternContentLayers {
                patternContentLayer.removeFromSuperlayer()
            }
            self.patternContentLayers.removeAll()
        }
        
        if let pattern = layout.presentation.pattern, layout.content.type != "edited" {
            if patternTarget?.textColor != layout.presentation.activity.main || patternTarget?.fileId != pattern {
                patternTarget = .init(account: layout.context.account, inlinePacksContext: layout.context.inlinePacksContext, emoji: .init(fileId: pattern, file: nil, emoji: ""), size: NSMakeSize(64, 64), playPolicy: .framesCount(1), textColor: layout.presentation.activity.main, contentDidUpdate: { [weak self] contents in
                    self?.updatePatternLayerImages(contents)
                })
                patternTarget?.superview = self
                patternTarget?.noDelayBeforeplay = true
                patternTarget?.isPlayable = true
            }
        } else {
            patternTarget = nil
            self.updatePatternLayerImages()
        }
        
        if let ad = layout.parent.adAttribute, ad.canReport {
            let current: TextView
            if let view = self.whatThisView {
                current = view
            } else {
                current = TextView()
                current.scaleOnClick = true
                current.isSelectable = false
                self.whatThisView = current
                addSubview(current)
            }
            
            current.removeAllHandlers()
            current.set(handler: { [weak current] _ in
                showModal(with: ChatHistoryUIHooks.shared.makeFragmentAdsInfoController(layout.context, layout.parent, layout.chatInteraction), for: layout.context.window, morphSource: { current })
            }, for: .Click)
            
            let text = TextViewLayout(.initialize(string: strings().chatAdWhatThis, color: layout.presentation.activity.main, font: .normal(.small)), alignment: .center)
            text.measure(width: .greatestFiniteMagnitude)
            current.update(text)
            current.setFrameSize(NSMakeSize(text.layoutSize.width + 6, text.layoutSize.height + 2))
            current.layer?.cornerRadius = current.frame.height / 2
            current.backgroundColor = layout.presentation.activity.main.withAlphaComponent(0.2)
        } else if let view = whatThisView {
            performSubviewRemoval(view, animated: animated)
            self.whatThisView = nil
        }
        
        self.backgroundColor = layout.presentation.activity.main.withAlphaComponent(0.1) //color
        self.needsLayout = true
        
        self.dashLayer.colors = layout.presentation.activity
        
        if let textLayout = layout.textLayout {
            updateInlineStickers(context: layout.context, view: self.textView, textLayout: textLayout)
        }
    }
    
    private func updatePatternLayerImages(_ image: CGImage? = nil) {
        for patternContentLayer in self.patternContentLayers {
            patternContentLayer.contents = image
        }
    }
    
    public func interactionContentView(for innerId: AnyHashable, animateIn: Bool ) -> NSView {
        return self.containerView
    }
    
    public var mediaContentView: NSView? {
        return containerView
    }
    
    @objc public func updateAnimatableContent() -> Void {
        for (_, value) in inlineStickerItemViews {
            if let superview = value.superview {
                var isKeyWindow: Bool = false
                if let window = self.window {
                    if !window.canBecomeKey {
                        isKeyWindow = true
                    } else {
                        isKeyWindow = window.isKeyWindow
                    }
                }
                value.isPlayable = NSIntersectsRect(value.frame, superview.visibleRect) && isKeyWindow && !isEmojiLite
            }
        }
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.updateListeners()
        self.updateAnimatableContent()
    }
    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        self.updateListeners()
        self.updateAnimatableContent()
    }
    
    private let animatableContentObserver = AnimatableContentObserver()

    private func updateListeners() {
        animatableContentObserver.update(for: self, target: self, selector: #selector(updateAnimatableContent), options: [.contentBounds, .documentFrame, .ownFrame])
    }
    
    
    public var isEmojiLite: Bool {
        if let layout = self.content {
            return layout.context.isLite(.emoji)
        }
        return false
    }
    
    public func updateInlineStickers(context: any AccountContextProtocol, view textView: TextView, textLayout: TextViewLayout) {
        
        guard let content = self.content else {
            return
        }
        
        let textColor = content.presentation.text
        
        var validIds: [InlineStickerItemLayer.Key] = []
        var index: Int = textView.hashValue
        
        for item in textLayout.embeddedItems {
            if let stickerItem = item.value as? InlineStickerItem, case let .attribute(emoji) = stickerItem.source {
                
                let id = InlineStickerItemLayer.Key(id: emoji.fileId, index: index, color: textColor)
                validIds.append(id)
                
                
                let rect: NSRect
                if textLayout.isBigEmoji {
                    rect = item.rect
                } else {
                    rect = item.rect
                }
                
                let view: InlineStickerItemLayer
                if let current = self.inlineStickerItemViews[id], current.frame.size == rect.size, textColor == current.textColor {
                    view = current
                } else {
                    self.inlineStickerItemViews[id]?.removeFromSuperlayer()
                    view = InlineStickerItemLayer(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: emoji, size: rect.size, textColor: textColor)
                    self.inlineStickerItemViews[id] = view
                    view.superview = textView
                    textView.addEmbeddedLayer(view)
                }
                index += 1
                var isKeyWindow: Bool = false
                if let window = window {
                    if !window.canBecomeKey {
                        isKeyWindow = true
                    } else {
                        isKeyWindow = window.isKeyWindow
                    }
                }
                view.isPlayable = NSIntersectsRect(rect, textView.visibleRect) && isKeyWindow
                view.frame = rect
            }
        }
        
        var removeKeys: [InlineStickerItemLayer.Key] = []
        for (key, itemLayer) in self.inlineStickerItemViews {
            if !validIds.contains(key) {
                removeKeys.append(key)
                itemLayer.removeFromSuperlayer()
            }
        }
        for key in removeKeys {
            self.inlineStickerItemViews.removeValue(forKey: key)
        }
        updateAnimatableContent()
    }


}
