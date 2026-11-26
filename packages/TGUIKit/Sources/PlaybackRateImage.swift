import Cocoa

public func generateEmptySettingsIcon() -> CGImage {
    return generateImage(NSMakeSize(24, 24), contextGenerator: { size, ctx in
        ctx.clear(CGRect(origin: CGPoint(), size: size))
    })!
}

public func optionsRateImage(rate: String, color: NSColor, isLarge: Bool) -> CGImage {
    return generateImage(isLarge ? CGSize(width: 30, height: 30) : CGSize(width: 24.0, height: 24.0), rotatedContext: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))

        let imageName: String = isLarge ? "playspeed_30" : "playspeed_24"

        if let image = NSImage(named: imageName )?.precomposed(color) {
            context.draw(image, in: size.bounds)
        }


        let string = NSMutableAttributedString(string: rate, font: NSFont.semibold(isLarge ? 11 : 10), textColor: color)

        var offset = CGPoint(x: 1.0, y: 0.0)
        if rate.count >= 3 {
            if rate == "0.5x" {
                string.addAttribute(.kern, value: -0.8 as NSNumber, range: NSRange(string.string.startIndex ..< string.string.endIndex, in: string.string))
                offset.x += -0.5
            } else {
                string.addAttribute(.kern, value: -0.5 as NSNumber, range: NSRange(string.string.startIndex ..< string.string.endIndex, in: string.string))
                offset.x += -0.3
            }
        } else {
            offset.x += -0.3
        }

        offset.x *= 0.5
        offset.y *= 0.5


        let layout = TextViewLayout(string, maximumNumberOfLines: 1, truncationType: .middle)
        layout.measure(width: size.width)
        let line = layout.lines[0]

        context.textMatrix = CGAffineTransform(scaleX: 1.0, y: -1.0)
        context.textPosition = size.bounds.focus(line.frame.size).origin.offsetBy(dx: 0, dy: isLarge ? 10 : 8)
        CTLineDraw(line.line, context)
    })!
}
