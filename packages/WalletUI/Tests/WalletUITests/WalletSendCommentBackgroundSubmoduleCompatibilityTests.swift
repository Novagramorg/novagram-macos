import XCTest
import Cocoa
import ColorPalette
import TGUIKit
@testable import WalletUI

private struct SubmoduleCommentStyle {
    let contourScale: (dark: CGFloat, light: CGFloat)
    let rimInset: CGFloat
    let innerInset: CGFloat
    let fillLocations: [CGFloat]
    let darkFillAmounts: [CGFloat]
    let lightFillShades: [UInt32]
    let highlightSaturation: CGFloat
    let borderLocations: [CGFloat]
    let borderAmounts: (dark: [CGFloat], light: [CGFloat])
    let glowAlpha: (dark: CGFloat, light: CGFloat)
    let highlightAmounts: (dark: [CGFloat], light: [CGFloat])

    init?(source: String) {
        func groups(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) else {
                return nil
            }
            return (1 ..< match.numberOfRanges).compactMap { Range(match.range(at: $0), in: source).map { String(source[$0]) } }
        }
        func numbers(_ list: String) -> [CGFloat] {
            return list.components(separatedBy: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)).map { CGFloat($0) } }
        }
        func number(_ text: String) -> CGFloat? {
            return Double(text).map { CGFloat($0) }
        }
        guard let contour = groups(#"let contourScale: CGFloat = parameters\.isDark \? ([0-9.]+) : ([0-9.]+)"#),
              let rim = groups(#"let rimMask = insetMask\(by: ([0-9.]+) \* contourScale\)"#),
              let inner = groups(#"let innerMask = insetMask\(by: ([0-9.]+) \* contourScale\)"#),
              let fillLocations = groups(#"let fillLocations: \[CGFloat\] = \[([^\]]+)\]"#),
              let fillAmounts = groups(#"let fillAmounts: \[CGFloat\] = \[([^\]]+)\]"#),
              let fillShades = groups(#"let fillShades: \[UInt32\] = \[([^\]]+)\]"#),
              let saturation = groups(#"saturation: saturation \* ([0-9.]+)"#),
              let borderLocations = groups(#"let borderLocations: \[CGFloat\] = \[([^\]]+)\]"#),
              let borderAmounts = groups(#"let borderAmounts: \[CGFloat\] = parameters\.isDark \? \[([^\]]+)\] : \[([^\]]+)\]"#),
              let glow = groups(#"let glowColor = highlightColor\.withAlphaComponent\(parameters\.isDark \? ([0-9.]+) : ([0-9.]+)\)"#),
              let highlightAmounts = groups(#"let highlightAmounts: \[CGFloat\] = parameters\.isDark \? \[([^\]]+)\] : \[([^\]]+)\]"#),
              let darkContour = number(contour[0]), let lightContour = number(contour[1]),
              let rimInset = number(rim[0]), let innerInset = number(inner[0]),
              let highlightSaturation = number(saturation[0]),
              let darkGlow = number(glow[0]), let lightGlow = number(glow[1]) else {
            return nil
        }
        self.contourScale = (darkContour, lightContour)
        self.rimInset = rimInset
        self.innerInset = innerInset
        self.fillLocations = numbers(fillLocations[0])
        self.darkFillAmounts = numbers(fillAmounts[0])
        self.lightFillShades = fillShades[0].components(separatedBy: ",").compactMap { UInt32($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "0x", with: ""), radix: 16) }
        self.highlightSaturation = highlightSaturation
        self.borderLocations = numbers(borderLocations[0])
        self.borderAmounts = (numbers(borderAmounts[0]), numbers(borderAmounts[1]))
        self.glowAlpha = (darkGlow, lightGlow)
        self.highlightAmounts = (numbers(highlightAmounts[0]), numbers(highlightAmounts[1]))
    }
}

private let submoduleCommentStyle: SubmoduleCommentStyle? = {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletSendScreen/Sources/WalletSendCommentBackgroundView.swift")
    return (try? String(contentsOf: url, encoding: .utf8)).flatMap(SubmoduleCommentStyle.init(source:))
}()

private func submoduleColor(_ rgb: UInt32) -> NSColor {
    return NSColor(deviceRed: CGFloat((rgb >> 16) & 0xff) / 255.0, green: CGFloat((rgb >> 8) & 0xff) / 255.0, blue: CGFloat(rgb & 0xff) / 255.0, alpha: 1.0)
}

private func submoduleMixedWith(_ color: NSColor, _ other: NSColor, alpha: CGFloat) -> NSColor {
    let alpha = min(1.0, max(0.0, alpha))
    let oneMinusAlpha = 1.0 - alpha
    var r1: CGFloat = 0.0, r2: CGFloat = 0.0, g1: CGFloat = 0.0, g2: CGFloat = 0.0, b1: CGFloat = 0.0, b2: CGFloat = 0.0, a1: CGFloat = 0.0, a2: CGFloat = 0.0
    color.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
    other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
    return NSColor(deviceRed: r1 * oneMinusAlpha + r2 * alpha, green: g1 * oneMinusAlpha + g2 * alpha, blue: b1 * oneMinusAlpha + b2 * alpha, alpha: a1 * oneMinusAlpha + a2 * alpha)
}

private func submoduleGenerate(_ size: CGSize, scale: CGFloat, _ draw: (CGContext) -> Void) -> CGImage? {
    guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
        return nil
    }
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: 0.0, y: size.height)
    context.scaleBy(x: 1.0, y: -1.0)
    draw(context)
    return context.makeImage()
}

private func submoduleDraw(_ context: CGContext, _ image: CGImage, in rect: CGRect, blendMode: CGBlendMode = .normal) {
    context.saveGState()
    context.setBlendMode(blendMode)
    context.translateBy(x: 0.0, y: rect.minY + rect.maxY)
    context.scaleBy(x: 1.0, y: -1.0)
    context.draw(image, in: rect)
    context.restoreGState()
}

private func submoduleCommentBackground(size: CGSize, scale: CGFloat, backgroundColor: NSColor, primaryTextColor: NSColor, isDark: Bool, silhouette: CGPath, style: SubmoduleCommentStyle, hasTail: Bool = true, maxCornerRadius: CGFloat = 0.0) -> CGImage? {
    let bounds = CGRect(origin: .zero, size: size)
    func roundedRectMask(inset: CGFloat) -> CGImage? {
        return submoduleGenerate(size, scale: scale, { context in
            context.clear(bounds)
            let cornerRadius = max(0.0, min(maxCornerRadius, min(size.width, size.height) * 0.5) - inset)
            context.addPath(CGPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
            context.setFillColor(NSColor.white.cgColor)
            context.fillPath()
        })
    }
    let shapeMask: CGImage?
    if hasTail {
        shapeMask = submoduleGenerate(size, scale: scale, { context in
            context.clear(bounds)
            context.addPath(silhouette)
            context.setFillColor(NSColor.white.cgColor)
            context.fillPath()
        })
    } else {
        shapeMask = roundedRectMask(inset: 0.0)
    }
    guard let mask = shapeMask else { return nil }

    func insetMask(by inset: CGFloat) -> CGImage? {
        if !hasTail {
            return roundedRectMask(inset: inset)
        }
        return submoduleGenerate(size, scale: scale, { context in
            context.clear(bounds)
            submoduleDraw(context, mask, in: bounds)
            for index in 0 ..< 8 {
                let angle = CGFloat(index) * .pi / 4.0
                submoduleDraw(context, mask, in: bounds.offsetBy(dx: cos(angle) * inset, dy: sin(angle) * inset), blendMode: .destinationIn)
            }
        })
    }
    let contourScale: CGFloat = isDark ? style.contourScale.dark : style.contourScale.light
    guard let borderMask = insetMask(by: contourScale / scale),
          let rimMask = insetMask(by: style.rimInset * contourScale),
          let innerMask = insetMask(by: style.innerInset * contourScale) else { return nil }

    let glowRadius = min(10.0, size.height * 0.24)
    let padding = ceil(glowRadius * 2.0)
    let outsideSize = CGSize(width: size.width + padding * 2.0, height: size.height + padding * 2.0)
    guard let outsideMask = submoduleGenerate(outsideSize, scale: scale, { context in
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: outsideSize))
        submoduleDraw(context, mask, in: bounds.offsetBy(dx: padding, dy: padding), blendMode: .destinationOut)
    }) else { return nil }

    let fillColors: [CGColor]
    if isDark {
        fillColors = style.darkFillAmounts.map { amount in
            submoduleMixedWith(backgroundColor, primaryTextColor, alpha: amount).cgColor
        }
    } else {
        fillColors = style.lightFillShades.map { submoduleColor($0).cgColor }
    }
    guard let fillGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: fillColors as CFArray, locations: style.fillLocations) else { return nil }
    let highlightColor: NSColor
    if isDark {
        var hue: CGFloat = 0.0
        var saturation: CGFloat = 0.0
        backgroundColor.getHue(&hue, saturation: &saturation, brightness: nil, alpha: nil)
        var brightness: CGFloat = 0.0
        primaryTextColor.getHue(nil, saturation: nil, brightness: &brightness, alpha: nil)
        highlightColor = NSColor(hue: hue, saturation: saturation * style.highlightSaturation, brightness: brightness, alpha: 1.0)
    } else {
        highlightColor = .white
    }

    let borderAmounts = isDark ? style.borderAmounts.dark : style.borderAmounts.light
    let borderColors = borderAmounts.map { amount in
        submoduleMixedWith(backgroundColor, isDark ? highlightColor : primaryTextColor, alpha: amount).cgColor
    }
    guard let borderGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: borderColors as CFArray, locations: style.borderLocations) else { return nil }
    let glowColor = highlightColor.withAlphaComponent(isDark ? style.glowAlpha.dark : style.glowAlpha.light)
    let highlightAmounts = isDark ? style.highlightAmounts.dark : style.highlightAmounts.light
    let highlightColors = highlightAmounts.map { highlightColor.withAlphaComponent($0).cgColor }
    guard let highlightGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: highlightColors as CFArray, locations: style.borderLocations) else { return nil }
    let body = hasTail ? silhouette.boundingBoxOfPath : bounds

    return submoduleGenerate(size, scale: scale, { context in
        context.clear(bounds)
        context.drawLinearGradient(fillGradient, start: CGPoint(x: 0.0, y: body.minY), end: CGPoint(x: 0.0, y: body.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

        context.saveGState()
        context.setShadow(offset: .zero, blur: glowRadius, color: glowColor.cgColor)
        submoduleDraw(context, outsideMask, in: CGRect(x: -padding, y: -padding, width: outsideSize.width, height: outsideSize.height))
        context.restoreGState()
        submoduleDraw(context, mask, in: bounds, blendMode: .destinationIn)

        func drawRing(outer: CGImage, inner: CGImage, fill: () -> Void) {
            context.saveGState()
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            submoduleDraw(context, outer, in: bounds)
            submoduleDraw(context, inner, in: bounds, blendMode: .destinationOut)
            context.setBlendMode(.sourceIn)
            fill()
            context.setBlendMode(.normal)
            context.endTransparencyLayer()
            context.restoreGState()
        }
        drawRing(outer: mask, inner: borderMask) {
            context.drawLinearGradient(borderGradient, start: CGPoint(x: 0.0, y: body.minY), end: CGPoint(x: 0.0, y: body.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        drawRing(outer: rimMask, inner: innerMask) {
            context.drawLinearGradient(highlightGradient, start: CGPoint(x: 0.0, y: body.minY), end: CGPoint(x: 0.0, y: body.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    })
}

private func submoduleRGBAPixels(_ image: CGImage) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return data
}

final class WalletSendCommentBackgroundSubmoduleCompatibilityTests: XCTestCase {
    private let sizes: [NSSize] = [NSMakeSize(60, 34), NSMakeSize(140, 34), NSMakeSize(260, 34), NSMakeSize(180, 48)]
    private let scales: [CGFloat] = [1, 2]

    private let pillSizes: [NSSize] = [NSMakeSize(20, 26), NSMakeSize(40, 26), NSMakeSize(51, 26), NSMakeSize(95, 26), NSMakeSize(260, 26), NSMakeSize(90, 34)]

    private func submoduleSource(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletSendScreen/Sources").appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func submoduleTaillessImageSize(_ size: NSSize, maxCornerRadius: CGFloat) -> NSSize {
        let glowPadding = ceil(min(10.0, size.height * 0.24) * 2.0)
        return NSMakeSize(min(size.width, maxCornerRadius * 2.0 + glowPadding * 2.0 + 1.0), size.height)
    }

    private func actualTaillessImage(_ palette: ColorPalette, size: NSSize, scale: CGFloat) -> CGImage? {
        let layout = WalletSendCommentBackgroundView.imageLayout(size: size, hasTail: false)
        return WalletSendCommentBackgroundView.makeImage(parameters: .init(size: layout.size, scale: scale, incoming: false, hasTail: false, backgroundColor: palette.background, textColor: palette.text, isDark: palette.isDark))
    }

    private func submoduleTaillessImage(_ palette: ColorPalette, size: NSSize, scale: CGFloat) -> CGImage? {
        guard let style = submoduleCommentStyle else {
            return nil
        }
        let maxCornerRadius = size.height / 2.0
        let imageSize = submoduleTaillessImageSize(size, maxCornerRadius: maxCornerRadius)
        return submoduleCommentBackground(size: imageSize, scale: scale, backgroundColor: palette.background, primaryTextColor: palette.text, isDark: palette.isDark, silhouette: CGPath(rect: CGRect(origin: .zero, size: imageSize), transform: nil), style: style, hasTail: false, maxCornerRadius: maxCornerRadius)
    }

    private func assertTaillessMatchesSubmodule(_ palettes: [ColorPalette], file: StaticString = #filePath, line: UInt = #line) {
        for palette in palettes {
            for size in pillSizes {
                for scale in scales {
                    let label = "\(palette.name) \(Int(size.width))x\(Int(size.height))@\(Int(scale))x tailless"
                    guard let actual = actualTaillessImage(palette, size: size, scale: scale), let submodule = submoduleTaillessImage(palette, size: size, scale: scale) else {
                        XCTFail("no image for \(label)", file: file, line: line)
                        continue
                    }
                    XCTAssertEqual(actual.width, submodule.width, label, file: file, line: line)
                    XCTAssertEqual(actual.height, submodule.height, label, file: file, line: line)
                    let actualPixels = submoduleRGBAPixels(actual)
                    let submodulePixels = submoduleRGBAPixels(submodule)
                    var maxDifference = 0
                    for index in 0 ..< min(actualPixels.count, submodulePixels.count) {
                        maxDifference = max(maxDifference, abs(Int(actualPixels[index]) - Int(submodulePixels[index])))
                    }
                    XCTAssertLessThanOrEqual(maxDifference, 2, label, file: file, line: line)
                }
            }
        }
    }

    private func actualImage(_ palette: ColorPalette, size: NSSize, scale: CGFloat, incoming: Bool = false) -> CGImage? {
        return WalletSendCommentBackgroundView.makeImage(parameters: .init(size: size, scale: scale, incoming: incoming, hasTail: true, backgroundColor: palette.background, textColor: palette.text, isDark: palette.isDark))
    }

    private func submoduleImage(_ palette: ColorPalette, size: NSSize, scale: CGFloat, incoming: Bool = false) -> CGImage? {
        guard let style = submoduleCommentStyle else {
            return nil
        }
        return submoduleCommentBackground(size: size, scale: scale, backgroundColor: palette.background, primaryTextColor: palette.text, isDark: palette.isDark, silhouette: walletCommentBubblePath(size, incoming: incoming), style: style)
    }

    func testDrawingRulesAreReadFromTheSubmodule() throws {
        let style = try XCTUnwrap(submoduleCommentStyle)
        XCTAssertEqual(style.fillLocations.count, style.darkFillAmounts.count)
        XCTAssertEqual(style.fillLocations.count, style.lightFillShades.count)
        XCTAssertEqual(style.borderLocations.count, style.borderAmounts.dark.count)
        XCTAssertEqual(style.borderLocations.count, style.borderAmounts.light.count)
        XCTAssertEqual(style.borderLocations.count, style.highlightAmounts.dark.count)
        XCTAssertEqual(style.borderLocations.count, style.highlightAmounts.light.count)
        XCTAssertLessThan(style.contourScale.dark, style.contourScale.light)
    }

    private func assertMatchesSubmodule(_ palettes: [ColorPalette], incoming: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        for palette in palettes {
            for size in sizes {
                for scale in scales {
                    let label = "\(palette.name) \(Int(size.width))x\(Int(size.height))@\(Int(scale))x\(incoming ? " incoming" : "")"
                    guard let actual = actualImage(palette, size: size, scale: scale, incoming: incoming), let submodule = submoduleImage(palette, size: size, scale: scale, incoming: incoming) else {
                        XCTFail("no image for \(label)", file: file, line: line)
                        continue
                    }
                    XCTAssertEqual(actual.width, submodule.width, label, file: file, line: line)
                    XCTAssertEqual(actual.height, submodule.height, label, file: file, line: line)
                    let actualPixels = submoduleRGBAPixels(actual)
                    let submodulePixels = submoduleRGBAPixels(submodule)
                    var maxDifference = 0
                    for index in 0 ..< min(actualPixels.count, submodulePixels.count) {
                        maxDifference = max(maxDifference, abs(Int(actualPixels[index]) - Int(submodulePixels[index])))
                    }
                    XCTAssertLessThanOrEqual(maxDifference, 2, label, file: file, line: line)
                }
            }
        }
    }

    func testDayBackgroundMatchesSubmodule() {
        assertMatchesSubmodule([whitePalette, dayClassicPalette])
    }

    func testNightBackgroundMatchesSubmodule() {
        assertMatchesSubmodule([darkPalette, nightAccentPalette])
    }

    func testIncomingDayBackgroundMatchesSubmodule() {
        assertMatchesSubmodule([whitePalette, dayClassicPalette], incoming: true)
    }

    func testIncomingNightBackgroundMatchesSubmodule() {
        assertMatchesSubmodule([darkPalette, nightAccentPalette], incoming: true)
    }

    func testIncomingBubblePointsItsTailLeft() {
        for size in sizes {
            guard let outgoing = actualImage(dayClassicPalette, size: size, scale: 2), let incoming = actualImage(dayClassicPalette, size: size, scale: 2, incoming: true) else {
                return XCTFail("no image")
            }
            let outgoingPixels = submoduleRGBAPixels(outgoing)
            let incomingPixels = submoduleRGBAPixels(incoming)
            let width = outgoing.width
            let bottom = (outgoing.height - 2) * width
            XCTAssertGreaterThan(outgoingPixels[(bottom + width - 3) * 4 + 3], 0)
            XCTAssertEqual(outgoingPixels[(bottom + 2) * 4 + 3], 0)
            XCTAssertGreaterThan(incomingPixels[(bottom + 2) * 4 + 3], 0)
            XCTAssertEqual(incomingPixels[(bottom + width - 3) * 4 + 3], 0)
            var maxDifference = 0
            for y in 0 ..< outgoing.height {
                for x in 0 ..< width {
                    for channel in 0 ..< 4 {
                        let a = Int(outgoingPixels[(y * width + x) * 4 + channel])
                        let b = Int(incomingPixels[(y * width + (width - 1 - x)) * 4 + channel])
                        maxDifference = max(maxDifference, abs(a - b))
                    }
                }
            }
            XCTAssertLessThanOrEqual(maxDifference, 2, "\(Int(size.width))x\(Int(size.height))")
        }
    }

    func testSubmoduleTaillessRulesAreTheCopiedOnes() throws {
        let view = try submoduleSource("WalletSendCommentBackgroundView.swift")
        XCTAssertTrue(view.contains("let glowPadding = ceil(min(10.0, size.height * 0.24) * 2.0)"))
        XCTAssertTrue(view.contains("let imageSize = CGSize(width: hasTail ? size.width : min(size.width, maxCornerRadius * 2.0 + glowPadding * 2.0 + 1.0), height: size.height)"))
        XCTAssertTrue(view.contains("let capWidth = max(0.0, (imageSize.width - 1.0) * 0.5) self.imageView.image = image.resizableImage(withCapInsets: UIEdgeInsets(top: 0.0, left: capWidth, bottom: 0.0, right: capWidth), resizingMode: .stretch)"))
        XCTAssertTrue(view.contains("let cornerRadius = max(0.0, min(parameters.maxCornerRadius, min(size.width, size.height) * 0.5) - inset) context.addPath(CGPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))"))
        XCTAssertTrue(view.contains("} else { shapeMask = roundedRectMask(inset: 0.0) }"))
        XCTAssertTrue(view.contains("func insetMask(by inset: CGFloat) -> UIImage? { if !parameters.hasTail { return roundedRectMask(inset: inset) }"))
        XCTAssertTrue(view.contains("let fillInset = parameters.hasTail ? min(2.0, size.height * 0.1) : 0.0"))
        let button = try submoduleSource("WalletSendAnimatedRateButton.swift")
        XCTAssertTrue(button.contains("private let backgroundView = WalletSendCommentBackgroundView(frame: .zero)"))
        XCTAssertTrue(button.contains("self.contentView.bounds = CGRect(x: 0.0, y: 0.0, width: self.currentWidth, height: 26.0)"))
        XCTAssertTrue(button.contains("self.backgroundView.update( size: self.contentView.bounds.size, maxCornerRadius: 13.0, minCornerRadius: 13.0, theme: theme, hasTail: false )"))
        XCTAssertEqual(walletSendRatePillHeight, 26.0)
    }

    func testTaillessImageIsCappedAndStretchedLikeSubmodule() {
        for height: CGFloat in [26, 34] {
            for width in stride(from: CGFloat(1), through: 320, by: 1) {
                let size = NSMakeSize(width, height)
                let layout = WalletSendCommentBackgroundView.imageLayout(size: size, hasTail: false)
                let submoduleSize = submoduleTaillessImageSize(size, maxCornerRadius: height / 2.0)
                let capWidth = max(0.0, (submoduleSize.width - 1.0) * 0.5)
                XCTAssertEqual(layout.size, submoduleSize, "\(width)x\(height)")
                XCTAssertEqual(layout.contentsCenter.minX * layout.size.width, capWidth, accuracy: 1e-9, "\(width)x\(height)")
                XCTAssertEqual((1.0 - layout.contentsCenter.maxX) * layout.size.width, capWidth, accuracy: 1e-9, "\(width)x\(height)")
                XCTAssertEqual(layout.contentsCenter.minY, 0)
                XCTAssertEqual(layout.contentsCenter.height, 1)
            }
        }
        XCTAssertEqual(WalletSendCommentBackgroundView.imageLayout(size: NSMakeSize(95, 26), hasTail: false).size, NSMakeSize(53, 26))
        let tailed = WalletSendCommentBackgroundView.imageLayout(size: NSMakeSize(140, 34), hasTail: true)
        XCTAssertEqual(tailed.size, NSMakeSize(140, 34))
        XCTAssertEqual(tailed.contentsCenter, NSMakeRect(24 / 140, 16 / 34, 92 / 140, 2 / 34))
    }

    func testDayTaillessBackgroundMatchesSubmodule() {
        assertTaillessMatchesSubmodule([whitePalette, dayClassicPalette])
    }

    func testNightTaillessBackgroundMatchesSubmodule() {
        assertTaillessMatchesSubmodule([darkPalette, nightAccentPalette])
    }

    func testKeepsOnlyTheBubbleShape() {
        let size = NSMakeSize(140, 34)
        guard let image = actualImage(nightAccentPalette, size: size, scale: 2) else {
            return XCTFail("no image")
        }
        let pixels = submoduleRGBAPixels(image)
        XCTAssertEqual(pixels[3], 0)
        XCTAssertEqual(pixels[((image.height - 1) * image.width + 2) * 4 + 3], 0)
        XCTAssertEqual(pixels[((image.height / 2) * image.width + image.width / 2) * 4 + 3], 255)
    }
}
