import Foundation
import Cocoa
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramContext
import TelegramTheme
import ThemeSettings
import TelegramMediaUtils
import ColorPalette

final class QrStudioThemeBackgroundView: View, QrStudioBackgroundContent {
    private let backgroundView: BackgroundView
    private let wallpaperDisposable = MetaDisposable()
    private var mode: TableBackgroundMode = .plain
    private var size = CGSize()

    let theme: QrStudioTheme
    let wantsFullFrameRate: Bool = false

    init(context: any AccountContextProtocol, theme: QrStudioTheme) {
        self.theme = theme
        self.backgroundView = BackgroundView(frame: CGRect())

        super.init(frame: CGRect())

        self.backgroundColor = self.theme.colors.first?.nsColor ?? .white
        self.backgroundView.useSharedAnimationPhase = false
        self.backgroundView.checkDarkPattern = false
        self.addSubview(self.backgroundView)

        let wallpaper = Wallpaper(theme.wallpaper)
        let emoticonThemes = context.emoticonThemes
        switch wallpaper {
        case .image, .file, .custom:
            self.setMode(QrStudioThemeBackgroundView.fallbackMode(colors: theme.colors), animated: false)
            self.wallpaperDisposable.set((moveWallpaperToCache(postbox: context.account.postbox, wallpaper: wallpaper)
            |> deliverOnMainQueue).start(next: { [weak self] wallpaper in
                guard let self = self else {
                    return
                }
                self.setMode(generateBackgroundMode(wallpaper, palette: dayClassicPalette, emoticonThemes: emoticonThemes), animated: true)
            }))
        default:
            self.setMode(generateBackgroundMode(wallpaper, palette: dayClassicPalette, emoticonThemes: emoticonThemes), animated: false)
        }
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.wallpaperDisposable.dispose()
    }

    private static func fallbackMode(colors: [QrStudioColor]) -> TableBackgroundMode {
        if colors.count > 1 {
            return .gradient(colors: colors.map { $0.nsColor }, rotation: nil)
        } else if let color = colors.first {
            return .color(color: color.nsColor)
        } else {
            return .color(color: .white)
        }
    }

    private func setMode(_ mode: TableBackgroundMode, animated: Bool) {
        guard self.mode != mode else {
            return
        }
        self.mode = mode
        if animated, let layer = self.backgroundView.layer {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.25
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(transition, forKey: "transition")
        }
        self.backgroundView.backgroundMode = mode
        if self.size.width > 0.0, self.size.height > 0.0 {
            self.backgroundView.updateLayout(size: self.size, transition: .immediate)
        }
    }

    func update(size: CGSize, revealCenter: CGPoint) {
        guard self.size != size, size.width > 0.0, size.height > 0.0 else {
            return
        }
        self.size = size
        self.backgroundView.frame = CGRect(origin: CGPoint(), size: size)
        self.backgroundView.updateLayout(size: size, transition: .immediate)
    }

    func tick(time: Double, pan: QrStudioPan, drift: QrStudioDrift, tilt: SIMD2<Double>) {
    }

    func beginReveal(at time: Double) {
    }

    func setVisible(_ isVisible: Bool) {
    }

    func snapshotImage(scale: CGFloat) -> CGImage? {
        let size = self.size
        guard size.width > 0.0, size.height > 0.0, scale > 0.0 else {
            return nil
        }
        let width = max(1, Int(ceil(size.width * scale)))
        let height = max(1, Int(ceil(size.height * scale)))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            return nil
        }
        context.scaleBy(x: CGFloat(width) / size.width, y: CGFloat(height) / size.height)
        context.interpolationQuality = .high
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.setFillColor(self.backgroundColor.cgColor)
        context.fill(bounds)

        switch self.mode {
        case let .color(color):
            context.setFillColor(color.withAlphaComponent(1.0).cgColor)
            context.fill(bounds)
        case let .gradient(colors, rotation):
            QrStudioThemeBackgroundView.drawGradient(colors: colors.map { $0.withAlphaComponent(1.0) }, rotation: rotation, size: size, in: context)
        case let .background(image, intensity, colors, rotation, _):
            var alpha: CGFloat = 1.0
            var blendMode: CGBlendMode = .normal
            var shouldTile = false
            if let colors = colors?.map({ $0.withAlphaComponent(1.0) }), !colors.isEmpty {
                QrStudioThemeBackgroundView.drawGradient(colors: colors, rotation: rotation, size: size, in: context)
                shouldTile = colors.count > 1
                if colors.count > 1 {
                    alpha = CGFloat(abs(intensity ?? 50)) / 100.0
                    blendMode = .softLight
                }
            }
            if let pattern = image._cgImage {
                QrStudioThemeBackgroundView.drawPattern(pattern, imageSize: image.size, shouldTile: shouldTile, alpha: alpha, blendMode: blendMode, size: size, in: context)
            }
        case .tiled, .plain:
            break
        }
        return context.makeImage()
    }

    private static func drawGradient(colors: [NSColor], rotation: Int32?, size: CGSize, in context: CGContext) {
        guard !colors.isEmpty else {
            return
        }
        let bounds = CGRect(origin: CGPoint(), size: size)
        if colors.count > 2 {
            let gradientSize = size.fitted(CGSize(width: 64.0, height: 64.0))
            let preview = AnimatedGradientBackgroundView.generatePreview(size: CGSize(width: max(1.0, floor(gradientSize.width)), height: max(1.0, floor(gradientSize.height))), colors: colors)
            context.draw(preview, in: bounds)
            return
        }
        let cgColors = Array([colors.first, colors.last].compactMap { $0?.cgColor }.reversed())
        guard let gradient = CGGradient.evenlySpaced(cgColors) else {
            return
        }
        context.saveGState()
        context.clip(to: bounds)
        context.translateBy(x: size.width / 2.0, y: size.height / 2.0)
        context.rotate(by: CGFloat(rotation ?? 0) * CGFloat.pi / -180.0)
        context.translateBy(x: -size.width / 2.0, y: -size.height / 2.0)
        context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 0.0, y: size.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }

    private static func drawPattern(_ pattern: CGImage, imageSize: CGSize, shouldTile: Bool, alpha: CGFloat, blendMode: CGBlendMode, size: CGSize, in context: CGContext) {
        guard imageSize.width > 0.0, imageSize.height > 0.0 else {
            return
        }
        var frame = CGRect(origin: CGPoint(), size: size)
        frame.size.height = max(500.0, frame.height)
        var rects: [CGRect] = []
        let tileSize = imageSize.aspectFitted(frame.size)
        if shouldTile && tileSize.width < frame.width {
            var x: CGFloat = 0.0
            while x < frame.width {
                rects.append(CGRect(x: x, y: (frame.height - tileSize.height) / 2.0, width: tileSize.width, height: tileSize.height))
                x += tileSize.width
            }
        } else {
            let filled = imageSize.aspectFilled(frame.size)
            rects.append(CGRect(x: round((frame.width - filled.width) / 2.0), y: round((frame.height - filled.height) / 2.0), width: filled.width, height: filled.height))
        }
        context.saveGState()
        context.clip(to: CGRect(origin: CGPoint(), size: size))
        context.setBlendMode(blendMode)
        context.setAlpha(alpha)
        for rect in rects {
            context.draw(pattern, in: CGRect(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height))
        }
        context.restoreGState()
    }
}
