import Cocoa
import TGUIKit
import TelegramCore
import Localization
import ColorPalette
import TelegramTheme
import InputDataUI
import GeneralRows
import TelegramContext
import TelegramUtils
import FoundationUtils
import AlertsUI
import InAppSettings
import LocalAnimations
import SwiftSignalKit
import Postbox
import AvatarUI

public enum StorageUsageCategory: Int32 {
    case photos
    case videos
    case files
    case music
    case other
    case stickers
    case avatars
    case misc
    case stories
    public var color: NSColor {
        switch self {
        case .photos:
            return NSColor(rgb: 0x5AC8FA)
        case .videos:
            return NSColor(rgb: 0x3478F6)
        case .files:
            return NSColor(rgb: 0x34C759)
        case .music:
            return NSColor(rgb: 0xFF2D55)
        case .other:
            return NSColor(rgb: 0xC4C4C6)
        case .stickers:
            return NSColor(rgb: 0x5856D6)
        case .avatars:
            return NSColor(rgb: 0xAF52DE)
        case .misc:
            return NSColor(rgb: 0xFF9500)
        case .stories:
            return NSColor(rgb: 0x3478F6)
        }
    }
    
    public var title: String {
        switch self {
        case .photos:
            return strings().storageUsageCategoryPhotos
        case .videos:
            return strings().storageUsageCategoryVideos
        case .files:
            return strings().storageUsageCategoryFiles
        case .music:
            return strings().storageUsageCategoryMusic
        case .other:
            return strings().storageUsageCategoryOther
        case .stickers:
            return strings().storageUsageCategoryStickers
        case .avatars:
            return strings().storageUsageCategoryAvatars
        case .misc:
            return strings().storageUsageCategoryMiscellaneous
        case .stories:
            return strings().storageUsageCategoryStories
        }
    }
    
    public var native: StorageUsageStats.CategoryKey {
        switch self {
        case .photos:
            return .photos
        case .videos:
            return .videos
        case .files:
            return .files
        case .music:
            return .music
        case .other:
            fatalError()
        case .stickers:
            return .stickers
        case .avatars:
            return .avatars
        case .misc:
            return .misc
        case .stories:
            return .stories
        }
    }
}

public extension StorageUsageStats.CategoryKey {
    var mapped: StorageUsageCategory {
        switch self {
        case .photos:
            return .photos
        case .videos:
            return .videos
        case .files:
            return .files
        case .music:
            return .music
        case .stickers:
            return .stickers
        case .avatars:
            return .avatars
        case .misc:
            return .misc
        case .stories:
            return .stories
        }
    }
}

extension AllStorageUsageStats : @retroactive Equatable {
    public static func ==(lhs: AllStorageUsageStats, rhs: AllStorageUsageStats) -> Bool {
        return lhs === rhs
    }
}
extension StorageUsageStats : @retroactive Equatable {
    public static func ==(lhs: StorageUsageStats, rhs: StorageUsageStats) -> Bool {
        return lhs === rhs
    }
    
    public var msgIds: Set<EngineMessage.Id> {
        var ids: [EngineMessage.Id] = []
        for (_, value) in categories {
            ids.append(contentsOf: value.messages.map { $0.key })
        }
        return Set(ids)
    }
    public var msgSizes: [EngineMessage.Id : Int64] {
        var ids: [EngineMessage.Id : Int64] = [:]
        for (_, value) in categories {
            for (key, value) in value.messages {
                ids[key] = value
            }
        }
        return ids
    }
}
extension StorageUsageStats.CategoryData : @retroactive Equatable {
    public static func ==(lhs: StorageUsageStats.CategoryData, rhs: StorageUsageStats.CategoryData) -> Bool {
        return lhs.size == rhs.size
    }
}

extension StorageUsageStats {
    public var totalCount: Int64 {
        return self.categories.reduce(0, { $0 + $1.value.size })
    }
}
