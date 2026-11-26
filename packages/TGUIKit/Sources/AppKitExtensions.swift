import Cocoa

public extension NSImage {
    
    // MARK: Extended functions
    
    /**
     Returns the NSImage with 'isTemplate' enabled
     This lets the UI draw the appropriate color
     according to background (e.g. dark in TouchBar)
     */
    func edit(size: NSSize? = nil,
              editCommand: @escaping (NSImage, NSSize) -> ()) -> NSImage {
        let temp = NSImage(size: size ?? self.size)
        
        guard temp.size.width > 0, temp.size.height > 0 else { return self }
        
        temp.lockFocus()
        editCommand(self, temp.size)
        temp.unlockFocus()
        
        return temp
    }
    
    /**
     Resizes NSImage
     - parameter newSize: the requested image size
     - parameter squareCrop: if true
     - returns: self scaled to requested size
     */
    func resized(to newSize: CGSize, squareCrop: Bool = true) -> NSImage {
        return self.edit(size: newSize) {
            image, size in
            
            var fromRect = NSZeroRect
            let inRect   = NSMakeRect(0, 0, size.width, size.height)
            
            if squareCrop, image.size.width != image.size.height {
                let minSize = min(image.size.width, image.size.height)
                let maxSize = max(image.size.width, image.size.height)
                let start   = ( maxSize - minSize ) / 2
                
                fromRect = NSMakeRect(
                    image.size.width   != minSize ? start : 0,
                    image.size.height  != minSize ? start : 0,
                    minSize,
                    minSize
                )
            }
            
            image.draw(in:        inRect,
                       from:      fromRect,
                       operation: .sourceOver,
                       fraction:  1.0)
        }
    }
    
    /**
     Changes NSImage alpha
     - parameter alpha: the requested alpha value
     - returns: self with requested alpha value
     */
    func withAlpha(_ alpha: CGFloat) -> NSImage {
        return self.edit {
            image, size in
            image.draw(in: NSMakeRect(0, 0, size.width, size.height),
                       from: NSZeroRect,
                       operation: .sourceOver,
                       fraction: alpha)
        }
    }
    
}

public extension Window {
    var titleView: NSView? {
        return self.standardWindowButton(.closeButton)?.superview
//        if let windowView = contentView?.superview {
//            return ObjcUtils.findElements(byClass: "NSTitlebarView", in: windowView).first
//        }
//        return nil
    }
}
