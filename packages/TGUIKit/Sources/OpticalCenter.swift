import Cocoa

public func imageOpticalCenterOffset(_ image: CGImage) -> NSPoint {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else {
        return .zero
    }

    var alpha = [UInt8](repeating: 0, count: width * height)
    let hasAlpha = alpha.withUnsafeMutableBytes { buffer -> Bool in
        guard let address = buffer.baseAddress, let context = CGContext(data: address, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else {
            return false
        }
        context.draw(image, in: CGRect(origin: .zero, size: CGSize(width: width, height: height)))
        return true
    }
    guard hasAlpha else {
        return .zero
    }

    var total: CGFloat = 0
    var sumX: CGFloat = 0
    var sumY: CGFloat = 0
    for y in 0 ..< height {
        let row = y * width
        for x in 0 ..< width {
            let value = CGFloat(alpha[row + x])
            if value > 0 {
                total += value
                sumX += value * (CGFloat(x) + 0.5)
                sumY += value * (CGFloat(y) + 0.5)
            }
        }
    }
    guard total > 0 else {
        return .zero
    }

    let scale = image.scale
    guard scale > 0 else {
        return .zero
    }

    let dx = (CGFloat(width) / 2 - sumX / total).rounded() / scale
    let dy = (CGFloat(height) / 2 - sumY / total).rounded() / scale
    return NSMakePoint(dx, dy)
}
