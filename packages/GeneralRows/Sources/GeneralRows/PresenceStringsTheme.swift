import Cocoa
import TelegramCore
import TGUIKit
#if SHARE
import TelegramUtilsShare
#else
import TelegramUtils
#endif

public func stringAndActivityForUserPresence(_ presence: TelegramUserPresence, timeDifference: TimeInterval, relativeTo timestamp: Int32, expanded: Bool = false, customTheme: GeneralRowItem.Theme? = nil) -> (String, Bool, NSColor) {
    return userPresenceText(presence, timeDifference: timeDifference, relativeTo: timestamp, expanded: expanded, customTheme: customTheme.map { UserPresenceColors(grayTextColor: $0.grayTextColor, accentColor: $0.accentColor) })
}
