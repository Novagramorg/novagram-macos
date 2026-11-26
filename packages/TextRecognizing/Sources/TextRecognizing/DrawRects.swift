import Foundation
import TGUIKit
import Cocoa
import CoreGraphics

private extension NSPoint {
    func apply(_ size: NSSize, _ multiplier: CGPoint = NSMakePoint(1, 1)) -> CGPoint {
        return NSMakePoint(self.x * size.width * multiplier.x, self.y * size.height * multiplier.y)
    }
}

@available(macOS 10.15, *)
private extension TextRecognizing.Result.Detected {
    func path(_ size: NSSize, viewSize: NSSize) -> CGPath {
        let path = CGMutablePath()
        let multiplier = NSMakePoint(viewSize.width / size.width, viewSize.height / size.height)
        path.move(to: self.topLeft.apply(size, multiplier))
        path.addLine(to: self.topRight.apply(size, multiplier))
        path.addLine(to: self.bottomRight.apply(size, multiplier))
        path.addLine(to: self.bottomLeft.apply(size, multiplier))
        path.addLine(to: self.topLeft.apply(size, multiplier))
        return path
    }
    func rect(_ size: NSSize, viewSize: NSSize) -> CGRect {
        let multiplier = NSMakePoint(viewSize.width / size.width, viewSize.height / size.height)
        return NSMakeRect(self.frameRect.minX * size.width * multiplier.x, self.frameRect.minY * size.height * multiplier.y, self.frameRect.width * size.width * multiplier.x, self.frameRect.height * size.height * multiplier.y)
    }
    
}


@available(macOS 10.15, *)
public extension TextRecognizing.Result.Barcode {
    func corners(viewSize: NSSize) -> [CGPoint] {
        return [self.topLeft, self.topRight, self.bottomRight, self.bottomLeft].map {
            $0.apply(viewSize)
        }
    }
    func bounds(viewSize: NSSize) -> CGRect {
        let corners = self.corners(viewSize: viewSize)
        let xs = corners.map { $0.x }
        let ys = corners.map { $0.y }
        return NSMakeRect(xs.min()!, ys.min()!, xs.max()! - xs.min()!, ys.max()! - ys.min()!)
    }
}

@available(macOS 10.15, *)
public extension TextRecognizing.Result {
    var barcodes: [TextRecognizing.Result.Barcode] {
        switch self {
        case let .finish(_, _, barcodes):
            return barcodes
        default:
            return []
        }
    }
    
    func selectablePaths(viewSize: NSSize) -> [CGPath] {
        switch self {
        case let .finish(image, text, _):
            var paths:[CGPath] = []
            for value in text {
                paths.append(value.path(image.size, viewSize: viewSize))
            }
            return paths
        default:
            return []
        }
    }
    
    func selectableRects(viewSize: NSSize) -> [CGRect] {
        switch self {
        case let .finish(image, text, _):
            var rects:[CGRect] = []
            for value in text {
                rects.append(value.rect(image.size, viewSize: viewSize))
            }
            return rects
        default:
            return []
        }
    }
    
    func rotations() -> [CGFloat] {
        switch self {
        case let .finish(_, text, _):
            var rotations:[CGFloat] = []
            for value in text {
                rotations.append(value.rotationAngle)
            }
            return rotations
        default:
            return []
        }
    }
    
    func select(from: CGPoint, to: CGPoint, viewSize: NSSize) -> TextRecognizing.Result {
        switch self {
        case let .finish(image, text, _):
            var result: [TextRecognizing.Result.Detected] = []
            let selected = NSMakeRect(min(from.x, to.x), min(from.y, to.y), max(from.x, to.x) - min(from.x, to.x), max(from.y, to.y) - min(from.y, to.y))
            let size = image.size
            for text in text {
                let rect = text.rect(size, viewSize: viewSize)
                if selected.intersects(rect) {
                    let center = NSMakeRect(rect.midX, rect.midY, 1, 1).insetBy(dx: -2, dy: -2)
                    if selected.intersects(center) {
                        result.append(text)
                    }
                }
            }
            return .finish(image: image, text: result, barcodes: [])
        default:
            return self
        }
        
      
    }
}
