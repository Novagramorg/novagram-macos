import AppKit
import TGUIKit
import TelegramTheme

private let legacyMinDiameter: CGFloat = 3.5
private let legacyMaxDiameter: CGFloat = 8.0

func legacyInterpolate(from: CGFloat, to: CGFloat, value: CGFloat) -> CGFloat {
    return (1.0 - value) * from + value * to
}

func legacyRadiusFunction(_ value: CGFloat, timeOffset: CGFloat) -> CGFloat {
    var clampedValue: CGFloat = value + timeOffset
    if clampedValue > 1.0 {
        clampedValue = clampedValue - floor(clampedValue)
    }
    if clampedValue < 0.4 {
        return legacyInterpolate(from: legacyMinDiameter, to: legacyMaxDiameter, value: clampedValue / 0.4)
    }
    else if clampedValue < 0.8 {
        return legacyInterpolate(from: legacyMaxDiameter, to: legacyMinDiameter, value: (clampedValue - 0.4) / 0.4)
    }
    else {
        return legacyMinDiameter
    }
}

func legacyTextAnimatedImage(_ animationValue:CGFloat, color:UInt32) -> CGImage {
    return generateImage(NSMakeSize(26, 20), contextGenerator: { (size, context) in
        context.clear(NSMakeRect(0,0,size.width, size.height))
        let leftPadding: CGFloat = 5.0
        let topPadding: CGFloat = 7
        let distance: CGFloat = 12.0 / 2.0
        let minAlpha: CGFloat = 0.75
        let deltaAlpha: CGFloat = 1.0 - minAlpha
        var radius: CGFloat = 0.0
        var ellipse:NSRect = NSZeroRect
        radius =  legacyRadiusFunction(animationValue, timeOffset: 0.4)
        radius = (max(legacyMinDiameter, radius) - legacyMinDiameter) / (legacyMaxDiameter - legacyMinDiameter)
        radius = radius * 1.5
        var dotsColor: NSColor = NSColor(color, (radius * deltaAlpha + minAlpha))
        context.setFillColor(dotsColor.cgColor)
        ellipse = NSMakeRect(leftPadding - legacyMinDiameter / 2.0 - radius / 2.0, topPadding - legacyMinDiameter / 2.0 - radius / 2.0, legacyMinDiameter + radius, legacyMinDiameter + radius)
        context.fillEllipse(in: ellipse)
        radius = legacyRadiusFunction(animationValue, timeOffset: 0.2)
        radius = (max(legacyMinDiameter, radius) - legacyMinDiameter) / (legacyMaxDiameter - legacyMinDiameter)
        radius = radius * 1.5
        dotsColor = NSColor(color, (radius * deltaAlpha + minAlpha))
        context.setFillColor(dotsColor.cgColor)
        ellipse = NSMakeRect(leftPadding + distance - legacyMinDiameter / 2.0 - radius / 2.0, topPadding - legacyMinDiameter / 2.0 - radius / 2.0, legacyMinDiameter + radius, legacyMinDiameter + radius)
        context.fillEllipse(in: ellipse)
        radius = legacyRadiusFunction(animationValue, timeOffset: 0.0)
        radius = (max(legacyMinDiameter, radius) - legacyMinDiameter) / (legacyMaxDiameter - legacyMinDiameter)
        radius = radius * 1.5
        
        dotsColor = NSColor(color, (radius * deltaAlpha + minAlpha))
        context.setFillColor(dotsColor.cgColor)
        ellipse = NSMakeRect(leftPadding + distance * 2.0 - legacyMinDiameter / 2.0 - radius / 2.0, topPadding - legacyMinDiameter / 2.0 - radius / 2.0, legacyMinDiameter + radius, legacyMinDiameter + radius)
                
        context.fillEllipse(in: ellipse)
    })!
    
}

func legacyRecordingAnimatedImage(_ animationValue:CGFloat, color:UInt32) -> CGImage {
    return generateImage(NSMakeSize(26, 20), contextGenerator: { (size, context) in
        context.clear(NSMakeRect(0,0,size.width, size.height))
        context.setStrokeColor(NSColor(color).cgColor)
        context.setLineCap(.round)
        context.setLineWidth(3)
        
        let delta: CGFloat = 5.0
        let x: CGFloat = 4
        let y: CGFloat = 7.0
        let angle = CGFloat(18.0 * .pi / 180.0)
        let animationValue: CGFloat = animationValue * delta
        var radius: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        radius = animationValue
        
        alpha = radius/(3*delta);
        alpha = 1.0 - pow(cos(alpha * (CGFloat.pi/2)), 50);
        context.setAlpha(alpha);
        
        context.beginPath();
        context.addArc(center: NSMakePoint(x, y), radius: radius, startAngle: -angle, endAngle: angle, clockwise: false)
        context.strokePath();
        
        radius = animationValue + delta;
        
        alpha = radius / (3.0 * delta);
        alpha = 1.0 - pow(cos(alpha * CGFloat.pi), 10);
        context.setAlpha(alpha);
        
        context.beginPath();
        context.addArc(center: NSMakePoint(x, y), radius: radius, startAngle: -angle, endAngle: angle, clockwise: false)
        context.strokePath();
        
        radius = animationValue + delta*2;
        
        alpha = radius / (3.0 * delta);
        alpha = 1.0 - pow(cos(alpha * CGFloat.pi), 10);
        context.setAlpha(alpha);
        
        context.beginPath();
        context.addArc(center: NSMakePoint(x, y), radius: radius, startAngle: -angle, endAngle: angle, clockwise: false)
        context.strokePath();
        
    })!
    
}

func legacyChoosingStickerAnimatedImage(_ animationValue:CGFloat, color:NSColor) -> CGImage {
    return generateImage(NSMakeSize(24, 20), contextGenerator: { (size, context) in
        context.clear(size.bounds)
        context.setFillColor(color.cgColor)
        context.setStrokeColor(color.cgColor)
        var heightProgress: CGFloat = animationValue * 4.0
        if heightProgress > 3.0 {
            heightProgress = 4.0 - heightProgress
        } else if heightProgress > 2.0 {
            heightProgress = heightProgress - 2.0
            heightProgress *= heightProgress
        } else if heightProgress > 1.0 {
            heightProgress = 2.0 - heightProgress
        } else {
            heightProgress *= heightProgress
        }
        
        var pupilProgress: CGFloat = animationValue * 4.0
        if pupilProgress > 2.0 {
            pupilProgress = 3.0 - pupilProgress
        }
        pupilProgress = min(1.0, max(0.0, pupilProgress))
        pupilProgress *= pupilProgress
        
        var positionProgress: CGFloat = animationValue * 2.0
        if positionProgress > 1.0 {
            positionProgress = 2.0 - positionProgress
        }
        
        let eyeWidth: CGFloat = 6.0
        let eyeHeight: CGFloat = 11.0 - 2.0 * heightProgress

        let eyeOffset: CGFloat = -1.0 + positionProgress * 2.0
        let leftCenter = CGPoint(x: size.bounds.width / 2.0 - eyeWidth - 1.0 + eyeOffset, y: size.bounds.height / 2.0)
        let rightCenter = CGPoint(x: size.bounds.width / 2.0 + 1.0 + eyeOffset, y: size.bounds.height / 2.0)
        
        let pupilSize: CGFloat = 4.0
        let pupilCenter = CGPoint(x: -1.0 + pupilProgress * 2.0, y: 0.0)
        
        context.strokeEllipse(in: CGRect(x: leftCenter.x - eyeWidth / 2.0, y: leftCenter.y - eyeHeight / 2.0, width: eyeWidth, height: eyeHeight))
        context.fillEllipse(in: CGRect(x: leftCenter.x - pupilSize / 2.0 + pupilCenter.x * eyeWidth / 4.0, y: leftCenter.y - pupilSize / 2.0, width: pupilSize, height: pupilSize))
        
        context.strokeEllipse(in: CGRect(x: rightCenter.x - eyeWidth / 2.0, y: rightCenter.y - eyeHeight / 2.0, width: eyeWidth, height: eyeHeight))
        context.fillEllipse(in: CGRect(x: rightCenter.x - pupilSize / 2.0 + pupilCenter.x * eyeWidth / 4.0, y: rightCenter.y - pupilSize / 2.0, width: pupilSize, height: pupilSize))
        
    })!
    
}

func legacyUploadFileAnimatedImage(_ animationValue:CGFloat, backgroundColor:UInt32, foregroundColor: UInt32) -> CGImage {
    return generateImage(NSMakeSize(26, 20), contextGenerator: { (size, context) in
        context.clear(NSMakeRect(0,0,size.width, size.height))
        let leftPadding: CGFloat = 7.0
        let topPadding: CGFloat = 4.0
        let progressWidth: CGFloat = 26.0 / 2.0
        let progressHeight: CGFloat = 10.0 / 2.0
        var progress: CGFloat = 0.0
        var dotsColor = NSColor(backgroundColor)
        context.setFillColor(dotsColor.cgColor)
        context.addPath(CGPath(roundedRect: CGRect(x: leftPadding, y: topPadding, width: progressWidth, height: progressHeight), cornerWidth: 2, cornerHeight: 2, transform: nil))
        context.closePath()
        context.fillPath()
        dotsColor = NSColor(foregroundColor, 0.3)
        context.setFillColor(dotsColor.cgColor)
        
        context.addPath(CGPath(roundedRect: CGRect(x: leftPadding, y: topPadding, width: progressWidth, height: progressHeight), cornerWidth: 2, cornerHeight: 2, transform: nil))
        context.closePath()
        context.fillPath()
        
        progress = legacyInterpolate(from: 0.0, to: progressWidth * 2.0, value: animationValue)
        dotsColor = NSColor(foregroundColor, 1.0)
        context.setFillColor(dotsColor.cgColor)
        context.setBlendMode(.sourceIn)
        context.addPath(CGPath(roundedRect: CGRect(x: CGFloat(leftPadding - progressWidth + progress), y: topPadding, width: progressWidth, height: progressHeight), cornerWidth: 2, cornerHeight: 2, transform: nil))
        context.closePath()
        context.fillPath()

        
    })!
    
}






func legacyRecordVoiceActivityAnimation(_ color: NSColor) -> [CGImage] {
    var steps:[CGImage] = []
    
    for i in 0 ..< 42 {
        steps.append(legacyRecordingAnimatedImage( CGFloat(i) / 42, color: color.rgb))
    }
    return steps
}

func legacyChoosingStickerActivityAnimation(_ color: NSColor) -> [CGImage] {
    var steps:[CGImage] = []
    for i in 0 ..< 120 {
        steps.append(legacyChoosingStickerAnimatedImage( CGFloat(i) / 120, color: color))
    }
    return steps
}

func legacyUploadFileActivityAnimation(_ foregroundColor: NSColor, _ backgroundColor: NSColor) -> [CGImage] {
    var steps:[CGImage] = []
    
    for i in 0 ..< 105 {
        steps.append(legacyUploadFileAnimatedImage( CGFloat(i) / 105, backgroundColor: backgroundColor.rgb, foregroundColor: foregroundColor.rgb))
    }
    return steps
}

func legacyTextActivityAnimation(_ color: NSColor) -> [CGImage] {
    var steps:[CGImage] = []
    
    for i in 0 ..< 42 {
        steps.append(legacyTextAnimatedImage( CGFloat(i) / 42, color: color.rgb))
    }
    return steps
}
