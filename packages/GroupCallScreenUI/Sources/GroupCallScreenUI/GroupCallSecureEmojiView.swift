import Cocoa
import TelegramCallsCore
import TGUIKit
import SwiftSignalKit
import TelegramCore
import ObjcUtils
import Localization

public final class GroupCallSecureEmojiView: Control {
    
    private class EmojiView : View {
        private(set) var stable: ImageView?
        private var pendingEmojiValues: [CGImage]?
        private var pendingContainerView: View?
        private var pendingEmojiViews: [SimpleLayer] = []
        
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func update(emoji: CGImage?, emojiSize: NSSize, animated: Bool) {

            let prevEmojiSize = self.frame.size
            
            if let emoji {
                let current: ImageView
                let isNew: Bool
                if let view = self.stable {
                    current = view
                    isNew = false
                } else {
                    current = ImageView()
                    current.isAccessibilityDecorative = true
                    addSubview(current)
                    self.stable = current
                    isNew = true
                }
                current.image = emoji
                current.setFrameSize(emojiSize)
                
                if isNew, animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
                
                if let pendingContainerView = self.pendingContainerView {
                    self.pendingContainerView = nil
                    performSubviewRemoval(pendingContainerView, animated: animated)
                    self.pendingEmojiViews.removeAll()
                }
                
            } else {
                
                if let stable = self.stable {
                    self.stable = nil
                    performSubviewRemoval(stable, animated: animated)
                }
                
                let borderEmoji = 2
                let numEmoji = borderEmoji * 2 + 3
                
                if self.pendingEmojiValues?.count != numEmoji {
                    var pendingEmojiValuesValue: [CGImage] = []
                    for _ in 0 ..< numEmoji - borderEmoji - 1 {
                        let emoji = ObjcUtils.randomCallsEmoji()
                        let image = generateTextIcon(.initialize(string: emoji, color: .white, font: .medium(30)), minSize: false)
                        pendingEmojiValuesValue.append(image)
                    }
                    for i in 0 ..< borderEmoji + 1 {
                        pendingEmojiValuesValue.append(pendingEmojiValuesValue[i])
                    }
                    self.pendingEmojiValues = pendingEmojiValuesValue
                }
                
                
                if let pendingEmojiValues, pendingEmojiValues.count == numEmoji {
                    let pendingContainerView: View
                    if let current = self.pendingContainerView {
                        pendingContainerView = current
                    } else {
                        pendingContainerView = View()
                        self.pendingContainerView = pendingContainerView
                    }
                    let size = emojiSize

                    for i in 0 ..< numEmoji {
                        let pendingEmojiView: SimpleLayer
                        if self.pendingEmojiViews.count > i {
                            pendingEmojiView = self.pendingEmojiViews[i]
                        } else {
                            pendingEmojiView = SimpleLayer()
                            self.pendingEmojiViews.append(pendingEmojiView)
                            pendingContainerView.layer?.addSublayer(pendingEmojiView)
                        }
                        pendingEmojiView.contents = pendingEmojiValues[i]
                        pendingEmojiView.frame = CGRect(origin: CGPoint(x: 0.0, y: CGFloat(i) * size.height), size: emojiSize)
                    }

                    pendingContainerView.frame = CGRect(origin: CGPoint(), size: size)

                    if pendingContainerView.superview == nil || emojiSize != prevEmojiSize {
                        self.addSubview(pendingContainerView)

                        let animation = CABasicAnimation(keyPath: "sublayerTransform.translation.y")
                        //animation.duration = 4.2
                        animation.duration = 0.7
                        animation.fromValue = -CGFloat(numEmoji - borderEmoji) * size.height
                        animation.toValue = CGFloat(borderEmoji - 3) * size.height
                        animation.timingFunction = CAMediaTimingFunction(name: .linear)
                        animation.autoreverses = false
                        animation.repeatCount = .infinity
                        
                        pendingContainerView.layer?.add(animation, forKey: "offsetCycle")
                    }
                }
            }
        }
    }
    
    private let textView = TextView()
    private let emojiesView: [EmojiView] = [EmojiView(frame: .zero), EmojiView(frame: .zero), EmojiView(frame: .zero), EmojiView(frame: .zero)]
    
    private var infoTextView: TextView?
    
    private var closeView: TextView?
    private var closeBorderView: View?

    private var glassBackgroundView: NSView?
    private var glassFallbackView: View?


    private var state: GroupCallUIState?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        textView.userInteractionEnabled = false
        textView.isSelectable = false

        for view in emojiesView {
            addSubview(view)
        }

        setupGlassBackground()


        scaleOnClick = true
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func emojiesRects(_ state: GroupCallUIState, width: CGFloat) -> [NSRect] {
        var rects: [CGRect] = []
        if state.showConferenceKey {
            
            let size = NSMakeSize(34, 39)
            
            let between = (width - size.width * 4) / 5.0
            
            var x: CGFloat = between
            for _ in self.emojiesView {
                rects.append(NSMakeRect(x, 10, size.width, size.height))
                x += size.width + between
            }
            
        } else {
            let size = NSMakeSize(21, 22)
            let leftX: CGFloat = 8
            let rightX: CGFloat = width - 8 - size.width * 2
            rects.append(.init(origin: NSMakePoint(leftX, 5), size: size))
            rects.append(.init(origin: NSMakePoint(leftX + size.width, 5), size: size))
            rects.append(.init(origin: NSMakePoint(rightX, 5), size: size))
            rects.append(.init(origin: NSMakePoint(rightX + size.width, 5), size: size))
        }
        return rects
    }
    
    private var isFullScreen: Bool = false

    public func update(_ state: GroupCallUIState, encryptionKeyEmoji: [String]?, _ account: Account, isFullScreen: Bool = false, toggle: @escaping()->Void, transition: ContainedViewLayoutTransition) -> NSSize {

        let animated = transition.isAnimated
        self.state = state
        self.isFullScreen = isFullScreen

        let titleString = isFullScreen ? strings().groupCallEndToEndTitleShort : strings().groupCallEndToEndTitle
        let textLayout = TextViewLayout(.initialize(string: titleString, color: .white, font: .normal(.text)), alignment: .center)
        textLayout.measure(width: .greatestFiniteMagnitude)
        self.textView.update(textLayout)
        self.textView.isAccessibilityDecorative = true


        background = .clear


        setSingle(handler: { _ in
            toggle()
        }, for: .Click)

        let views = self.emojiesView

        var width = (isFullScreen && !state.showConferenceKey) ? GroupCallTheme.tileTableWidth : textView.frame.width + 84 + 10 + 10
        if state.showConferenceKey {
            width = floor(width * 1.2)
        }
        let emojiRects = emojiesRects(state, width: width)

        for (i, view) in views.enumerated() {
            var image: CGImage? = nil
            if let encryptionKeyEmoji {
                let emoji = encryptionKeyEmoji[i]
                image = generateTextIcon(.initialize(string: emoji, color: .white, font: .medium(30)), minSize: false)
            }
            let isNew: Bool = view.stable == nil
            
            view.update(emoji: image, emojiSize: emojiRects[i].size, animated: animated)
                                    
            if isNew {
                view.frame = emojiRects[i]
            } else {
                transition.updateFrame(view: view, frame: emojiRects[i])
            }
        }
        
        
        self.textView.change(opacity: state.showConferenceKey ? 0 : 1, animated: animated)
        
        if state.showConferenceKey {
            let current: TextView
            let isNew: Bool
            if let view = self.infoTextView {
                current = view
                isNew = false
            } else {
                current = TextView()
                current.userInteractionEnabled = false
                current.isSelectable = false
                self.infoTextView = current
                addSubview(current)
                isNew = true
            }
            
            let layout = TextViewLayout(.initialize(string: "These four emojis represent the call's encryption key. They must match for all participants and change when someone joins or leaves.", color: .white, font: .normal(.text)))
            layout.measure(width: width - 20)
            
            current.update(layout)
            
            if isNew {
                current.centerX(y: 50)
            }
            
        } else if let view = self.infoTextView {
            performSubviewRemoval(view, animated: animated)
            self.infoTextView = nil
        }
        let emojiText = (encryptionKeyEmoji ?? []).joined(separator: " ")
        if let info = infoTextView?.textLayout?.attributedString.string {
            infoTextView?.isAccessibilityDecorative = true
            self.setAccessibilityLabel([emojiText, info, strings().navigationClose].filter { !$0.isEmpty }.joined(separator: ". "))
        } else {
            self.setAccessibilityLabel(([titleString] + (encryptionKeyEmoji ?? [])).joined(separator: " "))
        }
        
        if state.showConferenceKey, let infoTextView {
            let current: TextView
            let isNew: Bool
            if let view = self.closeView {
                current = view
                isNew = false
            } else {
                current = TextView()
                current.userInteractionEnabled = false
                current.isSelectable = false
                self.closeView = current
                addSubview(current)
                isNew = true
            }
            
            let layout = TextViewLayout(.initialize(string: strings().navigationClose, color: .white, font: .normal(.title)), alignment: .center)
            layout.measure(width: width - 20)
            current.update(layout)
            current.setFrameSize(NSMakeSize(width, 40))

            if isNew {
                current.centerX(y: infoTextView.frame.maxY + 10)
            }
            
        } else if let view = self.closeView {
            performSubviewRemoval(view, animated: animated)
            self.closeView = nil
        }
        
        if state.showConferenceKey, let infoTextView {
            let current: View
            let isNew: Bool
            if let view = self.closeBorderView {
                current = view
                isNew = false
            } else {
                current = View()
                self.closeBorderView = current
                addSubview(current)
                isNew = true
            }
            
            current.backgroundColor = NSColor.white.withAlphaComponent(0.15)
            current.setFrameSize(NSMakeSize(width, .borderSize))
            
            if isNew {
                current.centerX(y: infoTextView.frame.maxY + 10)
            }
            
        } else if let view = self.closeBorderView {
            performSubviewRemoval(view, animated: animated)
            self.closeBorderView = nil
        }
        
        
        

        if let infoTextView {
            return NSMakeSize(width, 30 + infoTextView.frame.height + 50 + 10 + 10)
        } else {
            return NSMakeSize(width, 30)
        }
        
    }
    
    private func setupGlassBackground() {
        let contentViews = subviews.first

        let fallback = View(frame: bounds)
        fallback.wantsLayer = true
        fallback.layer?.cornerRadius = 15
        fallback.background = GroupCallTheme.membersColor
        addSubview(fallback, positioned: .below, relativeTo: contentViews)
        glassFallbackView = fallback

        let glass = LiquidGlassView(frame: NSZeroRect, cornerRadius: 15, hasShadow: true, hasBorder: true, forceAppearance: .forceDark)
        addSubview(glass, positioned: .above, relativeTo: fallback)
        glassBackgroundView = glass

        self.stretchReferenceView = glass
    }

    public override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
        
    
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        if let glassFallbackView {
            transition.updateFrame(view: glassFallbackView, frame: bounds)
        }
        if let glassBackgroundView {
            transition.updateFrame(view: glassBackgroundView, frame: bounds)
            (glassBackgroundView as? LiquidGlassView)?.updateLayout(size: bounds.size, transition: transition)
        }
        transition.updateFrame(view: textView, frame: textView.centerFrameX(y: 7))

        guard let state else {
            return
        }
        
        let views = self.emojiesView
        let rects = self.emojiesRects(state, width: size.width)
        for (i, view) in views.enumerated() {
            transition.updateFrame(view: view, frame: rects[i])
        }
        
        if let view = self.infoTextView {
            transition.updateFrame(view: view, frame: view.centerFrameX(y: 50))
        }
        if let view = self.closeView {
            transition.updateFrame(view: view, frame: view.centerFrameX(y: size.height - view.frame.height))
        }
        if let view = self.closeBorderView {
            transition.updateFrame(view: view, frame: view.centerFrameX(y: size.height - 40))
        }
    }
}
