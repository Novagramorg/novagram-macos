import Cocoa
import TGUIKit
import TelegramTheme

private let walletSendCommentFillLocations: [CGFloat] = [0.0, 0.10, 0.23, 0.40, 0.54, 0.70, 0.82, 1.0]
private let walletSendCommentFillShades: [CGFloat] = [250, 249, 246, 244, 246, 248, 249, 250]
private let walletSendCommentDarkFillAmounts: [CGFloat] = [0.048, 0.026, 0.013, 0.013, 0.018, 0.018, 0.022, 0.048]
private let walletSendCommentBorderLocations: [CGFloat] = [0.0, 0.20, 0.50, 0.80, 1.0]

final class WalletSendCommentBackgroundView: ImageView {
    struct Parameters: Equatable {
        let size: NSSize
        let scale: CGFloat
        let incoming: Bool
        let hasTail: Bool
        let backgroundColor: NSColor
        let textColor: NSColor
        let isDark: Bool
    }

    private var parameters: Parameters?

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    static func imageLayout(size: NSSize, hasTail: Bool) -> (size: NSSize, contentsCenter: NSRect) {
        guard !hasTail else {
            let capX = min(24, floor((size.width - 1) / 2))
            let capY = min(18, floor((size.height - 1) / 2))
            return (size, NSMakeRect(capX / size.width, capY / size.height, (size.width - capX * 2) / size.width, (size.height - capY * 2) / size.height))
        }
        let glowPadding = ceil(min(10.0, size.height * 0.24) * 2.0)
        let imageSize = NSMakeSize(min(size.width, size.height + glowPadding * 2.0 + 1.0), size.height)
        let capWidth = max(0, (imageSize.width - 1) / 2)
        return (imageSize, NSMakeRect(capWidth / imageSize.width, 0, 1 / imageSize.width, 1))
    }

    func update(size: NSSize, incoming: Bool = false, hasTail: Bool = true) {
        guard size.width > 0, size.height > 0 else {
            return
        }
        let layout = Self.imageLayout(size: size, hasTail: hasTail)
        let parameters = Parameters(size: layout.size, scale: backingScaleFactor, incoming: incoming, hasTail: hasTail, backgroundColor: theme.colors.background, textColor: theme.colors.text, isDark: theme.colors.isDark)
        guard self.parameters != parameters else {
            return
        }
        if let image = Self.makeImage(parameters: parameters) {
            self.parameters = parameters
            self.image = image
            layer?.contentsCenter = layout.contentsCenter
        }
    }

    static func makeImage(parameters: Parameters) -> CGImage? {
        let size = parameters.size
        let scale = parameters.scale
        let bounds = NSRect(origin: .zero, size: size)
        var flip = CGAffineTransform(translationX: 0, y: size.height).scaledBy(x: 1, y: -1)
        let cornerRadius = min(size.width, size.height) / 2
        let silhouette = parameters.hasTail ? walletCommentBubblePath(size, incoming: parameters.incoming) : CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        guard let bubble = silhouette.copy(using: &flip) else {
            return nil
        }
        func roundedRectMask(inset: CGFloat) -> CGImage? {
            return generateImage(size, contextGenerator: { _, context in
                context.clear(bounds)
                let radius = max(0, cornerRadius - inset)
                context.addPath(CGPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), cornerWidth: radius, cornerHeight: radius, transform: nil))
                context.setFillColor(NSColor.white.cgColor)
                context.fillPath()
            }, scale: scale)
        }
        guard let mask = generateImage(size, contextGenerator: { _, context in
            context.clear(bounds)
            context.addPath(bubble)
            context.setFillColor(NSColor.white.cgColor)
            context.fillPath()
        }, scale: scale) else {
            return nil
        }

        func insetMask(by inset: CGFloat) -> CGImage? {
            if !parameters.hasTail {
                return roundedRectMask(inset: inset)
            }
            return generateImage(size, contextGenerator: { _, context in
                context.clear(bounds)
                context.draw(mask, in: bounds)
                context.setBlendMode(.destinationIn)
                for index in 0 ..< 8 {
                    let angle = CGFloat(index) * .pi / 4.0
                    context.draw(mask, in: bounds.offsetBy(dx: cos(angle) * inset, dy: sin(angle) * inset))
                }
            }, scale: scale)
        }
        let contourScale: CGFloat = parameters.isDark ? 0.5 : 1.0
        guard let borderMask = insetMask(by: contourScale / scale), let rimMask = insetMask(by: 0.65 * contourScale), let innerMask = insetMask(by: 1.4 * contourScale) else {
            return nil
        }

        let glowRadius = min(10.0, size.height * 0.24)
        let padding = ceil(glowRadius * 2.0)
        let outsideSize = NSMakeSize(size.width + padding * 2.0, size.height + padding * 2.0)
        guard let outsideMask = generateImage(outsideSize, contextGenerator: { _, context in
            context.setFillColor(NSColor.white.cgColor)
            context.fill(NSRect(origin: .zero, size: outsideSize))
            context.setBlendMode(.destinationOut)
            context.draw(mask, in: bounds.offsetBy(dx: padding, dy: padding))
        }, scale: scale) else {
            return nil
        }

        func mix(_ color: NSColor, _ fraction: CGFloat) -> CGColor {
            return (parameters.backgroundColor.interpolateTo(color, fraction: fraction) ?? parameters.backgroundColor).cgColor
        }
        let fillColors: [CGColor]
        if parameters.isDark {
            fillColors = walletSendCommentDarkFillAmounts.map { mix(parameters.textColor, $0) }
        } else {
            fillColors = walletSendCommentFillShades.map { mix(parameters.textColor, (255 - $0) / 255) }
        }
        let highlightColor: NSColor
        if parameters.isDark {
            let (hue, saturation, _) = parameters.backgroundColor.hsb
            highlightColor = NSColor(hue: hue, saturation: saturation * 0.65, brightness: parameters.textColor.hsb.2, alpha: 1.0)
        } else {
            highlightColor = .white
        }
        let borderAmounts: [CGFloat] = parameters.isDark ? [0.26, 0.075, 0.013, 0.075, 0.26] : [0.10, 0.24, 0.33, 0.24, 0.11]
        let borderColors = borderAmounts.map { amount in
            mix(parameters.isDark ? highlightColor : parameters.textColor, amount)
        }
        let highlightAmounts: [CGFloat] = parameters.isDark ? [0.14, 0.03, 0.0, 0.03, 0.14] : [0.94, 0.94, 0.94, 0.94, 0.94]
        let highlightColors = highlightAmounts.map { highlightColor.withAlphaComponent($0).cgColor }
        guard let fillGradient = CGGradient(colorsSpace: deviceColorSpace, colors: fillColors as CFArray, locations: walletSendCommentFillLocations),
              let borderGradient = CGGradient(colorsSpace: deviceColorSpace, colors: borderColors as CFArray, locations: walletSendCommentBorderLocations),
              let highlightGradient = CGGradient(colorsSpace: deviceColorSpace, colors: highlightColors as CFArray, locations: walletSendCommentBorderLocations) else {
            return nil
        }
        let glowColor = highlightColor.withAlphaComponent(parameters.isDark ? 0.025 : 0.9)
        let body = bubble.boundingBoxOfPath
        let gradientStart = NSMakePoint(0, body.maxY)
        let gradientEnd = NSMakePoint(0, body.minY)

        return generateImage(size, contextGenerator: { _, context in
            context.clear(bounds)
            context.drawLinearGradient(fillGradient, start: gradientStart, end: gradientEnd, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

            context.saveGState()
            context.setShadow(offset: .zero, blur: glowRadius, color: glowColor.cgColor)
            context.draw(outsideMask, in: NSMakeRect(-padding, -padding, outsideSize.width, outsideSize.height))
            context.restoreGState()
            context.setBlendMode(.destinationIn)
            context.draw(mask, in: bounds)
            context.setBlendMode(.normal)

            func drawRing(outer: CGImage, inner: CGImage, fill: () -> Void) {
                context.saveGState()
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                context.draw(outer, in: bounds)
                context.setBlendMode(.destinationOut)
                context.draw(inner, in: bounds)
                context.setBlendMode(.sourceIn)
                fill()
                context.setBlendMode(.normal)
                context.endTransparencyLayer()
                context.restoreGState()
            }
            drawRing(outer: mask, inner: borderMask) {
                context.drawLinearGradient(borderGradient, start: gradientStart, end: gradientEnd, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            drawRing(outer: rimMask, inner: innerMask) {
                context.drawLinearGradient(highlightGradient, start: gradientStart, end: gradientEnd, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
        }, scale: scale)
    }
}
