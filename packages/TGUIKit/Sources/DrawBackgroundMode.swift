import Cocoa
import ColorPalette

public func drawBg(_ backgroundMode: TableBackgroundMode, palette: ColorPalette, bubbled: Bool, rect: NSRect, in ctx: CGContext) {
    switch backgroundMode {
    case let .background(image, intensity, colors, rotation, _):
        let imageSize = image.size.aspectFilled(rect.size)
        ctx.saveGState()

        if let colors = colors, !colors.isEmpty {
            
            if palette.isDark {
                ctx.setBlendMode(.normal)
                ctx.clear(rect.focus(imageSize))
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.fill(rect.focus(imageSize))
                ctx.clip(to: rect.focus(imageSize), mask: image._cgImage!)
            }
            
            if colors.count > 2 {
                let preview = AnimatedGradientBackgroundView.generatePreview(size: NSMakeSize(200, 100).fitted(NSMakeSize(32, 32)), colors: colors)
                
                ctx.saveGState()
                ctx.translateBy(x: rect.width / 2.0, y: rect.height / 2.0)
                ctx.scaleBy(x: 1, y: -1.0)
                ctx.translateBy(x: -rect.width / 2.0, y: -rect.height / 2.0)

                ctx.draw(preview, in: rect.focus(NSMakeSize(500, 500)))
                ctx.restoreGState()
                
            } else if colors.count > 1 {
                let gradient = CGGradient.evenlySpaced(colors)!
                ctx.saveGState()
                ctx.translateBy(x: rect.width / 2.0, y: rect.height / 2.0)
                ctx.rotate(by: CGFloat(rotation ?? 0) * CGFloat.pi / -180.0)
                ctx.translateBy(x: -rect.width / 2.0, y: -rect.height / 2.0)
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 0.0, y: rect.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                ctx.restoreGState()
            } else if let color = colors.first {
                ctx.setFillColor(color.cgColor)
                ctx.fill(rect)
            }
        }
        
        if let colors = colors, !colors.isEmpty {
            if let image = image._cgImage {
                if !palette.isDark {
                    ctx.setBlendMode(.softLight)
                    ctx.setAlpha(CGFloat(abs(intensity ?? 50)) / 100.0)
                }
                ctx.draw(image, in: rect.focus(imageSize))
            }
        } else if let image = image._cgImage {
            ctx.saveGState()
            ctx.translateBy(x: rect.width / 2.0, y: rect.height / 2.0)
            ctx.scaleBy(x: 1, y: -1.0)
            ctx.translateBy(x: -rect.width / 2.0, y: -rect.height / 2.0)
            ctx.draw(image, in: rect.focus(imageSize))
            ctx.restoreGState()
        }
        ctx.restoreGState()
    case let .color(color):
        ctx.setFillColor(color.cgColor)
        ctx.fill(rect)
    case let .gradient(colors, rotation):
        if bubbled {
            if colors.count > 2 {
                let preview = AnimatedGradientBackgroundView.generatePreview(size: rect.size.fitted(NSMakeSize(32, 32)), colors: colors)
                ctx.saveGState()
                ctx.translateBy(x: rect.width / 2.0, y: rect.height / 2.0)
                ctx.scaleBy(x: 1, y: -1.0)
                ctx.translateBy(x: -rect.width / 2.0, y: -rect.height / 2.0)

                ctx.draw(preview, in: rect.size.bounds)
                ctx.restoreGState()
            } else {
                let gradient = CGGradient.evenlySpaced(Array(colors.reversed()))!
                ctx.saveGState()
                ctx.translateBy(x: rect.width / 2.0, y: rect.height / 2.0)
                ctx.rotate(by: CGFloat(rotation ?? 0) * CGFloat.pi / -180.0)
                ctx.translateBy(x: -rect.width / 2.0, y: -rect.height / 2.0)
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 0.0, y: rect.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                ctx.restoreGState()
            }
        }
    default:
        break
    }
}
