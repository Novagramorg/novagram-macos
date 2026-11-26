import Foundation
import Cocoa

public func generateStickerPlaceholderImage(data: Data, size: CGSize, scale: CGFloat? = nil, imageSize: CGSize, backgroundColor: NSColor?, foregroundColor: NSColor) -> CGImage? {
    return generateImage(size, scale: scale, rotatedContext: { size, context in
        if let backgroundColor = backgroundColor {
            context.setFillColor(backgroundColor.cgColor)
            context.setBlendMode(.copy)
            context.fill(CGRect(origin: CGPoint(), size: size))
            context.setFillColor(NSColor.clear.cgColor)
        } else {
            context.clear(CGRect(origin: CGPoint(), size: size))
            context.setFillColor(foregroundColor.cgColor)
        }
        
        var path = decodeStickerThumbnailData(data)
        if !path.hasSuffix("z") {
            path = "\(path)z"
        }
        let reader = PathDataReader(input: path)
        let segments = reader.read()
        
        let scale = max(size.width, size.height) / max(imageSize.width, imageSize.height)
        context.scaleBy(x: scale, y: scale)
        renderPath(segments, context: context)
    })
}
