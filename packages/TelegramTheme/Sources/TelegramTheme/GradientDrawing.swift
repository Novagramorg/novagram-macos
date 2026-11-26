import Cocoa
import TGUIKit

public let premiumGradient = [NSColor(rgb: 0x6B93FF), NSColor(rgb: 0x976FFF), NSColor(rgb: 0xE46ACE)]

public enum GradientImageDirection {
    case vertical
    case horizontal
    case diagonal
    case mirroredDiagonal
}

public func generateGradientTintedImage(image: CGImage?, colors: [NSColor], direction: GradientImageDirection = .vertical) -> CGImage? {
    guard let image = image else {
        return nil
    }

    let imageSize = image.systemSize

    return generateImage(imageSize, rotatedContext: { size, context in
        context.clear(size.bounds)

        let imageRect = CGRect(origin: CGPoint(), size: imageSize)
        context.saveGState()
        context.translateBy(x: imageRect.midX, y: imageRect.midY)
        context.scaleBy(x: 1.0, y: -1.0)
        context.translateBy(x: -imageRect.midX, y: -imageRect.midY)
        context.clip(to: imageRect, mask: image)

        if colors.count >= 2 {
            let gradientColors = colors.map { $0.cgColor } as CFArray

            var locations: [CGFloat] = []
            for i in 0 ..< colors.count {
                let t = CGFloat(i) / CGFloat(colors.count - 1)
                locations.append(t)
            }
            let colorSpace = DeviceGraphicsContextSettings.shared.colorSpace
            let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: &locations)!

            let start: CGPoint
            let end: CGPoint
            switch direction {
            case .horizontal:
                start = .zero
                end = CGPoint(x: imageRect.width, y: 0.0)
            case .vertical:
                start = CGPoint(x: 0.0, y: imageRect.height)
                end = .zero
            case .diagonal:
                start = CGPoint(x: 0.0, y: 0.0)
                end = CGPoint(x: imageRect.width, y: imageRect.height)
            case .mirroredDiagonal:
                start = CGPoint(x: imageRect.width, y: 0.0)
                end = CGPoint(x: 0.0, y: imageRect.height)
            }

            context.drawLinearGradient(gradient, start: start, end: end, options: CGGradientDrawingOptions())
        } else if !colors.isEmpty {
            context.setFillColor(colors[0].cgColor)
            context.fill(imageRect)
        }

        context.restoreGState()

    })

}

public func generateChatGroupToggleSelected(foregroundColor: NSColor, backgroundColor: NSColor) -> CGImage {
    let icon = TelegramThemeHooks.shared.image(.iconCheck).precomposed(foregroundColor)
    return generateImage(NSMakeSize(icon.backingSize.width + 2, icon.backingSize.height + 2), contextGenerator: { size, ctx in
        ctx.clear(NSMakeRect(0, 0, size.width, size.height))
        ctx.round(size, size.width/2)
        ctx.setFillColor(backgroundColor.cgColor)
        ctx.fill(NSMakeRect(0, 0, size.width, size.height))
        let imageRect = NSMakeRect((size.width - icon.backingSize.width) / 2, (size.height - icon.backingSize.height) / 2, icon.backingSize.width, icon.backingSize.height)
        ctx.draw(icon, in: imageRect)
    })!
}

public func generateChatGroupToggleUnselected(foregroundColor: NSColor, backgroundColor: NSColor) -> CGImage {
    let icon = TelegramThemeHooks.shared.image(.iconSelectionUncheck).precomposed(foregroundColor)
    return generateImage(NSMakeSize(icon.backingSize.width, icon.backingSize.height), contextGenerator: { size, ctx in
        ctx.clear(NSMakeRect(0, 0, size.width, size.height))
        ctx.round(size, size.width/2)
        ctx.setFillColor(backgroundColor.cgColor)
        ctx.fill(NSMakeRect(0, 0, size.width, size.height))
        let imageRect = NSMakeRect((size.width - icon.backingSize.width) / 2, (size.height - icon.backingSize.height) / 2, icon.backingSize.width, icon.backingSize.height)
        ctx.draw(icon, in: imageRect)
    })!
}
