import Foundation
import Cocoa
import TelegramCore
import ColorPalette
import ThemeSettings
import TelegramTheme

public extension TelegramMediaWebpageLoadedContent {
    func withUpdatedYoutubeTimecode(_ timecode: Double) -> TelegramMediaWebpageLoadedContent {
        var newUrl = self.url
        if let range = self.url.range(of: "t=") {
            let substr = String(newUrl[range.upperBound...])
            var parsed: String = ""
            for char in substr {
                if "0987654321".contains(char) {
                    parsed += String(char)
                } else {
                    break
                }
            }
            newUrl = newUrl.replacingOccurrences(of: parsed, with: "\(Int(timecode))", options: .caseInsensitive, range: range.lowerBound ..< newUrl.endIndex)
        } else {
            if url.contains("?") {
                newUrl = self.url + "&t=\(Int(timecode))"
            } else {
                newUrl = self.url + "?t=\(Int(timecode))"
            }
        }
        return TelegramMediaWebpageLoadedContent(url: newUrl, displayUrl: self.displayUrl, hash: self.hash, type: self.type, websiteName: self.websiteName, title: self.title, text: self.text, embedUrl: self.embedUrl, embedType: self.embedType, embedSize: self.embedSize, duration: self.duration, author: self.author, isMediaLargeByDefault: self.isMediaLargeByDefault, imageIsVideoCover: false, image: self.image, file: self.file, story: self.story, attributes: self.attributes, instantPage: self.instantPage?._parse())
    }
    func withUpdatedFile(_ file: TelegramMediaFile) -> TelegramMediaWebpageLoadedContent {
        return TelegramMediaWebpageLoadedContent(url: self.url, displayUrl: self.displayUrl, hash: self.hash, type: self.type, websiteName: self.websiteName, title: self.title, text: self.text, embedUrl: self.embedUrl, embedType: self.embedType, embedSize: self.embedSize, duration: self.duration, author: self.author, isMediaLargeByDefault: self.isMediaLargeByDefault, imageIsVideoCover: false, image: self.image, file: file, story: self.story, attributes: self.attributes, instantPage: self.instantPage?._parse())
    }
    func withUpdatedImage(_ image: TelegramMediaImage) -> TelegramMediaWebpageLoadedContent {
        return TelegramMediaWebpageLoadedContent(url: self.url, displayUrl: self.displayUrl, hash: self.hash, type: self.type, websiteName: self.websiteName, title: self.title, text: self.text, embedUrl: self.embedUrl, embedType: self.embedType, embedSize: self.embedSize, duration: self.duration, author: self.author, isMediaLargeByDefault: self.isMediaLargeByDefault, imageIsVideoCover: false, image: image, file: self.file, story: self.story, attributes: self.attributes, instantPage: self.instantPage?._parse())
    }
    
    var isCrossplatformTheme: Bool {
        for attr in attributes {
            switch attr {
            case let .theme(theme):
                var hasFile: Bool = false
                for file in theme.files {
                    if file.mimeType == "application/x-tgtheme-macos", !file.previewRepresentations.isEmpty {
                        hasFile = true
                    }
                }
                if let _ = theme.settings, !hasFile {
                    return true
                }
            default:
                break
            }
        }
        return false
    }
    
    var crossplatformPalette: ColorPalette? {
        for attr in attributes {
            switch attr {
            case let .theme(theme):
                return theme.settings?.palette
            default:
                break
            }
        }
        return nil
    }
    var crossplatformWallpaper: Wallpaper? {
        for attr in attributes {
            switch attr {
            case let .theme(theme):
                return theme.settings?.background?.uiWallpaper()
            default:
                break
            }
        }
        return nil
    }
    
    var themeSettings: TelegramThemeSettings? {
        for attr in attributes {
            switch attr {
            case let .theme(theme):
                return theme.settings
            default:
                break
            }
        }
        return nil
    }
}
