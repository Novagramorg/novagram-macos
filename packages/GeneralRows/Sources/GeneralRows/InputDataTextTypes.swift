import Cocoa
import TGUIKit
import TelegramCore
#if SHARE
import TelegramThemeShare
import TelegramContextShare
#else
import TelegramTheme
import TelegramContext
#endif

public final class InputDataTextInsertAnimatedViewData : NSObject {
    public let context: any AccountContextProtocol
    public let file: TelegramMediaFile
    public init(context: any AccountContextProtocol, file: TelegramMediaFile) {
        self.context = context
        self.file = file
    }
    public static func == (lhs: InputDataTextInsertAnimatedViewData, rhs: InputDataTextInsertAnimatedViewData) -> Bool {
        return lhs.file == rhs.file
    }
    public static var attributeKey: NSAttributedString.Key {
        return NSAttributedString.Key("InputDataTextInsertAnimatedDataKey")
    }
}

public struct InputDataGeneralTextRightData : Equatable {
    public static func == (lhs: InputDataGeneralTextRightData, rhs: InputDataGeneralTextRightData) -> Bool {
        return lhs.text == rhs.text && lhs.isLoading == rhs.isLoading && lhs.update == rhs.update && lhs.cornerRadius == rhs.cornerRadius
    }
    
    public let isLoading: Bool
    public let text: NSAttributedString?
    public let action:(()->Void)?
    public let alignToText: Bool
    public let wrap: NSColor?
    private let update: UInt32?
    public let contextMenu:(()->[ContextMenuItem])?
    public let afterImage: CGImage?
    public let cornerRadius: CGFloat
    public init(isLoading: Bool, text: NSAttributedString?, action:(()->Void)? = nil, update: UInt32? = nil, alignToText: Bool = false, wrap: NSColor? = nil, contextMenu:(()->[ContextMenuItem])? = nil, afterImage: CGImage? = nil, cornerRadius: CGFloat = .cornerRadius) {
        self.isLoading = isLoading
        self.text = text
        self.alignToText = alignToText
        self.wrap = wrap
        self.action = action
        self.update = update
        self.contextMenu = contextMenu
        self.afterImage = afterImage
        self.cornerRadius = cornerRadius
    }
}
