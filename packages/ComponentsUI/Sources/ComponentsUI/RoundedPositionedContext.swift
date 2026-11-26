import Cocoa
import TGUIKit

extension CGContext {
    func roundPositioned(_ size: NSSize, _ cornerRadius: CGFloat = .cornerRadius, positionFlags: LayoutPositionFlags? = nil) {
        let minx:CGFloat = 0, midx = size.width/2.0, maxx = size.width
        let miny:CGFloat = 0, midy = size.height/2.0, maxy = size.height
        
        self.move(to: NSMakePoint(minx, midy))
        
        var topLeftRadius: CGFloat = cornerRadius
        var bottomLeftRadius: CGFloat = cornerRadius
        var topRightRadius: CGFloat = cornerRadius
        var bottomRightRadius: CGFloat = cornerRadius
        
        
        if let positionFlags = positionFlags {
            if positionFlags.contains(.top) && positionFlags.contains(.left) {
                topLeftRadius = topLeftRadius * 3 + 2
            }
            if positionFlags.contains(.top) && positionFlags.contains(.right) {
                topRightRadius = topRightRadius * 3 + 2
            }
            if positionFlags.contains(.bottom) && positionFlags.contains(.left) {
                bottomLeftRadius = bottomLeftRadius * 3 + 2
            }
            if positionFlags.contains(.bottom) && positionFlags.contains(.right) {
                bottomRightRadius = bottomRightRadius * 3 + 2
            }
        }
        
        self.addArc(tangent1End: NSMakePoint(minx, miny), tangent2End: NSMakePoint(midx, miny), radius: topLeftRadius)
        self.addArc(tangent1End: NSMakePoint(maxx, miny), tangent2End: NSMakePoint(maxx, midy), radius: topRightRadius)
        self.addArc(tangent1End: NSMakePoint(maxx, maxy), tangent2End: NSMakePoint(midx, maxy), radius: bottomRightRadius)
        self.addArc(tangent1End: NSMakePoint(minx, maxy), tangent2End: NSMakePoint(minx, midy), radius: bottomLeftRadius)
        
        self.closePath()
        self.clip()
        
    }
}
