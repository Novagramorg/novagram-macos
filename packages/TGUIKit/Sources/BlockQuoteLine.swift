import Foundation
import AppKit

public func drawBlockQuoteLine(ctx: CGContext, blockFrame: CGRect, radius: CGFloat, lineWidth: CGFloat, tintColor: NSColor, secondaryTintColor: NSColor?, tertiaryTintColor: NSColor?) {
    let lineFrame = CGRect(origin: CGPoint(x: blockFrame.minX, y: blockFrame.minY), size: CGSize(width: lineWidth, height: blockFrame.height))
    ctx.move(to: CGPoint(x: lineFrame.minX, y: lineFrame.minY + radius))
    ctx.addArc(tangent1End: CGPoint(x: lineFrame.minX, y: lineFrame.minY), tangent2End: CGPoint(x: lineFrame.minX + radius, y: lineFrame.minY), radius: radius)
    ctx.addLine(to: CGPoint(x: lineFrame.minX + radius, y: lineFrame.maxY))
    ctx.addArc(tangent1End: CGPoint(x: lineFrame.minX, y: lineFrame.maxY), tangent2End: CGPoint(x: lineFrame.minX, y: lineFrame.maxY - radius), radius: radius)
    ctx.closePath()
    ctx.clip()
    
    if let secondaryTintColor = secondaryTintColor {
        let isMonochrome = secondaryTintColor.alpha == 0.2

        do {
            ctx.saveGState()
            
            let dashHeight: CGFloat = tertiaryTintColor != nil ? 6.0 : 9.0
            let dashOffset: CGFloat
            if let _ = tertiaryTintColor {
                dashOffset = isMonochrome ? -2.0 : 0.0
            } else {
                dashOffset = isMonochrome ? -4.0 : 5.0
            }
        
            if isMonochrome {
                ctx.setFillColor(tintColor.withMultipliedAlpha(0.2).cgColor)
                ctx.fill(lineFrame)
                ctx.setFillColor(tintColor.cgColor)
            } else {
                ctx.setFillColor(tintColor.cgColor)
                ctx.fill(lineFrame)
                ctx.setFillColor(secondaryTintColor.cgColor)
            }
            
            func drawDashes() {
                ctx.translateBy(x: blockFrame.minX, y: blockFrame.minY + dashOffset)
                
                var offset = 0.0
                while offset < blockFrame.height {
                    ctx.move(to: CGPoint(x: 0.0, y: 3.0))
                    ctx.addLine(to: CGPoint(x: lineWidth, y: 0.0))
                    ctx.addLine(to: CGPoint(x: lineWidth, y: dashHeight))
                    ctx.addLine(to: CGPoint(x: 0.0, y: dashHeight + 3.0))
                    ctx.closePath()
                    ctx.fillPath()
                    
                    ctx.translateBy(x: 0.0, y: 18.0)
                    offset += 18.0
                }
            }
            
            drawDashes()
            ctx.restoreGState()
            
            if let tertiaryTintColor = tertiaryTintColor {
                ctx.saveGState()
                ctx.translateBy(x: 0.0, y: dashHeight)
                if isMonochrome {
                    ctx.setFillColor(tintColor.withAlphaComponent(0.4).cgColor)
                } else {
                    ctx.setFillColor(tertiaryTintColor.cgColor)
                }
                drawDashes()
                ctx.restoreGState()
            }
        }
    } else {
        ctx.setFillColor(tintColor.cgColor)
        ctx.fill(lineFrame)
    }
    
    ctx.resetClip()
}
