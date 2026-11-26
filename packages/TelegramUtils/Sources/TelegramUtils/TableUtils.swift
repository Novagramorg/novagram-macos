import Cocoa

import TGUIKit
import TelegramCore
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif


public protocol TableItemListNodeEntry: Comparable, Identifiable {
    associatedtype ItemGenerationArguments
    
    func item(_ arguments: ItemGenerationArguments, initialSize: NSSize) -> TableRowItem
}

public protocol ItemListItemTag {
    func isEqual(to other: ItemListItemTag) -> Bool
}

