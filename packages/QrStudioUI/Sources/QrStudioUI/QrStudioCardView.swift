import Foundation
import Cocoa
import CoreText
import TGUIKit

private func qrStudioUsernameFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    if #available(macOS 10.15, *) {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.rounded), let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        return base
    }
    let name = weight == .heavy ? ".SFCompactRounded-Heavy" : ".SFCompactRounded-Bold"
    return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
}

private func qrStudioFontLineHeight(_ font: NSFont) -> CGFloat {
    return font.ascender - font.descender + font.leading
}

private func qrStudioUsernameText(_ username: String, size: CGFloat, color: NSColor) -> NSAttributedString {
    let text = NSMutableAttributedString()
    text.append(NSAttributedString(string: "@", attributes: [
        .font: qrStudioUsernameFont(size: size, weight: .heavy),
        .foregroundColor: color,
        .kern: -0.24
    ]))
    text.append(NSAttributedString(string: username.uppercased(), attributes: [
        .font: qrStudioUsernameFont(size: size, weight: .bold),
        .foregroundColor: color,
        .kern: -0.24
    ]))
    return text
}

private func qrStudioCardGradient(_ colors: [QrStudioColor]) -> [CGColor] {
    let dimmed = colors.map { QrStudioColor.mix($0, QrStudioColor(0.0, 0.0, 0.0), 0.3).cgColor }
    if dimmed.count == 1 {
        return [dimmed[0], dimmed[0]]
    }
    return dimmed
}

private struct QrStudioCardUsernameLayout {
    let username: String
    let frame: CGRect
    let fontSize: CGFloat
    let origin: CGPoint

    static func make(username: String, cardSize: CGSize) -> QrStudioCardUsernameLayout {
        let codeSide = QrStudioCardMetrics.codeSide
        let font = qrStudioUsernameFont(size: 24.0, weight: .bold)
        let lineHeight = qrStudioFontLineHeight(font)
        let height = ceil(lineHeight)
        let midY = (50.0 + codeSide + cardSize.height) * 0.5
        let baseline = midY + font.capHeight * 0.5
        let y = baseline - font.ascender - (height - lineHeight) * 0.5
        let scale = System.backingScale
        let frame = CGRect(x: 20.0, y: (y * scale).rounded() / scale, width: cardSize.width - 40.0, height: height)

        var fontSize: CGFloat = 24.0
        var width = QrStudioCardUsernameLayout.lineWidth(username: username, size: fontSize)
        var attempts = 0
        while width > frame.width, fontSize > 12.0, attempts < 8 {
            fontSize = max(12.0, min(fontSize - 0.25, floor(fontSize * frame.width / width * 4.0) / 4.0))
            width = QrStudioCardUsernameLayout.lineWidth(username: username, size: fontSize)
            attempts += 1
        }
        let fitted = qrStudioUsernameFont(size: fontSize, weight: .bold)
        let baselineY = (frame.height - qrStudioFontLineHeight(fitted)) * 0.5 + fitted.ascender
        return QrStudioCardUsernameLayout(username: username, frame: frame, fontSize: fontSize, origin: CGPoint(x: 0.0, y: baselineY))
    }

    private static func lineWidth(username: String, size: CGFloat) -> CGFloat {
        let line = CTLineCreateWithAttributedString(qrStudioUsernameText(username, size: size, color: .black))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    func line(color: NSColor) -> CTLine {
        let line = CTLineCreateWithAttributedString(qrStudioUsernameText(self.username, size: self.fontSize, color: color))
        if CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) <= self.frame.width {
            return line
        }
        let token = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2026}", attributes: [
            .font: qrStudioUsernameFont(size: self.fontSize, weight: .bold),
            .foregroundColor: color
        ]))
        return CTLineCreateTruncatedLine(line, Double(self.frame.width), .end, token) ?? line
    }

    func image(color: NSColor, scale: CGFloat) -> CGImage? {
        let line = self.line(color: color)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let x = (self.frame.width - width) * 0.5
        return qrStudioRenderFlippedImage(size: self.frame.size, scale: scale, { context in
            context.textMatrix = .identity
            context.saveGState()
            context.translateBy(x: x, y: self.origin.y)
            context.scaleBy(x: 1.0, y: -1.0)
            context.textPosition = CGPoint()
            CTLineDraw(line, context)
            context.restoreGState()
        })
    }
}

private final class QrStudioCardFill {
    let colors: [QrStudioColor]
    let codeLayer = SimpleGradientLayer()
    let usernameLayer = SimpleGradientLayer()

    var layers: [CALayer] {
        return [self.codeLayer, self.usernameLayer]
    }

    init(colors: [QrStudioColor]) {
        self.colors = colors
        let gradient = qrStudioCardGradient(colors)
        for layer in [self.codeLayer, self.usernameLayer] {
            layer.colors = gradient
            layer.startPoint = CGPoint(x: 0.0, y: 0.0)
            layer.endPoint = CGPoint(x: 1.0, y: 1.0)
        }
    }

    func remove() {
        for layer in self.layers {
            layer.removeFromSuperlayer()
        }
    }
}

final class QrStudioCardView: View {
    private struct State {
        let link: String
        let username: String?
        let ink: QrStudioColor
        let isLight: Bool
        let bounceToken: String
        let fillColors: [QrStudioColor]?
    }

    private let contentView = View()
    private let backgroundView = View()
    private let codeView = QrStudioCodeView(frame: .zero)
    private let usernameView = View()
    private let usernameLayer = SimpleLayer()
    private let usernameFillHost = SimpleLayer()
    private let usernameMaskLayer = SimpleLayer()

    private var state: State?
    private var matrix: QrCodeMatrix?
    private var matrixLink: String?
    private var cardSize = CGSize()
    private var usernameLayout: QrStudioCardUsernameLayout?
    private var usernameImageKey: String?
    private var fills: [QrStudioCardFill] = []
    private var isRemovingFill = false

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        self.layer?.masksToBounds = false
        self.layer?.isOpaque = false

        self.contentView.isEventLess = true
        self.contentView.layer?.masksToBounds = false
        self.contentView.layer?.isOpaque = false
        self.contentView.layer?.shadowColor = NSColor.black.cgColor
        self.contentView.layer?.shadowRadius = 22.0
        self.contentView.layer?.shadowOffset = CGSize()
        self.contentView.layer?.shadowOpacity = 0.0
        self.addSubview(self.contentView)

        self.backgroundView.isEventLess = true
        self.backgroundView.backgroundColor = .white
        self.backgroundView.layer?.cornerRadius = QrStudioCardMetrics.cornerRadius
        if #available(macOS 10.15, *) {
            self.backgroundView.layer?.cornerCurve = .continuous
        }
        self.contentView.addSubview(self.backgroundView)
        self.contentView.addSubview(self.codeView)

        self.usernameView.isEventLess = true
        self.usernameView.layer?.masksToBounds = false
        self.usernameView.layer?.isOpaque = false
        self.usernameLayer.contentsGravity = .resize
        self.usernameMaskLayer.contentsGravity = .resize
        self.usernameFillHost.mask = self.usernameMaskLayer
        self.usernameFillHost.isHidden = true
        self.usernameView.layer?.addSublayer(self.usernameLayer)
        self.usernameView.layer?.addSublayer(self.usernameFillHost)
        self.contentView.addSubview(self.usernameView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func centeredScale(_ scale: CGFloat, size: CGSize) -> NSValue {
        var transform = CATransform3DMakeTranslation(size.width * 0.5, size.height * 0.5, 0.0)
        transform = CATransform3DScale(transform, scale, scale, 1.0)
        transform = CATransform3DTranslate(transform, -size.width * 0.5, -size.height * 0.5, 0.0)
        return NSValue(caTransform3D: transform)
    }

    private func animateBounce(size: CGSize) {
        guard let layer = self.contentView.layer else {
            return
        }
        let dip = CABasicAnimation(keyPath: "transform")
        dip.fromValue = self.centeredScale(1.0, size: size)
        dip.toValue = self.centeredScale(0.95, size: size)
        dip.duration = 0.12
        dip.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = self.centeredScale(0.95, size: size)
        spring.toValue = self.centeredScale(1.0, size: size)
        spring.mass = 1.0
        spring.stiffness = 130.5
        spring.damping = 11.42
        spring.beginTime = 0.12
        spring.duration = 0.7

        let group = CAAnimationGroup()
        group.animations = [dip, spring]
        group.duration = 0.82
        layer.add(group, forKey: "bounce")
    }

    func update(link: String, username: String?, ink: QrStudioColor, isLight: Bool, bounceToken: String, fillColors: [QrStudioColor]?, transition: ContainedViewLayoutTransition) -> CGSize {
        let previous = self.state
        self.state = State(link: link, username: username, ink: ink, isLight: isLight, bounceToken: bounceToken, fillColors: fillColors)

        if self.matrixLink != link {
            self.matrixLink = link
            if !link.isEmpty, let matrix = qrCodeMatrix(string: link, ecl: "Q") {
                self.matrix = matrix
            }
        }

        let size = CGSize(width: QrStudioCardMetrics.width, height: QrStudioCardMetrics.height(showsUsername: username != nil))
        self.cardSize = size
        let bounds = CGRect(origin: CGPoint(), size: size)

        if let previous, previous.bounceToken != bounceToken, transition.isAnimated {
            self.animateBounce(size: size)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.contentView.frame = bounds
        self.backgroundView.frame = bounds
        self.contentView.layer?.shadowPath = CGPath(roundedRect: bounds.offsetBy(dx: 0.0, dy: 12.0), cornerWidth: QrStudioCardMetrics.cornerRadius, cornerHeight: QrStudioCardMetrics.cornerRadius, transform: nil)
        CATransaction.commit()

        if let contentLayer = self.contentView.layer {
            let shadowOpacity: Float = isLight ? 0.12 : 0.0
            if contentLayer.shadowOpacity != shadowOpacity {
                if transition.isAnimated {
                    let animation = CABasicAnimation(keyPath: "shadowOpacity")
                    animation.fromValue = contentLayer.presentation()?.shadowOpacity ?? contentLayer.shadowOpacity
                    animation.toValue = shadowOpacity
                    animation.duration = 0.45
                    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    contentLayer.add(animation, forKey: "shadowOpacity")
                }
                contentLayer.shadowOpacity = shadowOpacity
            }
        }

        let codeSide = QrStudioCardMetrics.codeSide
        self.codeView.frame = CGRect(x: (size.width - codeSide) * 0.5, y: 50.0, width: codeSide, height: codeSide)

        if let username {
            let layout = QrStudioCardUsernameLayout.make(username: username, cardSize: size)
            self.usernameLayout = layout
            self.usernameView.frame = layout.frame
            let usernameBounds = CGRect(origin: CGPoint(), size: layout.frame.size)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.usernameLayer.frame = usernameBounds
            self.usernameFillHost.frame = usernameBounds
            self.usernameMaskLayer.frame = usernameBounds
            CATransaction.commit()
        } else {
            self.usernameLayout = nil
        }

        let animated = previous != nil && transition.isAnimated
        self.updateFill(colors: fillColors, size: size, animated: animated)
        let linkChanged = previous.flatMap { $0.link != link } ?? false
        self.applyInk(ink: ink, animated: animated, animatesCode: linkChanged)

        return size
    }

    private func layoutFills(size: CGSize) {
        let codeOrigin = self.codeView.frame.origin
        let usernameOrigin = self.usernameLayout?.frame.origin ?? CGPoint()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for fill in self.fills {
            fill.codeLayer.frame = CGRect(origin: CGPoint(x: -codeOrigin.x, y: -codeOrigin.y), size: size)
            fill.usernameLayer.frame = CGRect(origin: CGPoint(x: -usernameOrigin.x, y: -usernameOrigin.y), size: size)
        }
        CATransaction.commit()
        self.codeView.fillHost.isHidden = self.fills.isEmpty
        self.usernameFillHost.isHidden = self.fills.isEmpty
    }

    private func updateFill(colors: [QrStudioColor]?, size: CGSize, animated: Bool) {
        let fadeTransition: ContainedViewLayoutTransition = .animated(duration: 0.5, curve: .easeInOut)
        if let colors, !colors.isEmpty {
            let wasRemoving = self.isRemovingFill
            self.isRemovingFill = false
            if self.fills.last?.colors != colors {
                let fill = QrStudioCardFill(colors: colors)
                self.codeView.fillHost.addSublayer(fill.codeLayer)
                self.usernameFillHost.addSublayer(fill.usernameLayer)
                self.fills.append(fill)
                self.layoutFills(size: size)
                if animated {
                    for layer in fill.layers {
                        layer.opacity = 0.0
                    }
                    fadeTransition.updateAlpha(layer: fill.usernameLayer, alpha: 1.0)
                    fadeTransition.updateAlpha(layer: fill.codeLayer, alpha: 1.0, completion: { [weak self, weak fill] _ in
                        guard let self, let fill, let index = self.fills.firstIndex(where: { $0 === fill }) else {
                            return
                        }
                        for previous in self.fills[..<index] {
                            previous.remove()
                        }
                        self.fills.removeFirst(index)
                    })
                } else {
                    for previous in self.fills.dropLast() {
                        previous.remove()
                    }
                    self.fills = [fill]
                }
            } else if wasRemoving, let fill = self.fills.last {
                let restoreTransition: ContainedViewLayoutTransition = animated ? fadeTransition : .immediate
                for layer in fill.layers {
                    restoreTransition.updateAlpha(layer: layer, alpha: 1.0)
                }
            }
        } else if !self.fills.isEmpty, !self.isRemovingFill {
            if animated {
                self.isRemovingFill = true
                let fills = self.fills
                for (index, fill) in fills.enumerated() {
                    for layer in fill.layers {
                        if index == fills.count - 1 && layer === fill.codeLayer {
                            fadeTransition.updateAlpha(layer: layer, alpha: 0.0, completion: { [weak self] _ in
                                guard let self, self.isRemovingFill else {
                                    return
                                }
                                self.removeFills()
                            })
                        } else {
                            fadeTransition.updateAlpha(layer: layer, alpha: 0.0)
                        }
                    }
                }
            } else {
                self.removeFills()
            }
        }
        self.layoutFills(size: size)
    }

    private func removeFills() {
        for fill in self.fills {
            fill.remove()
        }
        self.fills = []
        self.isRemovingFill = false
        self.codeView.fillHost.isHidden = true
        self.usernameFillHost.isHidden = true
    }

    private func applyInk(ink: QrStudioColor, animated: Bool, animatesCode: Bool) {
        let codeTransition: ContainedViewLayoutTransition = animated || animatesCode ? .animated(duration: 0.5, curve: .easeInOut) : .immediate
        self.codeView.update(matrix: self.matrix, ink: ink, transition: codeTransition, animatesInk: animated)

        guard let layout = self.usernameLayout else {
            self.usernameView.isHidden = true
            self.usernameImageKey = nil
            return
        }
        let scale = System.backingScale
        let key = "\(layout.username)|\(ink.rgb)|\(layout.fontSize)|\(layout.frame.width)x\(layout.frame.height)|\(scale)"
        if self.usernameImageKey != key {
            let hadImage = self.usernameImageKey != nil
            self.usernameImageKey = key
            let image = layout.image(color: ink.nsColor, scale: scale)
            if animated, hadImage {
                let fade = CATransition()
                fade.type = .fade
                fade.duration = 0.5
                fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.usernameLayer.add(fade, forKey: "contents")
            }
            self.usernameLayer.contentsScale = scale
            self.usernameLayer.contents = image
            self.usernameMaskLayer.contentsScale = scale
            self.usernameMaskLayer.contents = image
        }
        self.usernameView.isHidden = false
    }

    private func drawGradient(_ colors: [CGColor], size: CGSize, context: CGContext) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil) else {
            return
        }
        context.saveGState()
        context.scaleBy(x: size.width, y: size.height)
        context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 1.0, y: 1.0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }

    func exportImage(scale: CGFloat) -> CGImage? {
        guard let state = self.state else {
            return nil
        }
        let size = self.cardSize
        guard size.width > 0.0, size.height > 0.0, scale > 0.0 else {
            return nil
        }
        let ink = state.ink
        var gradientColors: [CGColor]?
        if let fillColors = state.fillColors, !fillColors.isEmpty {
            gradientColors = qrStudioCardGradient(fillColors)
        }
        let codeFrame = self.codeView.frame
        let paths = self.codeView.paths
        let logoFrame = self.codeView.logoFrame
        let planeFrame = self.codeView.planeFrame.offsetBy(dx: codeFrame.minX, dy: codeFrame.minY)
        var planeImage: CGImage?
        if paths != nil {
            planeImage = qrStudioDecodeExportPlane(pixelSide: Int(ceil(planeFrame.width * scale)))?.frames.first ?? self.codeView.planeImage
        }
        let usernameLayout = self.usernameLayout
        let usernameImage = usernameLayout?.image(color: ink.nsColor, scale: scale)

        return qrStudioRenderFlippedImage(size: size, scale: scale, { context in
            let bounds = CGRect(origin: CGPoint(), size: size)
            context.addPath(CGPath(roundedRect: bounds, cornerWidth: QrStudioCardMetrics.cornerRadius, cornerHeight: QrStudioCardMetrics.cornerRadius, transform: nil))
            context.setFillColor(NSColor.white.cgColor)
            context.fillPath()

            if let paths {
                let shapes: [(CGPath, CGPathFillRule)] = [
                    (paths.body, .winding),
                    (paths.frames, .evenOdd),
                    (paths.balls, .winding),
                    (CGPath(ellipseIn: logoFrame, transform: nil), .winding)
                ]
                context.saveGState()
                context.translateBy(x: codeFrame.minX, y: codeFrame.minY)
                context.setFillColor(ink.cgColor)
                for (path, rule) in shapes {
                    context.addPath(path)
                    context.fillPath(using: rule)
                }
                context.restoreGState()

                if let gradientColors {
                    for (path, rule) in shapes {
                        context.saveGState()
                        context.translateBy(x: codeFrame.minX, y: codeFrame.minY)
                        context.addPath(path)
                        context.clip(using: rule)
                        context.translateBy(x: -codeFrame.minX, y: -codeFrame.minY)
                        self.drawGradient(gradientColors, size: size, context: context)
                        context.restoreGState()
                    }
                }

                if let planeImage {
                    qrStudioDrawFlipped(planeImage, in: planeFrame, context: context)
                }
            }

            if let usernameLayout, let usernameImage {
                let frame = usernameLayout.frame
                qrStudioDrawFlipped(usernameImage, in: frame, context: context)
                if let gradientColors {
                    context.saveGState()
                    context.translateBy(x: frame.minX, y: frame.maxY)
                    context.scaleBy(x: 1.0, y: -1.0)
                    context.clip(to: CGRect(origin: CGPoint(), size: frame.size), mask: usernameImage)
                    context.scaleBy(x: 1.0, y: -1.0)
                    context.translateBy(x: -frame.minX, y: -frame.maxY)
                    self.drawGradient(gradientColors, size: size, context: context)
                    context.restoreGState()
                }
            }
        })
    }
}
