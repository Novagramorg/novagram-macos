import Cocoa
import struct TGUIKit.System
import struct TGUIKitBaseline.System

enum TGUIKitTestBootstrap {
    private static var retained: [NSImage] = []
    private static let installed: Void = {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        TGUIKit.System.updateScaleFactor(2)
        TGUIKitBaseline.System.updateScaleFactor(2)
        TGUIKit.System.liquidGlass = false
        TGUIKitBaseline.System.liquidGlass = false
        for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"] {
            let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                NSColor.black.setFill()
                rect.insetBy(dx: 4, dy: 4).fill()
                return true
            }
            _ = image.setName(name)
            retained.append(image)
        }
    }()
    static func install() { _ = installed }
}
