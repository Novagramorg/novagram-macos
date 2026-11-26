import Cocoa
import SwiftSignalKit
import Postbox
import TelegramCore
import TGUIKit
import Localization
import TelegramContext
import TelegramTheme
import TelegramMediaUtils


public final class CornerMaskLayer : SimpleShapeLayer {
    public var corners: ImageCorners? {
        didSet {
            if let corners {
                self.path = CGPath.bubbleCorners(size: frame.size, corners: corners)
            }
        }
    }
}


public final class CornerMaskLayerSimple : SimpleLayer {
    public var corners: ImageCorners? {
        didSet {
            if let corners {
                let layer = SimpleShapeLayer()
                layer.path = CGPath.bubbleCorners(size: frame.size, corners: corners)
                self.mask = layer
            }
        }
    }
}



private let sensitiveImage = TelegramThemeHooks.shared.image(.iconMediaSensitiveContent).precomposed(.white)

public final class MediaInkView : Control {
    
    private final class SensitiveView: NSVisualEffectView {
        private let textView = TextView()
        private let imageView = ImageView()
        required override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            self.wantsLayer = true
            self.material = .ultraDark
            self.blendingMode = .withinWindow
            self.state = .active
            
            addSubview(textView)
            addSubview(imageView)
            
            
            imageView.image = sensitiveImage
            imageView.sizeToFit()
            imageView.isAccessibilityDecorative = true
            
            let textLayout = TextViewLayout(.initialize(string: strings().chatSensitiveContent, color: NSColor.white, font: .medium(.text)))
            textLayout.measure(width: .greatestFiniteMagnitude)
            
            textView.update(textLayout)
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            
            setFrameSize(NSMakeSize(textView.frame.width + 25 + imageView.frame.width, 30))
        }
        
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func layout() {
            super.layout()
            self.imageView.centerY(x: 10)
            self.textView.centerY(x: imageView.frame.maxX + 5)
        }
    }
    
    private let inkView: MediaDustView = MediaDustView()
    private var inkMaskView: CornerMaskLayer?

    private let preview: TransformImageView = TransformImageView()
    
    private var sensitiveView: SensitiveView?
    private var paidView: PaidContentView?

    private var isSensitive: Bool = false
    private var payAmount: Int64? = nil
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(preview)
        addSubview(inkView)
        
        inkView.update(revealed: false)

    }
    

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update(isRevealed: Bool, updated: Bool, context: any AccountContextProtocol, imageReference: ImageMediaReference, size: NSSize, corners: ImageCorners?, synchronousLoad: Bool, isSensitive: Bool, payAmount: Int64?) {
        
        
        self.isSensitive = isSensitive
        self.payAmount = payAmount
        
        if isSensitive {
            let current: SensitiveView
            if let view = self.sensitiveView {
                current = view
            } else {
                current = SensitiveView(frame: NSMakeRect(0, 0, 100, 30))
                current.layer?.cornerRadius = current.frame.height / 2
                self.sensitiveView = current
                addSubview(current)
            }
        } else if let view = self.sensitiveView {
            performSubviewRemoval(view, animated: false)
            self.sensitiveView = nil
        }
        
        if let payAmount {
            let current: PaidContentView
            if let view = self.paidView {
                current = view
            } else {
                current = PaidContentView(frame: NSMakeRect(0, 0, 100, 30))
                self.paidView = current
                addSubview(current)
            }
            current.update(amount: payAmount, context: context, short: true)
            current.layer?.cornerRadius = current.frame.height / 2
        } else if let view = self.paidView {
            performSubviewRemoval(view, animated: false)
            self.paidView = nil
        }
                
        
        let signal = chatSecretPhoto(account: context.account, imageReference: imageReference, scale: System.backingScale, synchronousLoad: synchronousLoad)
        let arguments = TransformImageArguments(corners: .init(), imageSize: size, boundingSize: size, intrinsicInsets: .init())
        
        
        self.preview.setSignal(signal: cachedMedia(media: imageReference.media, arguments: arguments, scale: System.backingScale), clearInstantly: updated)
        
        if !self.preview.isFullyLoaded {
            self.preview.setSignal(signal, cacheImage: { result in
                cacheMedia(result, media: imageReference.media, arguments: arguments, scale: System.backingScale)
            })
        }
        
        
        self.preview.set(arguments: arguments)
        

        let inkRect = size.bounds.insetBy(dx: -20, dy: -20)
        
        let current = self.inkView
        current.frame = inkRect
        
        let path = CGMutablePath()
        path.addRect(inkRect.size.bounds)
        
        current.update(size: inkRect.size, color: NSColor.white, textColor: .black, mask: buttonPath(path))
       
        if let corners {
            let mask: CornerMaskLayer
            if let layer = self.inkMaskView {
                mask = layer
            } else {
                mask = CornerMaskLayer()
                self.inkMaskView = mask
            }
            mask.frame = size.bounds
            mask.corners = corners
            self.layer?.mask = mask
        } else {
            inkMaskView = nil
            layer?.mask = nil
            layer?.cornerRadius = 4
        }
        preview.frame = size.bounds
        
        needsLayout = true

    }
    
    private func buttonPath(_ basic: CGPath) -> CGPath {
        let buttonPath = CGMutablePath()

        buttonPath.addPath(basic)
        
        if let view = self.sensitiveView {
            let buttonRect = view.frame
            buttonPath.addRoundedRect(in: buttonRect, cornerWidth: buttonRect.height / 2, cornerHeight: buttonRect.height / 2)
        }
        
        if let view = self.paidView {
            let buttonRect = view.frame
            buttonPath.addRoundedRect(in: buttonRect, cornerWidth: buttonRect.height / 2, cornerHeight: buttonRect.height / 2)
        }
                    
        return buttonPath
    }
    
    public override func layout() {
        super.layout()
        preview.frame = bounds
        inkMaskView?.frame = bounds
        inkView.frame = bounds.insetBy(dx: -20, dy: -20)
        sensitiveView?.center()
        paidView?.center()
    }
}
