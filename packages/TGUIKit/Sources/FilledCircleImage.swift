import Cocoa

public func generateFilledCircleImage(diameter: CGFloat, color: NSColor?, strokeColor: NSColor? = nil, strokeWidth: CGFloat? = nil, backgroundColor: NSColor? = nil) -> CGImage {
    return generateImage(CGSize(width: diameter, height: diameter), contextGenerator: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        if let backgroundColor = backgroundColor {
            context.setFillColor(backgroundColor.cgColor)
            context.fill(CGRect(origin: CGPoint(), size: size))
        }
        
        if let strokeColor = strokeColor, let strokeWidth = strokeWidth {
            context.setFillColor(strokeColor.cgColor)
            context.fillEllipse(in: CGRect(origin: CGPoint(), size: size))
            
            if let color = color {
                context.setFillColor(color.cgColor)
            } else {
                context.setFillColor(NSColor.clear.cgColor)
                context.setBlendMode(.copy)
            }
            context.fillEllipse(in: CGRect(origin: CGPoint(x: strokeWidth, y: strokeWidth), size: CGSize(width: size.width - strokeWidth * 2.0, height: size.height - strokeWidth * 2.0)))
        } else {
            if let color = color {
                context.setFillColor(color.cgColor)
            } else {
                context.setFillColor(NSColor.clear.cgColor)
                context.setBlendMode(.copy)
            }
            context.fillEllipse(in: CGRect(origin: CGPoint(), size: size))
        }
    })!
}
