import Foundation
import CoreGraphics
import CoreVideo

func avatarDrawingFrame(size: CGSize, zoom: CGFloat, offset: CGPoint) -> CGRect? {
    guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0, zoom.isFinite, zoom > 0, offset.x.isFinite, offset.y.isFinite else { return nil }
    let width = size.width * zoom
    let height = size.height * zoom
    var frame = CGRect(x: ((size.width - width) / 2).rounded(), y: ((size.height - height) / 2).rounded(), width: width, height: height)
    frame.origin.x += frame.origin.x * offset.x * 2 * zoom / 3
    frame.origin.y -= frame.origin.y * offset.y * 2 * zoom / 3
    guard frame.origin.x.isFinite, frame.origin.y.isFinite, frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0 else { return nil }
    return frame
}

func avatarDrawingImage(size: CGSize, flipped: Bool = false, draw: (CGSize, CGContext) -> Bool) -> CGImage? {
    guard let width = Int(exactly: size.width), let height = Int(exactly: size.height), width > 0, height > 0 else { return nil }
    let rowBytes = width.multipliedReportingOverflow(by: 4)
    guard !rowBytes.overflow, !rowBytes.partialValue.multipliedReportingOverflow(by: height).overflow else { return nil }
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: rowBytes.partialValue, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.clear(CGRect(origin: .zero, size: size))
    if flipped {
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
    }
    guard draw(size, context) else { return nil }
    return context.makeImage()
}

func avatarPixelBuffer(from image: CGImage, zoom: CGFloat = 1, offset: CGPoint = .zero, background: CGImage? = nil) -> CVPixelBuffer? {
    let size = CGSize(width: image.width, height: image.height)
    guard let frame = avatarDrawingFrame(size: size, zoom: zoom, offset: offset) else { return nil }
    let attributes = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
    var buffer: CVPixelBuffer?
    guard CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32ARGB, attributes, &buffer) == kCVReturnSuccess, let buffer else { return nil }
    guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { return nil }
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let data = CVPixelBufferGetBaseAddress(buffer), let context = CGContext(data: data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
    let rect = CGRect(origin: .zero, size: size)
    context.clear(rect)
    if let background {
        context.draw(background, in: rect)
    }
    context.draw(image, in: frame)
    return buffer
}

func avatarCompositedImage(from image: CGImage, zoom: CGFloat = 1, offset: CGPoint, background: CGImage? = nil) -> CGImage? {
    let size = CGSize(width: image.width, height: image.height)
    guard let frame = avatarDrawingFrame(size: size, zoom: zoom, offset: offset) else { return nil }
    return avatarDrawingImage(size: size) { size, context in
        if let background {
            context.draw(background, in: CGRect(origin: .zero, size: size))
        }
        context.draw(image, in: frame)
        return true
    }
}
