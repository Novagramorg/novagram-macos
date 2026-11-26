import Cocoa
import ImageIO
import SwiftSignalKit
import TGUIKit
private let extensionImageCache = Atomic<[String: CGImage]>(value: [:])

private let redColors: (UInt32, UInt32) = (0xf0625d, 0xde524e)
private let greenColors: (UInt32, UInt32) = (0x72ce76, 0x54b658)
private let blueColors: (UInt32, UInt32) = (0x60b0e8, 0x4597d1)
private let yellowColors: (UInt32, UInt32) = (0xf5c565, 0xe5a64e)

private let extensionColorsMap: [String: (UInt32, UInt32)] = [
    "ppt": redColors,
    "pptx": redColors,
    "pdf": redColors,
    "key": redColors,
    
    "xls": greenColors,
    "xlsx": greenColors,
    "csv": greenColors,
    
    "zip": yellowColors,
    "rar": yellowColors,
    "gzip": yellowColors,
    "ai": yellowColors
]

public func generateExtensionImage(colors: (UInt32, UInt32), ext:String) -> CGImage? {
    return generateImage(CGSize(width: 42.0, height: 42.0), contextGenerator: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        
        context.round(CGRect(origin: CGPoint(), size: size), flags: [.left, .bottom, .right])
        
        context.translateBy(x: size.width / 2.0, y: size.height / 2.0)
        context.scaleBy(x: 1.0, y: -1.0)
        context.translateBy(x: -size.width / 2.0 + 1.0, y: -size.height / 2.0 + 1.0)
        
        let radius: CGFloat = .cornerRadius
        let cornerSize: CGFloat = 10.0
        
        context.setFillColor(NSColor(rgb: colors.0).cgColor)
        context.beginPath()
        context.move(to: CGPoint(x: 0.0, y: radius))
        if !radius.isZero {
            context.addArc(tangent1End: CGPoint(x: 0.0, y: 0.0), tangent2End: CGPoint(x: radius, y: 0.0), radius: radius)
        }
        context.addLine(to: CGPoint(x: size.width - cornerSize, y: 0.0))
        context.addLine(to: CGPoint(x: size.width - cornerSize + cornerSize / 4.0, y: cornerSize - cornerSize / 4.0))
        context.addLine(to: CGPoint(x: size.width, y: cornerSize))
        context.addLine(to: CGPoint(x: size.width, y: size.height - radius))
        if !radius.isZero {
            context.addArc(tangent1End: CGPoint(x: size.width, y: size.height), tangent2End: CGPoint(x: size.width - radius, y: size.height), radius: radius)
        }
        context.addLine(to: CGPoint(x: radius, y: size.height))
        
        if !radius.isZero {
            context.addArc(tangent1End: CGPoint(x: 0.0, y: size.height), tangent2End: CGPoint(x: 0.0, y: size.height - 5), radius: 5)
        }
        context.closePath()
        context.fillPath()
        
        context.setFillColor(NSColor(rgb: colors.1).cgColor)
        context.beginPath()
        context.move(to: CGPoint(x: size.width - cornerSize, y: 0.0))
        context.addLine(to: CGPoint(x: size.width, y: cornerSize))
        context.addLine(to: CGPoint(x: size.width - cornerSize + radius, y: cornerSize))
        
        if !radius.isZero {
            context.addArc(tangent1End: CGPoint(x: size.width - cornerSize, y: cornerSize), tangent2End: CGPoint(x: size.width - cornerSize, y: cornerSize - radius), radius: radius)
        }
        
        context.closePath()
        context.fillPath()

        
        
        let layout = TextViewLayout(.initialize(string: ext, color: .white, font: .medium(.short)), maximumNumberOfLines: 1, truncationType: .middle)
        layout.measure(width: size.width - 4)
        if !layout.lines.isEmpty {
            let line = layout.lines[0]
            context.textMatrix = CGAffineTransform(scaleX: 1.0, y: -1.0)
            context.textPosition = NSMakePoint(floorToScreenPixels(System.backingScale, (size.width - line.frame.width)/2.0) - 1, floorToScreenPixels(System.backingScale, (size.height )/2.0) + 4)
            
            CTLineDraw(line.line, context)
        } 
    })
}


public func generateMediaEmptyLinkThumb(color: NSColor, textColor: NSColor, host:String) -> CGImage? {
    return generateImage(CGSize(width: 40, height: 40), contextGenerator: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        let host = host.isEmpty ? "L" : host
        context.round(size, .cornerRadius)
        context.setFillColor(color.cgColor)
        context.fill(CGRect(origin: CGPoint(), size: size))
        if !host.isEmpty {
            let layout = TextViewLayout(.initialize(string: host, color: textColor, font: .bold(.huge)), maximumNumberOfLines: 1, truncationType: .middle)
            layout.measure(width: size.width - 4)
            let line = layout.lines[0]
            
            context.textMatrix = CGAffineTransform(scaleX: 1.0, y: 1.0)
            context.textPosition = NSMakePoint(floorToScreenPixels(System.backingScale, (size.width - line.frame.width)/2.0) , floorToScreenPixels(System.backingScale, (size.height - line.frame.width)/2.0))
            CTLineDraw(line.line, context)
        }
    })
}


public func extensionImage(fileExtension: String) -> CGImage? {
    let colors: (UInt32, UInt32)
    if let extensionColors = extensionColorsMap[fileExtension] {
        colors = extensionColors
    } else {
        colors = blueColors
    }
    
    if let cachedImage = (extensionImageCache.with { dict in
        return dict[fileExtension]
    }) {
        return cachedImage
    } else if let image = generateExtensionImage(colors: colors, ext: fileExtension) {
        let _ = extensionImageCache.modify { dict in
            var dict = dict
            dict[fileExtension] = image
            return dict
        }
        return image
    } else {
        return nil
    }
}

public func capIcon(for text:NSAttributedString, size:NSSize = NSMakeSize(50, 50), cornerRadius:CGFloat = 4, background:NSColor = .border) -> CGImage? {
    return generateImage(size, contextGenerator: { (size, ctx) in
        ctx.clear(NSMakeRect(0, 0, size.width, size.height))
        ctx.round(size, cornerRadius)
        ctx.setFillColor(background.cgColor)
        ctx.fill(NSMakeRect(0, 0, size.width, size.height))
        
        let line = CTLineCreateWithAttributedString(text)
        
        let rect = CTLineGetBoundsWithOptions(line, [.excludeTypographicLeading])
        

        ctx.textMatrix = CGAffineTransform(scaleX: 1.0, y: 1.0)
        ctx.textPosition = NSMakePoint(floorToScreenPixels(System.backingScale, (size.width - rect.width)/2.0), floorToScreenPixels(System.backingScale, (size.height - rect.height)/2.0) + 6 )
        
        CTLineDraw(line, ctx)
        
    })
}

public let playerPlayThumb = generateImage(NSMakeSize(40.0,40.0), contextGenerator: { size, context in
    
    context.clear(NSMakeRect(0.0,0.0,size.width,size.height))
    
    let position:NSPoint = NSMakePoint(14.0, 10.0)
    context.move(to: position)
    context.addLine(to: NSMakePoint(position.x, position.y + 20.0))
    context.addLine(to: NSMakePoint(position.x + 15.0, position.y + 10.0 ))
    context.setFillColor(NSColor.white.cgColor)
    context.fillPath()
    
})!


public let stopFetchStreamableControl = generateImage(CGSize(width: 6, height: 6), contextGenerator: { size, context in
    context.clear(CGRect(origin: CGPoint(), size: size))
    context.round(size, 2)
    context.setFillColor(NSColor.white.cgColor)
    context.fill(NSMakeRect(0, 0, size.width, size.height))
})


public struct PreviewOptions: OptionSet {
    public var rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    public init() {
        self.rawValue = 0
    }
    
    public init(_ flags: PreviewOptions) {
        var rawValue: UInt32 = 0
        
        
        if flags.contains(PreviewOptions.file) {
            rawValue |= PreviewOptions.file.rawValue
        }
        
        if flags.contains(PreviewOptions.media) {
            rawValue |= PreviewOptions.media.rawValue
        }
        
        self.rawValue = rawValue
    }
    
    public static let media = PreviewOptions(rawValue: 1)
    public static let file = PreviewOptions(rawValue: 8)
}

private let senderOptionsHeaderImageExtensions: Set<String> = ["jpg", "jpeg", "jpe", "jfif", "png", "heic", "heif"]

private func senderOptionsHeaderImageSize(_ url: URL) -> NSSize? {
    guard !url.lastPathComponent.contains("@"), senderOptionsHeaderImageExtensions.contains(url.pathExtension.lowercased()) else {
        return nil
    }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) == 1, let type = CGImageSourceGetType(source) as String?, ["public.jpeg", "public.heic", "public.heif", "public.png"].contains(type) else {
        return nil
    }
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, width > 0, height > 0 else {
        return nil
    }
    let dpiWidth = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue
    let dpiHeight = (properties[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue
    guard dpiWidth == nil || dpiWidth == 72, dpiHeight == nil || dpiHeight == 72 else {
        return nil
    }
    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    guard orientation >= 1 && orientation <= 8 else {
        return nil
    }
    return orientation >= 5 ? NSMakeSize(CGFloat(height), CGFloat(width)) : NSMakeSize(CGFloat(width), CGFloat(height))
}

public func takeSenderOptions(for urls:[URL]) -> [PreviewOptions] {
    var options:[PreviewOptions] = []
    for url in urls {
        let mime = MIMEType(url.path)
        
        if mime.hasPrefix("image") {
            if let size = senderOptionsHeaderImageSize(url) ?? NSImage(contentsOf: url)?.size {
                if size.width / 10 > size.height || size.height < 40 {
                    continue
                } else if size.height / 10 > size.width || size.width < 40 {
                    continue
                }
            } else {
                continue
            }
        }
        
        let media = mime.hasPrefix("image") || mime.hasSuffix("gif") || mime.hasPrefix("video/mp4") || mime.hasPrefix("video/mov") || mime.hasSuffix("m4v")

        if media {
            if !options.contains(.media) {
                options.append(.media)
            }
        } else {
            if !options.contains(.file) {
                options.append(.file)
            }
        }
        if mime == "image/webp" {
            options.removeAll(where: { $0 == .media })
        }
    }
    
    
    if options.isEmpty {
        options.append(.file)
    }
    
    return options
}



fileprivate let minDiameter: CGFloat = 3.5
fileprivate let maxDiameter: CGFloat = 8.0

public func interpolate(from: CGFloat, to: CGFloat, value: CGFloat) -> CGFloat {
    return (1.0 - value) * from + value * to
}

public func radiusFunction(_ value: CGFloat, timeOffset: CGFloat) -> CGFloat {
    var clampedValue: CGFloat = value + timeOffset
    if clampedValue > 1.0 {
        clampedValue = clampedValue - floor(clampedValue)
    }
    if clampedValue < 0.4 {
        return interpolate(from: minDiameter, to: maxDiameter, value: clampedValue / 0.4)
    }
    else if clampedValue < 0.8 {
        return interpolate(from: maxDiameter, to: minDiameter, value: (clampedValue - 0.4) / 0.4)
    }
    else {
        return minDiameter
    }
}

public struct ActivityDotFrame {
    public let rect: CGRect
    public let alpha: CGFloat
}

public func typingDotsFrame(_ animationValue: CGFloat) -> [ActivityDotFrame] {
    let leftPadding: CGFloat = 5.0
    let topPadding: CGFloat = 7
    let distance: CGFloat = 12.0 / 2.0
    let minAlpha: CGFloat = 0.75
    let deltaAlpha: CGFloat = 1.0 - minAlpha
    var dots: [ActivityDotFrame] = []
    for (index, timeOffset) in [CGFloat(0.4), 0.2, 0.0].enumerated() {
        var radius = radiusFunction(animationValue, timeOffset: timeOffset)
        radius = (max(minDiameter, radius) - minDiameter) / (maxDiameter - minDiameter)
        radius = radius * 1.5
        let rect = NSMakeRect(leftPadding + distance * CGFloat(index) - minDiameter / 2.0 - radius / 2.0, topPadding - minDiameter / 2.0 - radius / 2.0, minDiameter + radius, minDiameter + radius)
        dots.append(ActivityDotFrame(rect: rect, alpha: radius * deltaAlpha + minAlpha))
    }
    return dots
}

private func generateTextAnimatedImage(_ animationValue:CGFloat, color:UInt32) -> CGImage {
    return generateImage(NSMakeSize(26, 20), contextGenerator: { (size, context) in
        context.clear(NSMakeRect(0,0,size.width, size.height))
        for dot in typingDotsFrame(animationValue) {
            context.setFillColor(NSColor(color, dot.alpha).cgColor)
            context.fillEllipse(in: dot.rect)
        }
    })!
    
}

public struct ActivityArcFrame {
    public let radius: CGFloat
    public let alpha: CGFloat
}

public let recordingActivityArcCenter = NSMakePoint(4, 7)
public let recordingActivityArcAngle = CGFloat(18.0 * .pi / 180.0)

public func recordingArcsFrame(_ animationValue: CGFloat) -> [ActivityArcFrame] {
    let delta: CGFloat = 5.0
    let value: CGFloat = animationValue * delta
    var arcs: [ActivityArcFrame] = []
    var radius = value
    var alpha = radius / (3 * delta)
    alpha = 1.0 - pow(cos(alpha * (CGFloat.pi / 2)), 50)
    arcs.append(ActivityArcFrame(radius: radius, alpha: alpha))
    radius = value + delta
    alpha = radius / (3.0 * delta)
    alpha = 1.0 - pow(cos(alpha * CGFloat.pi), 10)
    arcs.append(ActivityArcFrame(radius: radius, alpha: alpha))
    radius = value + delta * 2
    alpha = radius / (3.0 * delta)
    alpha = 1.0 - pow(cos(alpha * CGFloat.pi), 10)
    arcs.append(ActivityArcFrame(radius: radius, alpha: alpha))
    return arcs
}

private func generateRecordingAnimatedImage(_ animationValue:CGFloat, color:UInt32) -> CGImage {
    return generateImage(NSMakeSize(26, 20), contextGenerator: { (size, context) in
        context.clear(NSMakeRect(0,0,size.width, size.height))
        context.setStrokeColor(NSColor(color).cgColor)
        context.setLineCap(.round)
        context.setLineWidth(3)
        for arc in recordingArcsFrame(animationValue) {
            context.setAlpha(arc.alpha)
            context.beginPath()
            context.addArc(center: recordingActivityArcCenter, radius: arc.radius, startAngle: -recordingActivityArcAngle, endAngle: recordingActivityArcAngle, clockwise: false)
            context.strokePath()
        }
    })!
    
}

public struct ChoosingStickerFrame {
    public let leftEye: CGRect
    public let rightEye: CGRect
    public let leftPupil: CGRect
    public let rightPupil: CGRect
}

public let choosingStickerActivitySize = NSMakeSize(24, 20)

public func choosingStickerFrame(_ animationValue: CGFloat) -> ChoosingStickerFrame {
    let size = choosingStickerActivitySize
    var heightProgress: CGFloat = animationValue * 4.0
    if heightProgress > 3.0 {
        heightProgress = 4.0 - heightProgress
    } else if heightProgress > 2.0 {
        heightProgress = heightProgress - 2.0
        heightProgress *= heightProgress
    } else if heightProgress > 1.0 {
        heightProgress = 2.0 - heightProgress
    } else {
        heightProgress *= heightProgress
    }
    
    var pupilProgress: CGFloat = animationValue * 4.0
    if pupilProgress > 2.0 {
        pupilProgress = 3.0 - pupilProgress
    }
    pupilProgress = min(1.0, max(0.0, pupilProgress))
    pupilProgress *= pupilProgress
    
    var positionProgress: CGFloat = animationValue * 2.0
    if positionProgress > 1.0 {
        positionProgress = 2.0 - positionProgress
    }
    
    let eyeWidth: CGFloat = 6.0
    let eyeHeight: CGFloat = 11.0 - 2.0 * heightProgress

    let eyeOffset: CGFloat = -1.0 + positionProgress * 2.0
    let leftCenter = CGPoint(x: size.bounds.width / 2.0 - eyeWidth - 1.0 + eyeOffset, y: size.bounds.height / 2.0)
    let rightCenter = CGPoint(x: size.bounds.width / 2.0 + 1.0 + eyeOffset, y: size.bounds.height / 2.0)
    
    let pupilSize: CGFloat = 4.0
    let pupilCenter = CGPoint(x: -1.0 + pupilProgress * 2.0, y: 0.0)
    
    return ChoosingStickerFrame(
        leftEye: CGRect(x: leftCenter.x - eyeWidth / 2.0, y: leftCenter.y - eyeHeight / 2.0, width: eyeWidth, height: eyeHeight),
        rightEye: CGRect(x: rightCenter.x - eyeWidth / 2.0, y: rightCenter.y - eyeHeight / 2.0, width: eyeWidth, height: eyeHeight),
        leftPupil: CGRect(x: leftCenter.x - pupilSize / 2.0 + pupilCenter.x * eyeWidth / 4.0, y: leftCenter.y - pupilSize / 2.0, width: pupilSize, height: pupilSize),
        rightPupil: CGRect(x: rightCenter.x - pupilSize / 2.0 + pupilCenter.x * eyeWidth / 4.0, y: rightCenter.y - pupilSize / 2.0, width: pupilSize, height: pupilSize)
    )
}

private func generateChoosingStickerAnimatedImage(_ animationValue:CGFloat, color:NSColor) -> CGImage {
    return generateImage(choosingStickerActivitySize, contextGenerator: { (size, context) in
        context.clear(size.bounds)
        context.setFillColor(color.cgColor)
        context.setStrokeColor(color.cgColor)
        let frame = choosingStickerFrame(animationValue)
        context.strokeEllipse(in: frame.leftEye)
        context.fillEllipse(in: frame.leftPupil)
        context.strokeEllipse(in: frame.rightEye)
        context.fillEllipse(in: frame.rightPupil)
    })!
    
}

public let uploadingActivityTrack = CGRect(x: 7.0, y: 4.0, width: 26.0 / 2.0, height: 10.0 / 2.0)

public func uploadingBarFrame(_ animationValue: CGFloat) -> CGRect {
    let track = uploadingActivityTrack
    let progress = interpolate(from: 0.0, to: track.width * 2.0, value: animationValue)
    return CGRect(x: track.minX - track.width + progress, y: track.minY, width: track.width, height: track.height)
}

private func generateUploadFileAnimatedImage(_ animationValue:CGFloat, backgroundColor:UInt32, foregroundColor: UInt32) -> CGImage {
    return generateImage(NSMakeSize(26, 20), contextGenerator: { (size, context) in
        context.clear(NSMakeRect(0,0,size.width, size.height))
        let track = uploadingActivityTrack
        context.setFillColor(NSColor(backgroundColor).cgColor)
        context.addPath(CGPath(roundedRect: track, cornerWidth: 2, cornerHeight: 2, transform: nil))
        context.closePath()
        context.fillPath()
        context.setFillColor(NSColor(foregroundColor, 0.3).cgColor)
        context.addPath(CGPath(roundedRect: track, cornerWidth: 2, cornerHeight: 2, transform: nil))
        context.closePath()
        context.fillPath()
        context.setFillColor(NSColor(foregroundColor, 1.0).cgColor)
        context.setBlendMode(.sourceIn)
        context.addPath(CGPath(roundedRect: uploadingBarFrame(animationValue), cornerWidth: 2, cornerHeight: 2, transform: nil))
        context.closePath()
        context.fillPath()
    })!
}






public func recordVoiceActivityAnimation(_ color: NSColor) -> [CGImage] {
    var steps:[CGImage] = []
    
    for i in 0 ..< 42 {
        steps.append(generateRecordingAnimatedImage( CGFloat(i) / 42, color: color.rgb))
    }
    return steps
}

public func choosingStickerActivityAnimation(_ color: NSColor) -> [CGImage] {
    var steps:[CGImage] = []
    for i in 0 ..< 120 {
        steps.append(generateChoosingStickerAnimatedImage( CGFloat(i) / 120, color: color))
    }
    return steps
}

public func uploadFileActivityAnimation(_ foregroundColor: NSColor, _ backgroundColor: NSColor) -> [CGImage] {
    var steps:[CGImage] = []
    
    for i in 0 ..< 105 {
        steps.append(generateUploadFileAnimatedImage( CGFloat(i) / 105, backgroundColor: backgroundColor.rgb, foregroundColor: foregroundColor.rgb))
    }
    return steps
}

public func textActivityAnimation(_ color: NSColor) -> [CGImage] {
    var steps:[CGImage] = []
    
    for i in 0 ..< 42 {
        steps.append(generateTextAnimatedImage( CGFloat(i) / 42, color: color.rgb))
    }
    return steps
}

