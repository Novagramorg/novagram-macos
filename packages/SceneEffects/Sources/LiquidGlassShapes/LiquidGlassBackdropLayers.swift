import Foundation
import Cocoa
import TGUIKit
import MetalEngine

private final class LiquidGlassNullActionDelegate: NSObject, CALayerDelegate {
    func action(for layer: CALayer, forKey event: String) -> CAAction? {
        return NSNull()
    }
}

private func makeLiquidGlassFilter(_ name: String) -> NSObject? {
    guard let filterClass = NSClassFromString("CAFilter") as AnyObject as? NSObjectProtocol else {
        return nil
    }
    let selector = NSSelectorFromString("filterWithName:")
    guard filterClass.responds(to: selector) else {
        return nil
    }
    return filterClass.perform(selector, with: name)?.takeUnretainedValue() as? NSObject
}

final class LiquidGlassBackdropLayers {
    let containerLayer: SimpleLayer
    let backdropLayer: CALayer
    let backdropMaskLayer: MetalEngineSubjectLayer
    let displacementMapLayer: MetalEngineSubjectLayer
    private let backdropLayerDelegate: LiquidGlassNullActionDelegate

    init?(blurRadius: CGFloat, scale: CGFloat) {
        guard let displacementMapFilter = makeLiquidGlassFilter("displacementMap"), let backdropLayer = ee2_createBackdropLayer() else {
            return nil
        }
        self.backdropLayer = backdropLayer
        self.backdropLayerDelegate = LiquidGlassNullActionDelegate()
        self.containerLayer = SimpleLayer()
        self.backdropMaskLayer = MetalEngineSubjectLayer()
        self.displacementMapLayer = MetalEngineSubjectLayer()

        self.containerLayer.masksToBounds = false
        self.containerLayer.rasterizationScale = System.backingScale

        backdropLayer.delegate = self.backdropLayerDelegate
        backdropLayer.setValue(scale as NSNumber, forKey: "scale")
        backdropLayer.rasterizationScale = scale
        if let blurFilter = makeLiquidGlassFilter("gaussianBlur") {
            blurFilter.setValue(blurRadius as NSNumber, forKey: "inputRadius")
            backdropLayer.filters = [blurFilter]
        }
        self.backdropMaskLayer.magnificationFilter = .linear
        backdropLayer.mask = self.backdropMaskLayer
        self.containerLayer.addSublayer(backdropLayer)

        let displacementMapLayerName = "liquidGlassDisplacementMap"
        self.displacementMapLayer.name = displacementMapLayerName
        self.displacementMapLayer.zPosition = -1.0
        self.displacementMapLayer.magnificationFilter = .linear
        self.containerLayer.addSublayer(self.displacementMapLayer)

        displacementMapFilter.setValue(displacementMapLayerName, forKey: "inputSourceSublayerName")
        displacementMapFilter.setValue((-LiquidGlassShapesConstants.displacementAmount) as NSNumber, forKey: "inputAmount")
        displacementMapFilter.setValue(NSValue(point: CGPoint(x: 0.5, y: 0.5)), forKey: "inputOffset")
        self.containerLayer.filters = [displacementMapFilter]
    }

    func updateFrame(_ frame: CGRect) {
        self.containerLayer.frame = frame
        let bounds = CGRect(origin: CGPoint(), size: frame.size)
        self.backdropLayer.frame = bounds
        self.backdropMaskLayer.frame = bounds
        self.displacementMapLayer.frame = bounds
    }
}
