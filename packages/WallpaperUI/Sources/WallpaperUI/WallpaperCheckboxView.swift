import Cocoa
import TGUIKit
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import GeneralRows
import InputDataUI
import AlertsUI
import LocalAnimations
import TelegramIconsTheme

private final class BlurCheckbox : View {
    
    public var isFullFilled: Bool = false {
        didSet {
            needsDisplay = true
        }
    }
    
    private(set) var isSelected: Bool = false
    private var animator: DisplayLinkAnimator?
    public func set(isSelected: Bool, animated: Bool) {
        self.isSelected = isSelected
        if animated {
            animator = DisplayLinkAnimator(duration: 0.2, from: animationProgress, to: isSelected ? 1.0 : 0.0, timingFunction: CAMediaTimingFunction(name: .linear), update: { [weak self] value in
                self?.animationProgress = value
            }, completion: { [weak self] in
                self?.animator = nil
            })
        } else {
            animator = nil
            animationProgress = isSelected ? 1.0 : 0.0
        }
    }
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
    }
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var animationProgress: CGFloat = 0.0 {
        didSet {
            needsDisplay = true
        }
    }
    
    public override func draw(_ layer: CALayer, in context: CGContext) {
        super.draw(layer, in: context)
        
        context.round(frame.size, frame.height / 2)
        
        let borderWidth: CGFloat = 2.0
        
        context.setStrokeColor(.white)
        context.setLineWidth(borderWidth)
        context.strokeEllipse(in: bounds.insetBy(dx: borderWidth / 2.0, dy: borderWidth / 2.0))
        
        let progress: CGFloat = animationProgress
        let diameter = bounds.width
        let center = CGPoint(x: diameter / 2.0, y: diameter / 2.0)

        
        context.setFillColor(.white)
        context.fillEllipse(in: bounds.insetBy(dx: (diameter - borderWidth) * (1.0 - animationProgress), dy: (diameter - borderWidth) * (1.0 - animationProgress)))
        if !isFullFilled {
            let firstSegment: CGFloat = max(0.0, min(1.0, progress * 3.0))
            let s = CGPoint(x: center.x - 4.0, y: center.y + 1.0)
            let p1 = CGPoint(x: 3.0, y: 3.0)
            let p2 = CGPoint(x: 5.0, y: -6.0)
            
            if !firstSegment.isZero {
                if firstSegment < 1.0 {
                    context.move(to: CGPoint(x: s.x + p1.x * firstSegment, y: s.y + p1.y * firstSegment))
                    context.addLine(to: s)
                } else {
                    let secondSegment = (progress - 0.33) * 1.5
                    context.move(to: CGPoint(x: s.x + p1.x + p2.x * secondSegment, y: s.y + p1.y + p2.y * secondSegment))
                    context.addLine(to: CGPoint(x: s.x + p1.x, y: s.y + p1.y))
                    context.addLine(to: s)
                }
            }
            

            context.setBlendMode(.clear)
            context.setLineWidth(borderWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setMiterLimit(10.0)
            
            
            context.strokePath()
        }
        
    }
}


public final class WallpaperCheckboxView : Control {
    
    public final class ColorsListView : View {
        
        var colors:[NSColor] = [] {
            didSet {
                needsDisplay = true
            }
        }
        
        public override func draw(_ layer: CALayer, in ctx: CGContext) {
            super.draw(layer, in: ctx)
            
            ctx.round(frame.size, frame.height / 2)
            
            if colors.count == 1 {
                ctx.setFillColor(colors[0].cgColor)
                ctx.fill(bounds)
            } else if colors.count == 2 {
                ctx.setFillColor(colors[0].cgColor)
                ctx.fill(NSMakeRect(0, 0, frame.width / 2, frame.height))
                ctx.setFillColor(colors[1].cgColor)
                ctx.fill(NSMakeRect(frame.width / 2, 0, frame.width / 2, frame.height))
            } else if colors.count == 3 {
            
                ctx.setFillColor(colors[2].cgColor)
                ctx.fill(bounds)
                
                ctx.setFillColor(colors[0].cgColor)
                var path = CGMutablePath()
                path.move(to: NSMakePoint(0, 0))
                path.addLine(to: CGPoint(x: frame.width / 2, y: 0))
                path.addLine(to: CGPoint(x: frame.width / 2, y: frame.height / 2))
                path.addLine(to: CGPoint(x: 0, y: frame.height * 0.8))
                ctx.addPath(path)
                ctx.fillPath()
                
                ctx.setFillColor(colors[1].cgColor)
                path = CGMutablePath()
                path.move(to: NSMakePoint(frame.width, 0))
                path.addLine(to: NSMakePoint(frame.width / 2, 0))
                path.addLine(to: CGPoint(x: frame.width / 2, y: frame.height / 2))
                path.addLine(to: CGPoint(x: frame.width, y: frame.height * 0.8))
                ctx.addPath(path)
                ctx.fillPath()
                
                
            } else if colors.count == 4 {
                ctx.setFillColor(colors[0].cgColor)
                ctx.fill(NSMakeRect(0, 0, frame.width / 2, frame.height / 2))
                
                ctx.setFillColor(colors[1].cgColor)
                ctx.fill(NSMakeRect(frame.width / 2, 0, frame.width / 2, frame.height / 2))
                
                ctx.setFillColor(colors[2].cgColor)
                ctx.fill(NSMakeRect(0, frame.height / 2, frame.width / 2, frame.height / 2))
                
                ctx.setFillColor(colors[3].cgColor)
                ctx.fill(NSMakeRect(frame.width / 2, frame.height / 2, frame.width / 2, frame.height / 2))

            }
        }
    }
    
    private let title: TextViewLayout
    private let titleView = TextView()
    fileprivate let checkbox: BlurCheckbox = BlurCheckbox(frame: NSMakeRect(0, 0, 16, 16))
    private var glassView: LiquidGlassView?

    private var _isSelected: Bool = false
    public override var isSelected: Bool {
        get {
            return _isSelected
        }
        set {
            _isSelected = newValue
            self.checkbox.set(isSelected: newValue, animated: false)
            self.update(by: self.bgcolor)
        }
    }


    public var isFullFilled: Bool = false {
        didSet {
        }
    }

    private var colors: ColorsListView?

    public required init(frame frameRect: NSRect, title: String) {
        self.title = TextViewLayout(.initialize(string: title, color: .white, font: .medium(.text)), maximumNumberOfLines: 1, truncationType: .end, alignment: .left)
        self.title.measure(width: .greatestFiniteMagnitude)
        super.init(frame: frameRect)

        if System.liquidGlass {
            let glass = LiquidGlassView(frame: bounds, cornerRadius: frameRect.height / 2, hasShadow: false, hasBorder: false, forceAppearance: .forceDark)
            self.glassView = glass
            addSubview(glass)
            self.stretchReferenceView = glass
        } else {
            layer?.cornerRadius = frameRect.height / 2
        }

        addSubview(checkbox)

        titleView.update(self.title)
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        titleView.isEventLess = true
        titleView.backgroundColor = .clear
        addSubview(titleView)

        colors?.colors = [NSColor.random, NSColor.random, NSColor.random]

        setFrameSize(self.title.layoutSize.width + 10 + checkbox.frame.width + 10 + 10, frameRect.height)
        scaleOnClick = true

        self.set(handler: { [weak self] _ in
            if let strongSelf = self {
                strongSelf.isSelected = !strongSelf.isSelected
                strongSelf.onChangedValue?(strongSelf.isSelected)
                strongSelf.update(by: strongSelf.bgcolor)
            }
        }, for: .Click)

    }
    
    public var hasPattern: Bool = false {
        didSet {
            checkbox.set(isSelected: hasPattern, animated: false)
        }
    }
    
    public var colorsValue: [NSColor] = [] {
        didSet {
            if colors == nil, !colorsValue.isEmpty {
                colors = ColorsListView(frame: NSMakeRect(10, 0, 16, 16))
                colors?.centerY(x: 10)
                addSubview(colors!)
            } else if colorsValue.isEmpty {
                colors?.removeFromSuperview()
                colors = nil
            }
            colors?.colors = colorsValue
            checkbox.isHidden = colors != nil
            checkbox.set(isSelected: !colorsValue.isEmpty, animated: true)
            needsLayout = true
        }
    }
    
    public var onChangedValue:((Bool)->Void)?
    
    public override func layout() {
        super.layout()
        if let glass = glassView {
            glass.frame = bounds
            glass.updateLayout(size: bounds.size, transition: .immediate)
        }
        checkbox.centerY(x: 10)
        colors?.centerY(x: 10)
        titleView.resize(title.layoutSize.width)
        titleView.centerY(x: frame.width - titleView.frame.width - 10)
    }
    private var bgcolor: NSColor? = nil

    public func update(by color: NSColor?) -> Void {
        self.bgcolor = color
        let resolved: NSColor
        if let color = color {
            resolved = isSelected ? color.darker() : color
        } else {
            resolved = isSelected ? theme.chatServiceItemColor.darker() : theme.chatServiceItemColor
        }
        if let glass = glassView {
            glass.customTint = resolved
            backgroundColor = .clear
        } else {
            backgroundColor = resolved
        }
        if colorsValue.isEmpty {
            checkbox.set(isSelected: checkbox.isSelected, animated: true)
        }
    }

    
    deinit {
    }
    
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
}


public final class WallpaperPlayRotateView : Control {


    private let imageView = ImageView()
    private var glassView: LiquidGlassView?

    public var onClick:(()->Void)?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        if System.liquidGlass {
            let glass = LiquidGlassView(frame: bounds, cornerRadius: frameRect.height / 2, hasShadow: false, hasBorder: false, forceAppearance: .forceDark)
            self.glassView = glass
            addSubview(glass)
            self.stretchReferenceView = glass
        } else {
            layer?.cornerRadius = frameRect.height / 2
        }
        addSubview(imageView)
        imageView.isAccessibilityDecorative = true
        scaleOnClick = true
        self.set(handler: { [weak self] _ in
            self?.onClick?()
        }, for: .Click)
    }
    
    public func set(rotation: Int32?, animated: Bool) {
        if let layer = self.imageView.layer {
            if let rotation = rotation {
                if animated {
                    if let animatorLayer = self.imageView.animator().layer {
                        layer.position = CGPoint(x: layer.frame.midX, y: layer.frame.midY)
                        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                        
                        NSAnimationContext.beginGrouping()
                        NSAnimationContext.current.allowsImplicitAnimation = true
                        animatorLayer.transform = CATransform3DMakeRotation(CGFloat.pi * CGFloat(rotation) / 180.0, 0, 0, 1)
                        NSAnimationContext.endGrouping()
                    }
                } else {
                    layer.position = CGPoint(x: layer.frame.midX, y: layer.frame.midY)
                    layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                    layer.transform = CATransform3DMakeRotation(CGFloat.pi * CGFloat(rotation) / 180.0, 0, 0, 1)
                }
            }
        }
    }
    
    public override func layout() {
        super.layout()
        if let glass = glassView {
            glass.frame = bounds
            glass.updateLayout(size: bounds.size, transition: .immediate)
        }
        imageView.center()
    }

    public func update(_ image: CGImage) {
        self.imageView.image = image
        self.imageView.sizeToFit()
        self.imageView.center()
    }

    public func update(by color: NSColor?) -> Void {
        let resolved = color ?? theme.chatServiceItemColor
        if let glass = glassView {
            glass.customTint = resolved
            backgroundColor = .clear
        } else {
            backgroundColor = resolved
        }
    }
    
    deinit {
    }
    
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
