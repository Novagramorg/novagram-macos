import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import TGUIKit
import ThemeSettings
import TelegramUtils
import ColorPalette
import Svg
import GZIP
import ImageIO
import Cocoa
import ApiCredentials

public enum WallpaperCacheSource : Equatable {
    case basic
    case pattern
    case gift(StarGift.UniqueGift)
    
    public var gift: StarGift.UniqueGift? {
        switch self {
        case let .gift(gift):
            return gift
        default:
            return nil
        }
    }
}

public func moveWallpaperToCache(postbox: Postbox, resource: TelegramMediaResource, reference: WallpaperReference?, settings: WallpaperSettings, source: WallpaperCacheSource = .basic) -> Signal<String, NoError> {
    let resourceData: Signal<MediaResourceData, NoError>
    if source == .pattern  {
        resourceData = postbox.mediaBox.cachedResourceRepresentation(resource, representation: CachedPatternWallpaperMaskRepresentation(size: nil, settings: settings), complete: true)
    } else if case let .gift(gift) = source  {
        resourceData = postbox.mediaBox.cachedResourceRepresentation(resource, representation: CachedPatternWallpaperMaskRepresentation(size: nil, settings: settings, model: gift.file, pattern: gift.pattern), complete: true)
    } else if settings.blur {
        resourceData = postbox.mediaBox.cachedResourceRepresentation(resource, representation: CachedBlurredWallpaperRepresentation(), complete: true)
    } else {
        resourceData = postbox.mediaBox.resourceData(resource)
    }
    
    
    var fetch: [Signal<FetchResourceSourceType, FetchResourceError>] = []
    
    fetch.append(fetchedMediaResource(mediaBox: postbox.mediaBox, userLocation: .other, userContentType: .other, reference: .wallpaper(wallpaper: reference, resource: resource), reportResultStatus: true))
    
    if case let .gift(gift) = source, let file = gift.file, let pattern = gift.pattern {
        fetch.append(fetchedMediaResource(mediaBox: postbox.mediaBox, userLocation: .other, userContentType: .other, reference: .standalone(resource: file.resource), reportResultStatus: true))
        fetch.append(fetchedMediaResource(mediaBox: postbox.mediaBox, userLocation: .other, userContentType: .other, reference: .standalone(resource: pattern.resource), reportResultStatus: true))
    }
    
    let signal: Signal<FetchResourceSourceType, FetchResourceError> = combineLatest(fetch) |> mapToSignal { values in
        return .single(values.allSatisfy({ $0 == .local }) ? .local : .remote)
    }
   
    return combineLatest(signal |> `catch` { _ in
        return .single(.local)
    }, resourceData) |> mapToSignal { _, data in
        if data.complete {
            return moveWallpaperToCache(postbox: postbox, path: data.path, resource: resource, settings: settings, gift: source.gift)
        } else {
            return .complete()
        }
    }
}

public func moveWallpaperToCache(postbox: Postbox, wallpaper: Wallpaper) -> Signal<Wallpaper, NoError> {
    switch wallpaper {
    case let .image(reps, settings):
        return moveWallpaperToCache(postbox: postbox, resource: largestImageRepresentation(reps)!.resource, reference: nil, settings: settings, source: .basic) |> map { _ in return wallpaper}
    case let .custom(representation, blurred):
        return moveWallpaperToCache(postbox: postbox, resource: representation.resource, reference: nil, settings: WallpaperSettings(blur: blurred), source: .basic) |> map { _ in return wallpaper}
    case let .file(slug, file, settings, isPattern, gift):
        return moveWallpaperToCache(postbox: postbox, resource: file.resource, reference: .slug(slug), settings: settings, source: gift != nil ? .gift(gift!) : isPattern ? .pattern : .basic) |> map { _ in return wallpaper}
    default:
       return .single(wallpaper)
    }
}

public func imageWithEightBitChannels(_ image: CGImage) -> CGImage? {
    guard image.bitsPerComponent > 8 else {
        return nil
    }
    let space = (image.colorSpace?.model == .rgb ? image.colorSpace : nil) ?? CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage()
}

public func imageChannelDepth(atPath path: String) -> Int? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
        return nil
    }
    return properties[kCGImagePropertyDepth] as? Int
}

@discardableResult
public func rewritePNGWithEightBitChannels(atPath path: String) -> Bool {
    guard let depth = imageChannelDepth(atPath: path), depth > 8 else {
        return false
    }
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil), let converted = imageWithEightBitChannels(image) else {
        return false
    }
    let temporaryPath = path + ".8bit"
    guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: temporaryPath) as CFURL, kUTTypePNG, 1, nil) else {
        return false
    }
    CGImageDestinationAddImage(destination, converted, nil)
    guard CGImageDestinationFinalize(destination), rename(temporaryPath, path) == 0 else {
        try? FileManager.default.removeItem(atPath: temporaryPath)
        return false
    }
    return true
}

@discardableResult
public func migrateWallpapersToEightBitChannels(directory: String? = nil) -> Int {
    guard let directory = directory ?? ApiEnvironment.containerURL?.appendingPathComponent("Wallpapers").path else {
        return 0
    }
    let files = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
    var rewritten = 0
    for file in files where file.hasSuffix(".png") {
        if rewritePNGWithEightBitChannels(atPath: directory + "/" + file) {
            rewritten += 1
        }
    }
    return rewritten
}

public func moveWallpaperToCache(postbox: Postbox, path: String, resource: TelegramMediaResource, settings: WallpaperSettings, gift: StarGift.UniqueGift? = nil) -> Signal<String, NoError> {
    return Signal { subscriber in
        
        let wallpapers = ApiEnvironment.containerURL!.appendingPathComponent("Wallpapers").path
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: wallpapers), withIntermediateDirectories: true, attributes: nil)
        
        var out = wallpapers + "/" + resource.id.stringRepresentation + "\(settings.stringValue)" + "_isDark__0"
        if let gift {
            out += "-\(gift.slug)"
        }
        out += ".png"
        

        if !FileManager.default.fileExists(atPath: out) {
            try? FileManager.default.removeItem(atPath: out)
            try? FileManager.default.copyItem(atPath: path, toPath: out)
        }
        rewritePNGWithEightBitChannels(atPath: out)
        
        let image = NSImage(contentsOf: URL(fileURLWithPath: out))
        
        var outDark = wallpapers + "/" + resource.id.stringRepresentation + "\(settings.stringValue)" + "_isDark__1"
        if let gift {
            outDark += "-\(gift.slug)"
        }
        outDark += ".png"
        
        let darkUrl = URL(fileURLWithPath: outDark)
        
        if !FileManager.default.fileExists(atPath: outDark), let image {
            
            let intense = CGFloat(abs(settings.intensity ?? 0)) / 100
            var cgImage = image._cgImage
            var type: CFString = kUTTypeJPEG
            if settings.colors.count > 1 {
                cgImage = generateImage(image.size, contextGenerator: { size, ctx in
                    ctx.clear(size.bounds)
                    ctx.setFillColor(NSColor.black.cgColor)
                    ctx.fill(size.bounds)
                    ctx.clip(to: size.bounds, mask: image._cgImage!)
                    
                    ctx.clear(size.bounds)
                    ctx.setFillColor(NSColor.black.withAlphaComponent(1 - intense).cgColor)
                    ctx.fill(size.bounds)
                }, scale: 1)
                type = kUTTypePNG
            } else if intense > 0 {
                cgImage = generateImage(image.size, contextGenerator: { size, ctx in
                    ctx.clear(size.bounds)
                    ctx.draw(image._cgImage!, in: size.bounds)
                    
                    ctx.setFillColor(NSColor.black.withAlphaComponent(1 - intense).cgColor)
                    ctx.fill(size.bounds)
                }, scale: 1)
                type = kUTTypeJPEG
            }
            if let image = cgImage, let colorDestination = CGImageDestinationCreateWithURL(darkUrl as CFURL, type, 1, nil) {
                CGImageDestinationSetProperties(colorDestination, [:] as CFDictionary)
                
                let colorQuality: Float = 0.7
                
                let options = NSMutableDictionary()
                options.setObject(colorQuality as NSNumber, forKey: kCGImageDestinationLossyCompressionQuality as NSString)
                
                CGImageDestinationAddImage(colorDestination, image, options as CFDictionary)
                CGImageDestinationFinalize(colorDestination)
                
            }
        }
        
        // Only gift wallpapers carry SVG slot metadata; reading and inflating the whole resource for every
        // other wallpaper was wasted work (the body below is gated on gift anyway).
        if let gift, let image {
            let resourcePath = postbox.mediaBox.resourcePath(resource)
            let data = try? Data(contentsOf: URL(fileURLWithPath: resourcePath))
            if let data = TGGUnzipData(data, 8 * 1024 * 1024) {
                let slotsData = svgSlotsDataFromSVG(data, image.size)
                if let slotsData {
                    let path = wallpapers + "/" + resource.id.stringRepresentation + "\(settings.stringValue)" + "-\(gift.slug)-metadata.json"
                    let url = URL(fileURLWithPath: path)
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: slotsData, options: [.prettyPrinted])
                        try jsonData.write(to: url, options: [.atomic])
                    } catch { }
                }
            }
        }
        
        subscriber.putNext(out)
        
        subscriber.putCompletion()
        return EmptyDisposable
        
    }
}
