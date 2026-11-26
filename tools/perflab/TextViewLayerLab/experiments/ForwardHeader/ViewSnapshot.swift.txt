import AppKit
import TGUIKit

final class SnapshotWindow: NSWindow {
    override var backingScaleFactor: CGFloat {
        return 2
    }
}

struct PixelBuffer: Equatable {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = data
    }

    func differingPixels(from other: PixelBuffer, tolerance: Int = 2) -> Int {
        guard width == other.width, height == other.height else {
            return Int.max
        }
        var count = 0
        var index = 0
        while index < bytes.count {
            var differs = false
            for channel in 0 ..< 4 where abs(Int(bytes[index + channel]) - Int(other.bytes[index + channel])) > tolerance {
                differs = true
            }
            if differs {
                count += 1
            }
            index += 4
        }
        return count
    }

    func pixels(darkerThan limit: UInt8) -> Int {
        var count = 0
        var index = 0
        while index < bytes.count {
            if bytes[index] < limit && bytes[index + 1] < limit && bytes[index + 2] < limit && bytes[index + 3] > 0 {
                count += 1
            }
            index += 4
        }
        return count
    }
}

enum ViewSnapshot {
    private static func makeContext(_ size: CGSize, _ scale: CGFloat) -> CGContext {
        let context = CGContext(data: nil, width: Int(ceil(size.width * scale)), height: Int(ceil(size.height * scale)), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        return context
    }

    static func render(_ view: NSView, scale: CGFloat = 2) -> PixelBuffer {
        let window = SnapshotWindow(contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        CATransaction.flush()
        var temporary: [CALayer] = []
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        func displayPlain(_ layer: CALayer) {
            if !(layer.delegate is NSView) {
                layer.displayIfNeeded()
            }
            layer.sublayers?.forEach(displayPlain)
        }
        func inject(_ current: NSView) {
            if let layer = current.layer, layer.bounds.width > 0, layer.bounds.height > 0 {
                var image: CGImage?
                if let contents = layer.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
                    image = (contents as! CGImage)
                } else if !current.wantsUpdateLayer || (current as? View)?.displayDelegate != nil {
                    let context = makeContext(layer.bounds.size, scale)
                    if current.isFlipped {
                        context.translateBy(x: 0, y: layer.bounds.height)
                        context.scaleBy(x: 1, y: -1)
                    }
                    layer.draw(in: context)
                    image = context.makeImage()
                }
                if let image = image {
                    let overlay = CALayer()
                    overlay.frame = layer.bounds
                    overlay.contentsScale = scale
                    overlay.contentsGravity = layer.contentsGravity
                    overlay.contentsRect = layer.contentsRect
                    overlay.contents = image
                    layer.insertSublayer(overlay, at: 0)
                    temporary.append(overlay)
                }
            }
            current.subviews.forEach(inject)
        }
        view.layer.map(displayPlain)
        inject(view)
        CATransaction.commit()
        let context = makeContext(view.bounds.size, scale)
        if view.layer!.isGeometryFlipped {
            context.translateBy(x: 0, y: view.bounds.height)
            context.scaleBy(x: 1, y: -1)
        }
        view.layer!.render(in: context)
        temporary.forEach { $0.removeFromSuperlayer() }
        window.contentView = nil
        return PixelBuffer(context.makeImage()!)
    }
}

func viewTreeCount(_ view: NSView) -> Int {
    return 1 + view.subviews.reduce(0) { $0 + viewTreeCount($1) }
}

func viewClassNames(_ views: [NSView]) -> [String] {
    return views.map { String(describing: type(of: $0)) }
}
