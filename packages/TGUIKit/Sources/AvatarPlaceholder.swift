import Cocoa
import SwiftSignalKit

public enum EmptyAvatartType {
    case peer(colors:(top:NSColor, bottom: NSColor), letter: [String], font: NSFont, cornerRadius: CGFloat?)
    case icon(colors:(top:NSColor, bottom: NSColor), icon: CGImage, iconSize: NSSize, cornerRadius: CGFloat?)
}

public func generateEmptyPhoto(_ displayDimensions:NSSize, type: EmptyAvatartType, bubble: Bool) -> Signal<CGImage?, NoError> {
    return Signal { subscriber in

        let color:(top: NSColor, bottom: NSColor)
        let letters: [String]?
        let icon: CGImage?
        let iconSize: NSSize?
        let font: NSFont?
        let cornerRadius: CGFloat?
        switch type {
        case let .icon(colors, _icon, _iconSize, _cornerRadius):
            color = colors
            icon = _icon
            letters = nil
            font = nil
            iconSize = _iconSize
            cornerRadius = _cornerRadius
        case let .peer(colors, _letters, _font, _cornerRadius):
            color = colors
            icon = nil
            font = _font
            letters = _letters
            iconSize = nil
            cornerRadius = _cornerRadius
        }

        let image = generateImage(displayDimensions, contextGenerator: { (size, ctx) in
            ctx.clear(NSMakeRect(0, 0, size.width, size.height))

            if bubble {
                let rect = CGRect(origin: CGPoint(), size: size)
                ctx.translateBy(x: rect.midX, y: rect.midY)
                ctx.scaleBy(x: 1.0, y: -1.0)
                ctx.translateBy(x: -rect.midX, y: -rect.midY)
                addAvatarBubblePath(context: ctx, rect: rect)
                ctx.translateBy(x: rect.midX, y: rect.midY)
                ctx.scaleBy(x: 1.0, y: -1.0)
                ctx.translateBy(x: -rect.midX, y: -rect.midY)
                ctx.clip()
            } else {
                if let cornerRadius = cornerRadius {
                    ctx.round(size, cornerRadius)
                } else {
                    ctx.round(size, size.height / 2)
                }
            }

            //ctx.addEllipse(in: CGRect(x: 0.0, y: 0.0, width: size.width, height:
             //   size.height))
           // ctx.clip()

            var locations: [CGFloat] = [1.0, 0.2];
            let colorSpace = deviceColorSpace
            let gradient = CGGradient(colorsSpace: colorSpace, colors: NSArray(array: [color.top.cgColor, color.bottom.cgColor]), locations: &locations)!

            ctx.drawLinearGradient(gradient, start: CGPoint(), end: CGPoint(x: 0.0, y: size.height), options: CGGradientDrawingOptions())

            ctx.setBlendMode(.normal)

            if let letters = letters, let font = font {
                let string = letters.count == 0 ? "" : (letters[0] + (letters.count == 1 ? "" : letters[1]))
                let attributedString = NSAttributedString(string: string, attributes: [NSAttributedString.Key.font: font, NSAttributedString.Key.foregroundColor: NSColor.white])

                let line = CTLineCreateWithAttributedString(attributedString)
                let lineBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

                let lineOrigin = CGPoint(x: floorToScreenPixels(System.backingScale, -lineBounds.origin.x + (size.width - lineBounds.size.width) / 2.0) , y: floorToScreenPixels(System.backingScale, -lineBounds.origin.y + (size.height - lineBounds.size.height) / 2.0))

                ctx.translateBy(x: floorToScreenPixels(size.width / 2.0), y: floorToScreenPixels(size.height / 2.0))
                ctx.scaleBy(x: 1.0, y: 1.0)
                ctx.translateBy(x: -floorToScreenPixels(size.width / 2.0), y: -floorToScreenPixels(size.height / 2.0))
                //
                ctx.translateBy(x: lineOrigin.x, y: lineOrigin.y)
                CTLineDraw(line, ctx)
                ctx.translateBy(x: -lineOrigin.x, y: -lineOrigin.y)
            }

            if let icon = icon, let iconSize = iconSize {
                let rect = NSMakeRect(floorToScreenPixels((displayDimensions.width - iconSize.width)/2), floorToScreenPixels((displayDimensions.height - iconSize.height)/2), iconSize.width, iconSize.height)
                ctx.draw(icon, in: rect)
            }

        })
        subscriber.putNext(image)
        subscriber.putCompletion()
        return EmptyDisposable
    }
}
