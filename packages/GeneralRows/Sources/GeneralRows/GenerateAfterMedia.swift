import Cocoa
import TGUIKit
import TelegramTheme
import ColorPalette

public func generateAfterMedia(_ count: String, revealed: Bool) -> CGImage {

    let layout = TextNode.layoutText(.initialize(string: count, color: theme.colors.text, font: .medium(.text)), nil, 1, .end, NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude), nil, false, .center)
    let image = TelegramThemeHooks.shared.image(revealed ? .iconSmallChevronUp : .iconSmallChevronDown).precomposed(theme.colors.text, flipVertical: true)

    return generateImage(NSMakeSize(layout.0.size.width + 3 + image.backingSize.width, layout.0.size.height), contextGenerator: { size, ctx in
        ctx.clear(size.bounds)

        var rect = size.bounds.focus(layout.0.size)
        rect.origin.x = 0
        layout.1.draw(rect, in: ctx, backingScaleFactor: 2, backgroundColor: .clear)

        var imageRect = size.bounds.focus(image.backingSize)
        imageRect.origin.x = rect.maxX + 3
        ctx.draw(image, in: imageRect)
    })!
}
