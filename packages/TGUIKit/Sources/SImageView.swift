import Cocoa

public class SImageView: NSView {

    public init() {
        super.init(frame: NSZeroRect)
        wantsLayer = true
    }
    
    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required override init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
    
    public var data: (CGImage, NSEdgeInsets)? {
        didSet {
            if let image = data {
                layer?.contentsScale = System.backingScale
                let imageSize = image.0.backingSize
                let insets = image.1
                let halfPixelFudge: CGFloat = 0.49
                let otherPixelFudge: CGFloat = 0.02
                var contentsCenter: CGRect  = NSMakeRect(0.0, 0.0, 1.0, 1.0);
                if (insets.left > 0 || insets.right > 0) {
                    contentsCenter.origin.x = ((insets.left + halfPixelFudge) / imageSize.width);
                    contentsCenter.size.width = (imageSize.width - (insets.left + insets.right + 1.0) + otherPixelFudge) / imageSize.width;
                }
                if (insets.top > 0 || insets.bottom > 0) {
                    contentsCenter.origin.y = ((insets.top + halfPixelFudge) / imageSize.height);
                    contentsCenter.size.height = (imageSize.height - (insets.top + insets.bottom + 1.0) + otherPixelFudge) / imageSize.height;
                }
                self.layer?.contentsGravity = .resize;
                self.layer?.contentsCenter = contentsCenter;
                self.layer?.contents = image.0
            } else {
                self.layer?.contents = nil
            }
            
        }
    }
    
    
}
