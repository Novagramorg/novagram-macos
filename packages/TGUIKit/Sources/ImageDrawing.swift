import Cocoa

public func generateTextIcon(_ text: NSAttributedString, minSize: Bool = true) -> CGImage {

    let textNode = TextNode.layoutText(text, nil, 1, .end, NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude), nil, false, .center)
    var size = textNode.0.size
    if minSize {
        size.width = max(size.width, 24)
        size.width = max(size.height, 23)
    }
    return generateImage(textNode.0.size, rotatedContext: { size, ctx in
        let rect = NSMakeRect(0, 0, size.width, size.height)
        ctx.clear(rect)

        textNode.1.draw(rect.focus(textNode.0.size), in: ctx, backingScaleFactor: System.backingScale, backgroundColor: .clear)
    })!
}

public func generateScaledImage(image: CGImage?, size: CGSize, scale: CGFloat? = nil, opaque: Bool = true, color: NSColor? = nil) -> CGImage? {
    guard let image = image else {
        return nil
    }

    return generateImage(size, contextGenerator: { size, context in
        context.clear(size.bounds)

        // Draw base image
        context.draw(image, in: CGRect(origin: .zero, size: size))

        // Apply tint color if provided
        if let color = color {
            context.saveGState()
            context.setFillColor(color.cgColor)
            context.setBlendMode(.sourceAtop) // or .multiply, .overlay, depending on effect desired
            context.fill(CGRect(origin: .zero, size: size))
            context.restoreGState()
        }
    }, opaque: opaque, scale: scale ?? System.backingScale)
}
