import Cocoa
import TGUIKit
import TelegramTheme
import SwiftSignalKit

public class MediaDustView2: View {
    private static let speckleImage: CGImage? = TelegramThemeHooks.shared.image(.textSpeckleNormal).cgImage(forProposedRect: nil, context: nil, hints: nil)

    private var currentParams: (size: CGSize, color: NSColor)?
    private var emitter: CAEmitterCell?
    private var emitterLayer: CAEmitterLayer?
    private lazy var keyObserver = WindowKeyObserver(update: { [weak self] in
        self?.updatePlayback()
    })
    private let maskLayer = SimpleShapeLayer()
        
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.initialize()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func initialize() {
        
        let emitter = CAEmitterCell()
        emitter.color = NSColor(rgb: 0xffffff, alpha: 0.0).cgColor
        emitter.contents = MediaDustView2.speckleImage
        emitter.contentsScale = 1.8
        emitter.emissionRange = .pi * 2.0
        emitter.lifetime = 8.0
        emitter.scale = 0.5
        emitter.velocityRange = 0.0
        emitter.name = "dustCell"
        emitter.alphaRange = 1.0
        emitter.setValue("point", forKey: "particleType")
        emitter.setValue(1.0, forKey: "mass")
        emitter.setValue(0.01, forKey: "massRange")
        self.emitter = emitter
        
        let alphaBehavior = createEmitterBehavior(type: "valueOverLife")
        alphaBehavior.setValue("color.alpha", forKey: "keyPath")
        alphaBehavior.setValue([0, 0, 1, 0, -1, 0, 0, 1, 0, -1, 0, 0, 1, 0, -1, 0, 0, 1, 0, -1, 0, 0, 1, 0, -1, 0, 0, 1, 0, -1, 0, 0, 1, 0, -1, 0, 0, 1, 0, -1], forKey: "values")
        alphaBehavior.setValue(true, forKey: "additive")
        
        let scaleBehavior = createEmitterBehavior(type: "valueOverLife")
        scaleBehavior.setValue("scale", forKey: "keyPath")
        scaleBehavior.setValue([0.0, 0.5], forKey: "values")
        scaleBehavior.setValue([0.0, 0.05], forKey: "locations")
                
        let behaviors = [alphaBehavior, scaleBehavior]
    
        let emitterLayer = CAEmitterLayer()
        emitterLayer.masksToBounds = true
        emitterLayer.allowsGroupOpacity = true
        emitterLayer.lifetime = 1
        emitterLayer.emitterCells = [emitter]
        emitterLayer.seed = arc4random()
        emitterLayer.emitterShape = .rectangle
        emitterLayer.setValue(behaviors, forKey: "emitterBehaviors")
                
        self.emitterLayer = emitterLayer
        
        emitterLayer.mask = maskLayer
        maskLayer.fillRule = .evenOdd
        self.layer?.addSublayer(emitterLayer)
        
        self.updateEmitter()
        self.updatePlayback()
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.keyObserver.observe(self.window)
        self.updatePlayback()
    }
    
    private func updatePlayback() {
        self.emitterLayer?.setTimelineFrozen(!WindowKeyObserver.isKey(self.window))
    }
        
    private func updateEmitter() {
        guard let (size, _) = self.currentParams else {
            return
        }
        self.maskLayer.frame = CGRect(origin: CGPoint(), size: size)
        self.emitterLayer?.frame = CGRect(origin: CGPoint(), size: size)
        self.emitterLayer?.emitterSize = size
        self.emitterLayer?.emitterPosition = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        
        let square = Float(size.width * size.height)
        Queue.mainQueue().async {
            self.emitter?.birthRate = min(100000.0, square * 0.016)
        }
    }
    
    public func update(size: CGSize, color: NSColor, mask: CGPath) {
        self.currentParams = (size, color)
        self.updateEmitter()
        self.maskLayer.path = mask
    }
}