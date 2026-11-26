import Cocoa

public func drawPollSquareUnselected(_ context: CGContext, rect: CGRect, borderColor: NSColor) {
    context.setStrokeColor(borderColor.cgColor)
    context.setLineWidth(1.0)
    let path = CGMutablePath()
    path.addRoundedRect(in: rect.insetBy(dx: 1, dy: 1), cornerWidth: 4, cornerHeight: 4)
    context.addPath(path)
    context.strokePath()
}

public func drawPollSquareSelected(_ context: CGContext, rect: CGRect, image: NSImage, backgroundColor: NSColor, foregroundColor: NSColor? = nil, flipVertical: Bool = false) {
    context.saveGState()
    context.setBlendMode(.copy)
    let clipPath = CGMutablePath()
    clipPath.addRoundedRect(in: rect, cornerWidth: 5, cornerHeight: 5)
    context.addPath(clipPath)
    context.clip()
    if foregroundColor != nil {
        context.setFillColor(backgroundColor.cgColor)
        context.fill(rect)
    } else {
        if backgroundColor != NSColor(0xffffff) {
            context.setFillColor(NSColor(0xffffff).cgColor)
            context.fill(rect)
        }
        context.setFillColor(backgroundColor.cgColor)
        let insetPath = CGMutablePath()
        insetPath.addRoundedRect(in: rect.insetBy(dx: 1, dy: 1), cornerWidth: 4, cornerHeight: 4)
        context.addPath(insetPath)
        context.fillPath()
    }
    context.setBlendMode(.normal)
    let image = flipVertical ? image.precomposed(flipVertical: true) : image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let imageRect = rect.focus(image.backingSize).offsetBy(dx: rect.minX, dy: rect.minY)
    context.saveGState()
    if let foregroundColor {
        context.clip(to: imageRect, mask: image)
        context.setFillColor(foregroundColor.cgColor)
        context.fill(imageRect)
    } else if backgroundColor == NSColor(0xffffff) {
        context.clip(to: rect, mask: image)
        context.clear(rect)
    } else {
        context.draw(image, in: imageRect)
    }
    context.restoreGState()
    context.restoreGState()
}
