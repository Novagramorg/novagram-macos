import Cocoa
import Postbox
import TelegramCore
import ThemeSettings

public extension Wallpaper {
    var dimensions: NSSize {
        switch self {
        case let .file(_, file, _, _, _):
            if let dimensions = file.dimensions {
                return dimensions.size
            }
             return NSMakeSize(300, 300)
        case let .image(representations, _):
            let largest = largestImageRepresentation(representations)
            return largest!.dimensions.size
        case let .custom(representation, _):
            return representation.dimensions.size
        case .color:
            return NSMakeSize(300, 300)
        default:
            return NSZeroSize
        }
       
    }
}
