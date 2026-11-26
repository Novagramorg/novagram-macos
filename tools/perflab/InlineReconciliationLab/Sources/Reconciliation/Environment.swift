import Cocoa

typealias Key = InlineStickerItemLayer.Key

class LayerRows {
    let parent = CALayer()
    var inlineStickerItemViews: [Key: CALayer] = [:]
    func ensureLayer(_ key: Key) {
        if inlineStickerItemViews[key] == nil {
            let layer = CALayer()
            layer.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
            parent.addSublayer(layer)
            inlineStickerItemViews[key] = layer
        }
    }
    func bind(_ keys: [Key]) {}
}
