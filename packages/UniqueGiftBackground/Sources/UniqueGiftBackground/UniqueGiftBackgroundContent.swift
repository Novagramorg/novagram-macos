import Foundation
import TelegramCore
import Postbox
import UniqueGiftRenderer

public struct UniqueGiftBackgroundContent: Equatable {
    public enum Pattern: Equatable {
        case file(TelegramMediaFile)
        case fileId(Int64)

        public var fileId: Int64 {
            switch self {
            case let .file(file):
                return file.fileId.id
            case let .fileId(id):
                return id
            }
        }

        public static func ==(lhs: Pattern, rhs: Pattern) -> Bool {
            return lhs.fileId == rhs.fileId
        }
    }

    public let colors: UniqueGiftColors
    public let pattern: Pattern?

    public init(colors: UniqueGiftColors, pattern: Pattern?) {
        self.colors = colors
        self.pattern = pattern
    }

    public init?(gift: StarGift.UniqueGift) {
        self.init(attributes: gift.attributes)
    }

    public init?(gift: StarGift) {
        switch gift {
        case let .unique(unique):
            self.init(gift: unique)
        case .generic:
            return nil
        }
    }

    public init?(emojiStatus: PeerEmojiStatus) {
        switch emojiStatus.content {
        case let .starGift(_, _, _, _, patternFileId, innerColor, outerColor, patternColor, _):
            self.init(colors: UniqueGiftColors(center: innerColor, edge: outerColor, pattern: patternColor), pattern: .fileId(patternFileId))
        default:
            return nil
        }
    }

    public init?(attributes: [StarGift.UniqueGift.Attribute]) {
        var colors: UniqueGiftColors?
        var pattern: Pattern?
        for attribute in attributes {
            switch attribute {
            case let .backdrop(_, _, innerColor, outerColor, patternColor, _, _):
                colors = UniqueGiftColors(center: innerColor, edge: outerColor, pattern: patternColor)
            case let .pattern(_, file, _):
                pattern = .file(file)
            default:
                break
            }
        }
        guard let colors = colors else {
            return nil
        }
        self.init(colors: colors, pattern: pattern)
    }
}
