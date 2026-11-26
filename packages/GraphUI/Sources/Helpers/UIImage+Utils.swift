import Cocoa
import TGUIKit
import GraphCore


extension NSImage {
    static let arrowRight = NSImage(named: "arrow_right")
    public convenience init?(color: NSColor, size: CGSize = CGSize(width: 1, height: 1)) {
        let rect = CGRect(origin: .zero, size: size)
        
        
        let image = generateImage(size, contextGenerator: { size, ctx in
            ctx.clear(rect)
            ctx.setFillColor(color.cgColor)
            ctx.fill(rect)
        })
        
        guard let cgImage = image else { return nil }
        self.init(cgImage: cgImage, size: size)
    }
    
    
}
