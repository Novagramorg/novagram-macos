import Cocoa
import TGUIKit
extension NSAttributedString {
    static func referenceInitialize(string:String?, color:NSColor? = nil, font:NSFont? = .normal(.text)) -> NSAttributedString {
        let attr:NSMutableAttributedString = NSMutableAttributedString()
        _ = attr.append(string: string, color: color, font: font)
        
        return attr.copy() as! NSAttributedString
    }
}
