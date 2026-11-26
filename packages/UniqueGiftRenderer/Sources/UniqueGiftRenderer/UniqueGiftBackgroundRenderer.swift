import Foundation
import CoreGraphics

public final class UniqueGiftGlyph {
    public let template: CGImage
    public let mask: CGImage

    public init(template: CGImage, mask: CGImage) {
        self.template = template
        self.mask = mask
    }

    public convenience init?(image: CGImage) {
        guard let template = UniqueGiftBackgroundRenderer.makeGlyphTemplate(from: image), let mask = UniqueGiftBackgroundRenderer.makeGlyphMask(from: template) else {
            return nil
        }
        self.init(template: template, mask: mask)
    }
}

public enum UniqueGiftBackgroundRenderer {
    public static let colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    public static let glyphPixelSize: Int = 96

    public static func color(_ rgb: UInt32, alpha: CGFloat = 1.0) -> CGColor {
        let components: [CGFloat] = [
            CGFloat((rgb >> 16) & 0xff) / 255.0,
            CGFloat((rgb >> 8) & 0xff) / 255.0,
            CGFloat(rgb & 0xff) / 255.0,
            alpha
        ]
        return CGColor(colorSpace: colorSpace, components: components) ?? CGColor(gray: 0.0, alpha: alpha)
    }

    public static func makeGlyphTemplate(from image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            return nil
        }
        let rect = CGRect(x: 0.0, y: 0.0, width: CGFloat(width), height: CGFloat(height))
        context.draw(image, in: rect)
        context.setBlendMode(.sourceIn)
        context.setFillColor(color(0xffffff))
        context.fill(rect)
        return context.makeImage()
    }

    public static func makeGlyphMask(from template: CGImage) -> CGImage? {
        let width = template.width
        let height = template.height
        guard width > 0, height > 0, let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return nil
        }
        context.draw(template, in: CGRect(x: 0.0, y: 0.0, width: CGFloat(width), height: CGFloat(height)))
        return context.makeImage()
    }

    public static func renderColorSpace(_ target: CGColorSpace?) -> CGColorSpace {
        guard let target = target, target.model == .rgb, target.supportsOutput else {
            return colorSpace
        }
        return target
    }

    public static func makeImage(geometry: UniqueGiftBackgroundGeometry, colors: UniqueGiftColors, glyph: CGImage?, scale: CGFloat, colorSpace targetColorSpace: CGColorSpace? = nil) -> CGImage? {
        let pixelWidth = Int(ceil(geometry.size.width * scale))
        let pixelHeight = Int(ceil(geometry.size.height * scale))
        guard pixelWidth > 0, pixelHeight > 0, let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0, space: renderColorSpace(targetColorSpace), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            return nil
        }
        context.translateBy(x: 0.0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        draw(geometry: geometry, colors: colors, glyph: glyph, in: context, pixelSize: CGSize(width: pixelWidth, height: pixelHeight), scale: scale)
        return context.makeImage()
    }

    static func draw(geometry: UniqueGiftBackgroundGeometry, colors: UniqueGiftColors, glyph: CGImage?, in context: CGContext, pixelSize: CGSize, scale: CGFloat) {
        let bounds = CGRect(origin: .zero, size: geometry.size)
        context.saveGState()
        if geometry.cornerRadius > 0.0 {
            let radius = min(geometry.cornerRadius, min(bounds.width, bounds.height) / 2.0)
            context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.clip()
        }
        context.setFillColor(color(colors.edge))
        context.fill(bounds)

        drawEllipse(geometry.gradientEllipse, clip: geometry.gradientFrame.intersection(bounds), from: color(colors.center), to: color(colors.edge), in: context)

        if let glyph = glyph, let mask = makePatternMask(geometry: geometry, glyph: glyph, pixelSize: pixelSize, scale: scale) {
            let tintFrame = geometry.patternTintFrame.intersection(bounds)
            if !tintFrame.isNull && !tintFrame.isEmpty {
                context.saveGState()
                let transform = context.ctm
                context.concatenate(transform.inverted())
                context.clip(to: CGRect(origin: .zero, size: pixelSize), mask: mask)
                context.concatenate(transform)
                drawEllipse(geometry.patternTintEllipse, clip: tintFrame, from: color(colors.pattern, alpha: UniqueGiftBackgroundGeometry.patternTintAlpha), to: color(colors.pattern, alpha: 0.0), in: context)
                context.restoreGState()
            }
        }
        context.restoreGState()
    }

    private static func drawEllipse(_ ellipse: UniqueGiftEllipse, clip: CGRect, from: CGColor, to: CGColor, in context: CGContext) {
        guard ellipse.radii.width > 0.0, ellipse.radii.height > 0.0, !clip.isNull, !clip.isEmpty, let gradient = CGGradient(colorsSpace: colorSpace, colors: [from, to] as CFArray, locations: [0.0, 1.0]) else {
            return
        }
        context.saveGState()
        context.clip(to: clip)
        context.translateBy(x: ellipse.center.x, y: ellipse.center.y)
        context.scaleBy(x: ellipse.radii.width, y: ellipse.radii.height)
        context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0.0, endCenter: .zero, endRadius: 1.0, options: [.drawsAfterEndLocation])
        context.restoreGState()
    }

    private static func makePatternMask(geometry: UniqueGiftBackgroundGeometry, glyph: CGImage, pixelSize: CGSize, scale: CGFloat) -> CGImage? {
        guard let context = CGContext(data: nil, width: Int(pixelSize.width), height: Int(pixelSize.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return nil
        }
        context.interpolationQuality = .high
        context.setBlendMode(.screen)
        context.translateBy(x: 0.0, y: pixelSize.height)
        context.scaleBy(x: scale, y: -scale)
        let bounds = CGRect(origin: .zero, size: geometry.size)
        for item in geometry.patternItems() where item.alpha > 0.0 && item.frame.intersects(bounds) {
            context.saveGState()
            context.setAlpha(UniqueGiftBackgroundGeometry.patternGlyphAlpha * item.alpha)
            context.translateBy(x: item.frame.minX, y: item.frame.maxY)
            context.scaleBy(x: 1.0, y: -1.0)
            context.draw(glyph, in: CGRect(origin: .zero, size: item.frame.size))
            context.restoreGState()
        }
        return context.makeImage()
    }
}
