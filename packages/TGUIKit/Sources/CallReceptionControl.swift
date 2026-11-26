import Cocoa

public class CallReceptionControl: View {
    
    public var reception: Int32 = 4 {
        didSet {
            self.needsDisplay = true
        }
    }
    
    public override func draw(_ layer: CALayer, in context: CGContext) {
        super.draw(layer, in: context)
        
        context.setFillColor(NSColor.white.cgColor)
        
        let width: CGFloat = 3.0
        let spacing: CGFloat = 2.0

        for i in 0 ..< 4 {
            let height = 4.0 + 2.0 * CGFloat(i)
            let rect = CGRect(x: bounds.minX + CGFloat(i) * (width + spacing), y: frame.height - height, width: width, height: height)
            
            if i >= reception {
                context.setAlpha(0.4)
            }
            let path = CGMutablePath()
            path.addRoundedRect(in: rect, cornerWidth: 0.5, cornerHeight: 0.5)
            context.addPath(path)
            context.fillPath()
        }
    }
    
}
