import Cocoa

public func generateTextIcon_AccentBadge(text: String, bgColor: NSColor, textColor: NSColor, fontSize: CGFloat = .small, round: Bool = false) -> CGImage {
    
    let textNode = TextNode.layoutText(.initialize(string: text, color: textColor, font: .avatar(fontSize)), nil, 1, .end, NSMakeSize(.greatestFiniteMagnitude, 20), nil, false, .center)
    var size = textNode.0.size
    size.width += 6
    size.height += 4
    return generateImage(size, rotatedContext: { size, ctx in
        let rect = NSMakeRect(0, 0, size.width, size.height)
        ctx.clear(rect)
        
        ctx.round(size, round ? size.height / 2 : .cornerRadius)
        ctx.setFillColor(bgColor.cgColor)
        ctx.fill(rect)
        
        var textRect = rect.focus(textNode.0.size)
        
        if fontSize < 9 {
            textRect.origin.y -= 1
        }
        textNode.1.draw(textRect, in: ctx, backingScaleFactor: System.backingScale, backgroundColor: .clear)
    })!
}
