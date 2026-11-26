import Cocoa
import TGUIKit
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif


public enum DynamicItemSide {
    case top
    case bottom
}
open class DynamicHeightRowItem: GeneralRowItem {
    private let side:DynamicItemSide
    public init(_ initialSize: NSSize, stableId: AnyHashable, side: DynamicItemSide) {
        self.side = side
        super.init(initialSize, stableId: stableId)
    }
    
    open override var height: CGFloat {
        if let table = table {
            var tableHeight: CGFloat = 0
            table.enumerateItems { item -> Bool in
                if !item.reloadOnTableHeightChanged {
                    tableHeight += item.height
                }
                return true
            }
            
            return max((table.frame.height - tableHeight) / 2, 0)
        } else {
            return 0
        }
    }
    
    open override var instantlyResize: Bool {
        return true
    }
    open override var reloadOnTableHeightChanged: Bool {
        return true
    }
    
    open override func viewClass() -> AnyClass {
        return DynamicHeightRowView.self
    }

    open override var accessibilityIsSpacer: Bool {
        return true
    }
}

private final class DynamicHeightRowView : TableRowView {
    public override func updateColors() {
        
    }
    
    public override var firstResponder: NSResponder? {
        return nil
    }
}
