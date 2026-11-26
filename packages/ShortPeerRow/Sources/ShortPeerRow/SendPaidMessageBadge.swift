import Cocoa
import TGUIKit
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif

final class SendPaidMessageBadgeCache {
    private struct Key: Equatable {
        let text: String
        let background: CGColor
        let outer: CGColor
        let foreground: CGColor
        let font: NSFont
        let scale: CGFloat
        let icon: NSImage

        static func == (lhs: Key, rhs: Key) -> Bool {
            lhs.text == rhs.text && lhs.background == rhs.background && lhs.outer == rhs.outer && lhs.foreground == rhs.foreground && lhs.font == rhs.font && lhs.scale == rhs.scale && lhs.icon === rhs.icon
        }
    }

    private var entry: (key: Key, image: CGImage)?

    func image(text: String, bgColor: NSColor, outerColor: NSColor, imageColor: NSColor, font: NSFont) -> CGImage {
        let key = Key(text: text, background: bgColor.cgColor, outer: outerColor.cgColor, foreground: imageColor.cgColor, font: font, scale: System.backingScale, icon: TelegramThemeHooks.shared.image(.starSmall))
        if let entry, entry.key == key {
            return entry.image
        }
        let image = generalSendPaidMessage(bgColor: bgColor, outerColor: outerColor, imageColor: imageColor, count: .initialize(string: text, color: imageColor, font: font))
        entry = (key, image)
        return image
    }
}

public func generalSendPaidMessage(bgColor: NSColor, outerColor: NSColor, imageColor: NSColor, count: NSAttributedString) -> CGImage {
    let layout = TextNode.layoutText(count, nil, 1, .end, NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude), nil, false, .center)
    let image = TelegramThemeHooks.shared.image(.starSmall).precomposed(imageColor, flipVertical: true)

    return generateImage(NSMakeSize(layout.0.size.width + 8 + image.backingSize.width, 18), rotatedContext: { size, ctx in
        ctx.clear(size.bounds)
        ctx.round(size, size.height / 2)
        
        ctx.setFillColor(outerColor.cgColor)
        ctx.fill(size.bounds)
        
        let path = CGMutablePath()
        let inner = size.bounds.insetBy(dx: 1, dy: 1)
        path.addRoundedRect(in: inner, cornerWidth: inner.height / 2, cornerHeight: inner.height / 2)
        ctx.addPath(path)
        ctx.setFillColor(bgColor.cgColor)
        ctx.fillPath()

        var rect = size.bounds.focus(layout.0.size)
        rect.origin.x = size.width - rect.size.width - 4
        layout.1.draw(rect, in: ctx, backingScaleFactor: 2, backgroundColor: .clear)
        
        var imageRect = size.bounds.focus(image.backingSize)
        imageRect.origin.x = 3
        ctx.draw(image, in: imageRect)
    })!
}
