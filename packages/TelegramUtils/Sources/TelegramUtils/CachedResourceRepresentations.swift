import Cocoa
import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import FoundationUtils
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif


public final class CachedStickerAJpegRepresentation: CachedMediaResourceRepresentation {
    public let size: CGSize?
    public var keepDuration: CachedMediaRepresentationKeepDuration = .general
    public var uniqueId: String {
        if let size = self.size {
            return "sticker-v3-png-\(Int(size.width))x\(Int(size.height))"
        } else {
            return "sticker-v3-png"
        }
    }
    
    public init(size: CGSize?) {
        self.size = size
    }
    
    public func isEqual(to: CachedMediaResourceRepresentation) -> Bool {
        if let to = to as? CachedStickerAJpegRepresentation {
            return self.size == to.size
        } else {
            return false
        }
    }
}

open class CachedScaledImageRepresentation: CachedMediaResourceRepresentation {
    public let size: CGSize
    open var keepDuration: CachedMediaRepresentationKeepDuration = .general
    open var uniqueId: String {
        return "scaled-image-\(Int(self.size.width))x\(Int(self.size.height))"
    }
    
    public init(size: CGSize) {
        self.size = size
    }
    
    open func isEqual(to: CachedMediaResourceRepresentation) -> Bool {
        if let to = to as? CachedScaledImageRepresentation {
            return self.size == to.size
        } else {
            return false
        }
    }
}



public final class CachedVideoFirstFrameRepresentation: CachedMediaResourceRepresentation {
    public init() {}
    public var keepDuration: CachedMediaRepresentationKeepDuration = .general
    
    public var uniqueId: String {
        return "first-frame"
    }
    
    public func isEqual(to: CachedMediaResourceRepresentation) -> Bool {
        if to is CachedVideoFirstFrameRepresentation {
            return true
        } else {
            return false
        }
    }
}

public final class CachedScaledVideoFirstFrameRepresentation: CachedMediaResourceRepresentation {
    public let size: CGSize
    public var keepDuration: CachedMediaRepresentationKeepDuration = .general
    public var uniqueId: String {
        return "scaled-frame-\(Int(self.size.width))x\(Int(self.size.height))"
    }
    
    public init(size: CGSize) {
        self.size = size
    }
    
    public func isEqual(to: CachedMediaResourceRepresentation) -> Bool {
        if let to = to as? CachedScaledVideoFirstFrameRepresentation {
            return self.size == to.size
        } else {
            return false
        }
    }
}
public final class CachedBlurredWallpaperRepresentation: CachedMediaResourceRepresentation {
    public init() {}
    public var keepDuration: CachedMediaRepresentationKeepDuration = .general
    public var uniqueId: String {
        return CachedBlurredWallpaperRepresentation.uniqueId
    }
    
    public static var uniqueId: String {
        return "blurred-wallpaper"
    }
    
    public func isEqual(to: CachedMediaResourceRepresentation) -> Bool {
        if to is CachedBlurredWallpaperRepresentation {
            return true
        } else {
            return false
        }
    }
}

public final class CachedWallpaperRepresentation: CachedMediaResourceRepresentation {
    public var keepDuration: CachedMediaRepresentationKeepDuration = .general
    public var uniqueId: String {
        return CachedBlurredWallpaperRepresentation.uniqueId
    }
    public let isDark: Bool
    public let settings: WallpaperSettings
    public init(isDark: Bool, settings: WallpaperSettings) {
        self.isDark = isDark
        self.settings = settings
    }
    
    public static var uniqueId: String {
        return "cached-wallpaper"
    }
    
    public func isEqual(to: CachedMediaResourceRepresentation) -> Bool {
        if let to = to as? CachedWallpaperRepresentation {
            return to.isDark == self.isDark && to.settings == to.settings
        } else {
            return false
        }
    }
}


public final class CachedAnimatedStickerRepresentation: CachedMediaResourceRepresentation {
    public var keepDuration: CachedMediaRepresentationKeepDuration = .general
    public var uniqueId: String {
        let version: Int = 18
        if let fitzModifier = self.fitzModifier {
            return "2animated-sticker-v\(version)-\(self.thumb ? 1 : 0)-w:\(size.width)-h:\(size.height)-fitz\(fitzModifier.rawValue)-f\(frame)-m1\(self.isVideo)"
        } else {
            return "2animated-sticker-v\(version)-\(self.thumb ? 1 : 0)-w:\(size.width)-h:\(size.height)-f\(frame)-m1\(self.isVideo)"
        }
    }
    public let thumb: Bool
    public let size: NSSize
    public let fitzModifier: EmojiFitzModifier?
    public let frame: Int
    public let isVideo: Bool
    public init(thumb: Bool, size: NSSize, fitzModifier: EmojiFitzModifier? = nil, frame: Int = 0, isVideo: Bool = false) {
        self.thumb = thumb
        self.size = size
        self.fitzModifier = fitzModifier
        self.frame = frame
        self.isVideo = isVideo
    }
    
    public func isEqual(to: CachedMediaResourceRepresentation) -> Bool {
        if let to = to as? CachedAnimatedStickerRepresentation {
            return self.thumb == to.thumb && self.size == to.size && self.fitzModifier == to.fitzModifier && self.frame == to.frame && self.isVideo == to.isVideo && self.uniqueId == to.uniqueId
        } else {
            return false
        }
    }
}

public final class CachedPatternWallpaperMaskRepresentation: CachedMediaResourceRepresentation {
    public let keepDuration: CachedMediaRepresentationKeepDuration = .general
    
    public let size: CGSize?
    public let settings: WallpaperSettings?
    public var pattern: TelegramMediaFile?
    public var model: TelegramMediaFile?
    
    public var uniqueId: String {
        
        var color:String = ""
        
        if let settings = settings {
            color += settings.stringValue
        }
        var string: String
        if let size = self.size {
            string = "-------pattern-wallpaper-mask-\(Int(size.width))x\(Int(size.height))" + color
        } else {
            string = "-------pattern-wallpaper-mask-" + color
        }
        if let pattern {
            string += "-\(pattern.fileId.id)"
        }
        if let model {
            string += "-\(model.fileId.id)"
        }
        return string
    }
    
    public init(size: CGSize? = nil, settings: WallpaperSettings? = nil, model: TelegramMediaFile? = nil, pattern: TelegramMediaFile? = nil) {
        self.size = size
        self.settings = settings
        self.model = model
        self.pattern = pattern
    }
    
    public func isEqual(to: CachedMediaResourceRepresentation) -> Bool {
        if let to = to as? CachedPatternWallpaperMaskRepresentation {
            return self.size == to.size && self.settings == to.settings && self.pattern?.fileId == to.pattern?.fileId && self.model?.fileId == to.model?.fileId
        } else {
            return false
        }
    }
}


public final class CachedDiceRepresentation: CachedMediaResourceRepresentation {
    public let keepDuration: CachedMediaRepresentationKeepDuration = .general
    public let emoji: String
    public let value: String
    public let size: NSSize
    public var uniqueId: String {
        return emoji + value + ":dice2"
    }
    
    public init(emoji: String, value: String, size: NSSize) {
        self.value = value
        self.size = size
        self.emoji = emoji
    }
    
    public func isEqual(to: CachedMediaResourceRepresentation) -> Bool {
        if let to = to as? CachedDiceRepresentation {
            return self.value == to.value && self.size == to.size && self.emoji == to.emoji
        } else {
            return false
        }
    }
}

public final class CachedSlotMachineRepresentation: CachedMediaResourceRepresentation {
    public let keepDuration: CachedMediaRepresentationKeepDuration = .general
    public let value: SlotMachineValue
    public let size: NSSize
    public var uniqueId: String {
        return "l: \(value.left.hashValue)" + ", c: \(value.center.hashValue)" + ", c: \(value.right.hashValue)" + " :slot1"
    }
    
    public init(value: SlotMachineValue, size: NSSize) {
        self.value = value
        self.size = size
    }
    
    public func isEqual(to: CachedMediaResourceRepresentation) -> Bool {
        if let to = to as? CachedSlotMachineRepresentation {
            return self.value == to.value && self.size == to.size
        } else {
            return false
        }
    }
}





public final class CachedPreparedSvgRepresentation: CachedMediaResourceRepresentation {
    public let keepDuration: CachedMediaRepresentationKeepDuration = .general
    
    public var uniqueId: String {
        return "prepared-svg"
    }
    
    public init() {
    }
    
    public func isEqual(to: CachedMediaResourceRepresentation) -> Bool {
        if to is CachedPreparedSvgRepresentation {
            return true
        } else {
            return false
        }
    }
}
