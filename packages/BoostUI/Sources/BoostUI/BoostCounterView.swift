import Foundation
import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import TelegramContext
import TelegramTheme

public final class BoostCounterView : View {
    private let backgrounView = ImageView()
    
    private let textView = DynamicCounterTextView(frame: .zero)
    private let imageView = ImageView()
    private let container = View()
    
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(backgrounView)
        container.addSubview(textView)
        container.addSubview(imageView)
        addSubview(container)
        
        textView.userInteractionEnabled = false
        backgrounView.isAccessibilityDecorative = true
        imageView.isAccessibilityDecorative = true
    }
    
    public override func layout() {
        super.layout()
        backgrounView.frame = bounds
        container.centerX()
        imageView.centerY(x: -3)
        textView.centerY(x: imageView.frame.maxX)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var boosts: Int?

    public override func isAccessibilityElement() -> Bool {
        return boosts != nil
    }

    public override func accessibilityRole() -> NSAccessibility.Role? {
        return .staticText
    }

    public override func accessibilityLabel() -> String? {
        return boosts.flatMap { "\($0)" }
    }
    
    
    public func update(boosts: Int, context: any AccountContextProtocol, transition: ContainedViewLayoutTransition) -> NSSize {
        
        let dynamicValue = DynamicCounterTextView.make(for: "\(boosts)", count: "\(boosts)", font: .avatar(20), textColor: .white, width: .greatestFiniteMagnitude)
        
        textView.update(dynamicValue, animated: transition.isAnimated)
        self.boosts = boosts
        transition.updateFrame(view: textView, frame: CGRect(origin: textView.frame.origin, size: dynamicValue.size))
        
        imageView.image = BoostHooks.shared.iconBoostLighting().precomposed()
        imageView.sizeToFit()
        
        container.setFrameSize(NSMakeSize(dynamicValue.size.width + imageView.frame.width, 40))
                    
        let size = NSMakeSize(container.frame.width + 20, 50)
        
        let image = generateImage(NSMakeSize(size.width, size.height - 10), contextGenerator: { size, ctx in
            ctx.clear(size.bounds)
           
            let path = CGMutablePath()
            path.addRoundedRect(in: NSMakeRect(0, 0, size.width, size.height), cornerWidth: size.height / 2, cornerHeight: size.height / 2)
            
            ctx.addPath(path)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            
        })!
        
        let corner = generateImage(NSMakeSize(30, 10), contextGenerator: { size, context in
            context.clear(CGRect(origin: CGPoint(), size: size))
            context.setFillColor(NSColor.black.cgColor)
            context.scaleBy(x: 0.333, y: 0.333)
            let _ = try? drawSvgPath(context, path: "M85.882251,0 C79.5170552,0 73.4125613,2.52817247 68.9116882,7.02834833 L51.4264069,24.5109211 C46.7401154,29.1964866 39.1421356,29.1964866 34.4558441,24.5109211 L16.9705627,7.02834833 C12.4696897,2.52817247 6.36519576,0 0,0 L85.882251,0 ")
            context.fillPath()
        })!

        let clipImage = generateImage(size, rotatedContext: { size, ctx in
            ctx.clear(size.bounds)
            ctx.draw(image, in: NSMakeRect(0, 0, image.backingSize.width, image.backingSize.height))
            
            ctx.draw(corner, in: NSMakeRect(size.bounds.focus(corner.backingSize).minX, image.backingSize.height, corner.backingSize.width, corner.backingSize.height))
        })!
        
        let fullImage = generateImage(size, contextGenerator: { size, ctx in
            ctx.clear(size.bounds)

            ctx.clip(to: size.bounds, mask: clipImage)
            
            let gradient = CGGradient.evenlySpaced(premiumGradient.compactMap { $0.cgColor }, colorSpace: deviceColorSpace)!
            
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: size.height), options: CGGradientDrawingOptions())
        })!
        
        self.backgrounView.image = fullImage
        
        
        needsLayout = true
        
        return size
    }

}
