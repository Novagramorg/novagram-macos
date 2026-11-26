import Cocoa

open class TableStickView: TableRowView {

    open var header:Bool = false {
        didSet {
            if header != oldValue {
                needsDisplay = true
            }
        }
    }
    
    open var isAlwaysUp: Bool {
        return false
    }
    
    open func updateIsVisible(_ visible: Bool, animated: Bool) {
        
    }
    
    open override var backdorColor: NSColor {
        return .clear
    }
    
    
    open override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
    }
    
}
