import Cocoa
import TelegramCore
import Postbox
import ColorPalette
import ApiCredentials
import TGUIKit

extension WallpaperSettings {
    public var stringValue: String {
        var value: String = ""
        if let top = self.colors.first, self.colors.count == 2 {
            value += "ctop\(top)"
        }
        if let top = self.colors.last, self.colors.count == 2 {
            value += "cbottom\(top)"
        }
        if let rotation = self.rotation {
            value += "rotation\(rotation)"
        }
        if self.blur {
            value += "blur"
        }
        return value
    }
}

public func wallpaperPath(_ resource: TelegramMediaResource, palette: ColorPalette = theme.colors, settings: WallpaperSettings, gift: StarGift.UniqueGift? = nil) -> String {
    var path = ApiEnvironment.containerURL!.appendingPathComponent("Wallpapers").path + "/" + resource.id.stringRepresentation + "\(settings.stringValue)" + "_isDark__\(palette.isDark ? 1 : 0)"
    if let gift {
        path += "-\(gift.slug)"
    }
    path += ".png"
    return path
}

public func wallpaperMetadataPath(_ resource: TelegramMediaResource, settings: WallpaperSettings, gift: StarGift.UniqueGift) -> String {
    return ApiEnvironment.containerURL!.appendingPathComponent("Wallpapers").path + "/" + resource.id.stringRepresentation + "\(settings.stringValue)" + "-\(gift.slug)" + "-metadata.json"
}
