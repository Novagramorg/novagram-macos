import Cocoa
import TGUIKit
import ColorPalette
import Localization

public func generatePremium(_ reversed: Bool = false, color: NSColor? = nil, small: Bool = false) -> CGImage {
    
    let draw: (NSSize, CGContext)->Void = { size, ctx in
        ctx.clear(CGRect(origin: CGPoint(), size: size))

        let image: CGImage
        if small {
            image = TelegramThemeHooks.shared.image(.iconPeerPremium).precomposed()
        } else {
            image = TelegramThemeHooks.shared.image(.iconPremiumStickerPack).precomposed()
        }
        ctx.clip(to: size.bounds, mask: image)

        if let color = color {
            ctx.setFillColor(color.cgColor)
            ctx.fill(size.bounds)
        } else {
            let colors = [NSColor(hexString: "#1391FF")!, NSColor(hexString: "#F977CC")!].map { $0.cgColor } as NSArray
            let delta: CGFloat = 1.0 / (CGFloat(colors.count) - 1.0)
            
            var locations: [CGFloat] = []
            for i in 0 ..< colors.count {
                locations.append(delta * CGFloat(i))
            }

            let colorSpace = deviceColorSpace
            let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: &locations)!
            
            ctx.drawLinearGradient(gradient, start: CGPoint(x: size.width, y: 0), end: CGPoint(x: 0.0, y: size.height), options: CGGradientDrawingOptions())
        }
        
    }
    
    let size: NSSize
    if small {
        size = NSMakeSize(16, 16)
    } else {
        size = NSMakeSize(24, 24)
    }
    if reversed {
        return generateImage(size, rotatedContext: { size, ctx in
            draw(size, ctx)
        })!
    } else {
        return generateImage(size, contextGenerator: { size, ctx in
            draw(size, ctx)
        })!
    }

}

public func generateCheckSelected(foregroundColor: NSColor, backgroundColor: NSColor) -> CGImage {
    let icon = TelegramThemeHooks.shared.image(.iconCheck).precomposed(foregroundColor)
    return generateImage(NSMakeSize(icon.backingSize.width, icon.backingSize.height), contextGenerator: { size, ctx in
        ctx.clear(NSMakeRect(0, 0, size.width, size.height))
        ctx.setFillColor(backgroundColor.cgColor)
        ctx.fillEllipse(in: NSMakeRect(2, 2, size.width - 4, size.height - 4))
        ctx.draw(icon, in: size.bounds)
    })!
}

public func generateTextIcon_NewBadge(bgColor: NSColor, textColor: NSColor) -> CGImage {
    return generateTextIcon_AccentBadge(text: strings().badgeNew, bgColor: bgColor, textColor: textColor)
}
