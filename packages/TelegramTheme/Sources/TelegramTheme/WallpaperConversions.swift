import Foundation
import Cocoa
import TelegramCore
import Postbox
import ColorPalette
import TGUIKit
import ThemeSettings

public extension TelegramBaseTheme {
    var palette: ColorPalette {
        switch self {
        case .classic:
            return dayClassicPalette
        case .day:
            return whitePalette
        case .night, .tinted:
            return nightAccentPalette
        }
    }
}

public extension TelegramThemeSettings {
    var palette: ColorPalette {
        return baseTheme.palette.withAccentColor(accent)
    }
    
    var accent: PaletteAccentColor {
        let messages = self.messageColors.map { NSColor(rgb: UInt32(bitPattern: $0)) }
        return PaletteAccentColor(NSColor(rgb: UInt32(bitPattern: self.accentColor)), messages)
    }
    
    var background: TelegramWallpaper? {
        if let wallpaper = self.wallpaper {
            return wallpaper
        } else {
            if self.baseTheme == .classic {
                return .builtin(WallpaperSettings())
            }
        }
        return nil
    }
    
}

public extension TelegramWallpaper {
    func uiWallpaper(_ gift: StarGift.UniqueGift? = nil)-> Wallpaper {
        let t: Wallpaper
        switch self {
        case .builtin:
            t = .builtin
        case let .color(color):
            t = .color(color)
        case let .file(values):
            t = .file(slug: values.slug, file: values.file, settings: values.settings, isPattern: values.isPattern, gift: gift)
        case let .gradient(gradient):
            t = .gradient(gradient.id, gradient.colors, gradient.settings.rotation)
        case let .image(reps, settings):
            t = .image(reps, settings: settings)
        case let .emoticon(emoticon):
            t = .emoticon(emoticon)
        }
        return t
    }
}

public extension Wallpaper {
    var cloudWallpaper: TelegramWallpaper? {
        switch self {
        case .builtin:
            return .builtin(WallpaperSettings())
        case let .color(color):
            return .color(color)
        case let .gradient(id, colors, rotation):
            return .gradient(.init(id: id, colors: colors, settings: WallpaperSettings(rotation: rotation)))
        case let .file(slug, file, settings, isPattern, _):
            return .file(.init(id: file.fileId.id, accessHash: 0, isCreator: true, isDefault: false, isPattern: isPattern, isDark: false, slug: slug, file: file, settings: settings))
        case let .image(representation, settings):
            let resource = representation.last?.resource as? LocalFileMediaResource
            let dimension: PixelDimensions = representation.last?.dimensions ?? .init(WallpaperDimensions)
            return .file(.init(id: resource?.fileId ?? 0, accessHash: 0, isCreator: true, isDefault: false, isPattern: false, isDark: false, slug: "", file: TelegramMediaFile(fileId: MediaId(namespace: 0, id: resource?.fileId ?? 0), partialReference: nil, resource: representation.last!.resource, previewRepresentations: representation, videoThumbnails: [], immediateThumbnailData: nil, mimeType: "image/jpeg", size: nil, attributes: [.ImageSize(size: dimension)], alternativeRepresentations: []), settings: settings))
        default:
            return nil
        }
    }
}

//
