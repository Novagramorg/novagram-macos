import Cocoa
import Foundation




public class StickerShimmerEffectView: View {
    private let backgroundView: View
    private let effectView: ShimmerEffectForegroundView
    private let foregroundView: ImageView
    
    private var maskView: ImageView?
    
    private var currentData: Data?
    private var currentBackgroundColor: NSColor?
    private var currentForegroundColor: NSColor?
    private var currentShimmeringColor: NSColor?
    private var currentSize = CGSize()
    private var currentScale: CGFloat = 0
    
    public override init() {
        self.backgroundView = View()
        self.effectView = ShimmerEffectForegroundView()
        self.foregroundView = ImageView()
        
        super.init()
        
        self.addSubview(self.backgroundView)
        self.addSubview(self.effectView)
        self.addSubview(self.foregroundView)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public func updateAbsoluteRect(_ rect: CGRect, within containerSize: CGSize) {
        self.effectView.updateAbsoluteRect(rect, within: containerSize)
    }
    public func update(backgroundColor: NSColor?, foregroundColor: NSColor = NSColor(rgb: 0x748391, alpha: 0.2), shimmeringColor: NSColor = NSColor(rgb: 0x748391, alpha: 0.35), data: Data?, size: CGSize) {
        let scale = System.backingScale
        let backgroundKey = backgroundColor.map(resolvedShimmerColor)
        let foregroundKey = resolvedShimmerColor(foregroundColor)
        let shimmeringKey = resolvedShimmerColor(shimmeringColor)
        if self.currentData == data, self.currentBackgroundColor == backgroundKey, self.currentForegroundColor == foregroundKey, self.currentShimmeringColor == shimmeringKey, self.currentSize == size, self.currentScale == scale {
            return
        }
        
        self.currentBackgroundColor = backgroundKey
        self.currentForegroundColor = foregroundKey
        self.currentShimmeringColor = shimmeringKey
        self.currentData = data
        self.currentSize = size
        self.currentScale = scale
        
        self.backgroundView.backgroundColor = foregroundColor
        
        self.effectView.update(backgroundColor: backgroundColor == nil ? .clear : foregroundColor, foregroundColor: shimmeringColor)
        
        let image = generateImage(size, scale: scale, rotatedContext: { size, context in
            if let backgroundColor = backgroundKey?.cgColor {
                context.setFillColor(backgroundColor)
                context.setBlendMode(.copy)
                context.fill(CGRect(origin: CGPoint(), size: size))
                context.setFillColor(NSColor.clear.cgColor)
            } else {
                context.clear(CGRect(origin: CGPoint(), size: size))
                context.setFillColor(NSColor.black.cgColor)
            }
            
            if let data = data {
                var path = decodeStickerThumbnailData(data)
                if !path.hasPrefix("z") {
                    path = "\(path)z"
                }
                let reader = PathDataReader(input: path)
                let segments = reader.read()

                let scale = size.width / 512.0
                context.scaleBy(x: scale, y: scale)
                renderPath(segments, context: context)
            } else {
                let path = CGMutablePath()
                path.addRoundedRect(in: CGRect(origin: CGPoint(), size: size), cornerWidth: min(min(10, size.height / 2), size.width / 2), cornerHeight: min(min(size.height / 2, 10), size.height / 2))
                context.addPath(path)
                context.fillPath()
            }
        })
                
        if backgroundColor == nil {
            self.foregroundView.image = nil
            
            let maskView: ImageView
            if let current = self.maskView {
                maskView = current
            } else {
                maskView = ImageView()
                maskView.frame = CGRect(origin: CGPoint(), size: size)
                self.maskView = maskView
                self.layer?.mask = maskView.layer
            }
            
        } else {
            self.foregroundView.image = image
            
            if let _ = self.maskView {
                self.layer?.mask = nil
                self.maskView = nil
            }
        }
        
        self.maskView?.frame = CGRect(origin: CGPoint(), size: size)
        self.maskView?.image = image
        
        self.backgroundView.frame = CGRect(origin: CGPoint(), size: size)
        self.foregroundView.frame = CGRect(origin: CGPoint(), size: size)
        self.effectView.frame = CGRect(origin: CGPoint(), size: size)
    }
}
