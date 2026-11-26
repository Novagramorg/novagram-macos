import AppKit
import TGUIKit

enum TestBootstrap {
    private static var retained: [NSImage] = []

    static let installed: Void = {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        System.updateScaleFactor(2)
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
}
