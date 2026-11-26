import Cocoa

private func supportsImageAlphaAnalysis(_ image: CGImage) -> Bool {
    guard image.bitsPerComponent == 8, image.bitsPerPixel == 32 else { return false }
    switch image.alphaInfo {
    case .first, .last, .premultipliedFirst, .premultipliedLast:
        return true
    default:
        return false
    }
}

private func imageAnalysisContext(_ image: CGImage, size: CGSize) -> CGContext? {
    guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0, size.width < CGFloat(Int.max), size.height < CGFloat(Int.max) else { return nil }
    let width = max(1, Int(size.width)), height = max(1, Int(size.height))
    let (bytesPerRow, rowOverflow) = width.multipliedReportingOverflow(by: 4)
    let (_, sizeOverflow) = bytesPerRow.multipliedReportingOverflow(by: height)
    guard !rowOverflow, !sizeOverflow else { return nil }
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: deviceColorSpace, bitmapInfo: bitmapInfo) else { return nil }
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(image, in: CGRect(origin: .zero, size: size))
    return context
}

private func imagePixelsHaveTransparency(_ data: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) -> Bool {
    for y in 0..<height {
        let row = data.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt32.self)
        for x in 0..<width {
            if UInt32(littleEndian: row[x]) >> 24 < 255 { return true }
        }
    }
    return false
}

func imageHasTransparency(_ image: CGImage) -> Bool {
    guard supportsImageAlphaAnalysis(image), let context = imageAnalysisContext(image, size: CGSize(width: image.width, height: image.height)), let data = context.data else { return false }
    return withExtendedLifetime(context) {
        imagePixelsHaveTransparency(data, width: context.width, height: context.height, bytesPerRow: context.bytesPerRow)
    }
}

private func scaledDrawingContext(_ image: CGImage, maxSize: CGSize) -> CGContext? {
    var size = CGSize(width: image.width, height: image.height)
    if size.width > maxSize.width && size.height > maxSize.height {
        size = size.aspectFilled(maxSize)
    }
    return imageAnalysisContext(image, size: size)
}

public func imageRequiresInversion(_ image: CGImage) -> Bool {
    guard supportsImageAlphaAnalysis(image), let context = scaledDrawingContext(image, maxSize: CGSize(width: 128, height: 128)), let data = context.data else { return false }
    return withExtendedLifetime(context) {
        let width = context.width, height = context.height, bytesPerRow = context.bytesPerRow
        guard imagePixelsHaveTransparency(data, width: width, height: height, bytesPerRow: bytesPerRow) else { return false }
        var matching = 0
        var total = 0
        for y in 0..<height {
            let row = data.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt32.self)
            for x in 0..<width {
                let pixel = UInt32(littleEndian: row[x])
                let alpha = Int(pixel >> 24)
                if alpha == 0 { continue }
                total += 1
                let red = Int((pixel >> 16) & 255)
                let green = Int((pixel >> 8) & 255)
                let blue = Int(pixel & 255)
                let maximum = max(red, max(green, blue))
                if maximum * 4 < alpha {
                    let minimum = min(red, min(green, blue))
                    if maximum == 0 || (maximum - minimum) * 10 < maximum {
                        matching += 1
                    }
                }
            }
        }
        return total > 0 && Double(matching) / Double(total) > 0.85
    }
}

public func generateTintedImage(image: CGImage?, color: NSColor, backgroundColor: NSColor? = nil, flipVertical: Bool = true) -> CGImage? {
    guard let image = image else {
        return nil
    }
    let imageSize = image.size
    return generateImage(imageSize, contextGenerator: { size, context in
        context.clear(size.bounds)
        if let backgroundColor = backgroundColor {
            context.setFillColor(backgroundColor.cgColor)
            context.fill(CGRect(origin: CGPoint(), size: imageSize))
        }
        
        let imageRect = CGRect(origin: CGPoint(), size: imageSize)
        context.saveGState()
        if flipVertical {
            context.translateBy(x: imageRect.midX, y: imageRect.midY)
            context.scaleBy(x: 1.0, y: -1.0)
            context.translateBy(x: -imageRect.midX, y: -imageRect.midY)
        }
        context.clip(to: imageRect, mask: image)
        context.setFillColor(color.cgColor)
        context.fill(imageRect)
        context.restoreGState()
    })
}



private func orientationFromExif(orientation: Int) -> ImageOrientation {
    switch orientation {
    case 1:
        return .up;
    case 3:
        return .down;
    case 8:
        return .left;
    case 6:
        return .right;
    case 2:
        return .upMirrored;
    case 4:
        return .downMirrored;
    case 5:
        return .leftMirrored;
    case 7:
        return .rightMirrored;
    default:
        return .up
    }
}

public func imageOrientationFromSource(_ source: CGImageSource) -> ImageOrientation {
    if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) {
        let dict = properties as NSDictionary
        if let value = dict.object(forKey: kCGImagePropertyOrientation) as? NSNumber {
            return orientationFromExif(orientation: value.intValue)
        }
    }
    
    return .up
}
