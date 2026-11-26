import XCTest
import AppKit
import TGUIKit
import TelegramTheme
@testable import ShortPeerRow

final class ChatActivityIndicatorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private let foreground = NSColor(srgbRed: 0.24, green: 0.55, blue: 0.82, alpha: 1)
    private let background = NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1)

    private func frames(_ type: ChatActivityAnimation, foreground: NSColor, background: NSColor) -> [CGImage] {
        switch type {
        case .recording:
            return recordVoiceActivityAnimation(foreground)
        case .uploading:
            return uploadFileActivityAnimation(foreground, background)
        case .choosingSticker:
            return choosingStickerActivityAnimation(foreground)
        default:
            return textActivityAnimation(foreground)
        }
    }

    private func legacyFrames(_ type: ChatActivityAnimation, foreground: NSColor, background: NSColor) -> [CGImage] {
        switch type {
        case .recording:
            return legacyRecordVoiceActivityAnimation(foreground)
        case .uploading:
            return legacyUploadFileActivityAnimation(foreground, background)
        case .choosingSticker:
            return legacyChoosingStickerActivityAnimation(foreground)
        default:
            return legacyTextActivityAnimation(foreground)
        }
    }

    private func render(_ layer: CALayer, size: NSSize) -> PixelBuffer {
        let context = CGContext(data: nil, width: Int(size.width * 2), height: Int(size.height * 2), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: 2, y: 2)
        layer.render(in: context)
        return PixelBuffer(context.makeImage()!)
    }

    private let types: [ChatActivityAnimation] = [.text, .recording, .uploading, .choosingSticker]
    private let tolerance: [ChatActivityAnimation: Int] = [.text: 2, .recording: 2, .uploading: 4, .choosingSticker: 0]

    func testFrameGeometryRefactorDrawsTheSameBitmaps() {
        for type in types {
            for (backgroundColor, name) in [(background, "opaque"), (NSColor.clear, "clear")] {
                let new = frames(type, foreground: foreground, background: backgroundColor)
                let old = legacyFrames(type, foreground: foreground, background: backgroundColor)
                XCTAssertEqual(new.count, old.count, "\(type) \(name)")
                for (index, (a, b)) in zip(new, old).enumerated() {
                    XCTAssertEqual(PixelBuffer(a).differingPixels(from: PixelBuffer(b), tolerance: 0), 0, "\(type) \(name) frame \(index)")
                }
            }
        }
    }

    func testLayersDrawEveryOldFrame() {
        for type in types {
            for (backgroundColor, name) in [(background, "opaque"), (NSColor.clear, "clear")] {
                let theme = ActivitiesTheme(textColor: foreground, backgroundColor: backgroundColor)
                let images = frames(type, foreground: foreground, background: backgroundColor)
                let size = ChatActivityIndicatorLayer.size(for: type)
                let layer = ChatActivityIndicatorLayer()
                layer.frame = size.bounds
                layer.configure(type, theme: theme)
                XCTAssertEqual(layer.frameCount, images.count, "\(type)")
                var worst = 0
                for index in 0 ..< images.count {
                    layer.show(sample: index)
                    let rendered = self.render(layer, size: size)
                    let expected = PixelBuffer(images[index])
                    XCTAssertEqual(rendered.width, expected.width)
                    worst = max(worst, rendered.differingPixels(from: expected, tolerance: self.tolerance[type] ?? 0))
                }
                XCTAssertEqual(worst, 0, "\(type) \(name)")
                layer.show(sample: 0)
                let blank = ChatActivityIndicatorLayer()
                blank.frame = size.bounds
                XCTAssertGreaterThan(self.render(layer, size: size).differingPixels(from: self.render(blank, size: size), tolerance: 0), 20, "\(type)")
            }
        }
    }

    func testAnimationsKeepTheOldTimeline() {
        for (type, duration) in [(ChatActivityAnimation.text, 0.7), (.recording, 0.7), (.uploading, 1.75), (.choosingSticker, 2.0)] {
            let layer = ChatActivityIndicatorLayer()
            layer.frame = ChatActivityIndicatorLayer.size(for: type).bounds
            layer.configure(type, theme: ActivitiesTheme(textColor: foreground, backgroundColor: background))
            layer.startAnimating()
            var animated = 0
            var stack: [CALayer] = layer.sublayers ?? []
            while let current = stack.popLast() {
                stack.append(contentsOf: current.sublayers ?? [])
                for key in current.animationKeys() ?? [] {
                    let animation = current.animation(forKey: key) as! CAKeyframeAnimation
                    XCTAssertEqual(animation.duration, duration, "\(type)")
                    XCTAssertEqual(animation.repeatCount, .infinity)
                    XCTAssertEqual(animation.values?.count, layer.frameCount, "\(type) \(key)")
                    XCTAssertNil(animation.keyTimes)
                    if key == "path", let shape = current as? CAShapeLayer {
                        let values = animation.values as! [CGPath]
                        layer.show(sample: 7)
                        XCTAssertEqual(values[7], shape.path, "\(type)")
                    }
                    animated += 1
                }
            }
            XCTAssertGreaterThan(animated, 0, "\(type)")
        }
    }
}
