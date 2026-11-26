import AppKit
import TGUIKit

private let labImages: [NSImage] = ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"].map { name in
    let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
        NSColor.black.setFill()
        rect.insetBy(dx: 4, dy: 4).fill()
        return true
    }
    image.setName(name)
    return image
}

func initializeSearchViewLab() {
    _ = NSApplication.shared
    _ = labImages
    System.updateScaleFactor(2)
    System.liquidGlass = false
}
