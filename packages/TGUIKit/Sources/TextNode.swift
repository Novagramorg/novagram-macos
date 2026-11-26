import Cocoa

private let defaultFont:NSFont = .normal(.text)

private final class TextNodeLine {
    let line: CTLine
    let frame: CGRect
    
    init(line: CTLine, frame: CGRect) {
        self.line = line
        self.frame = frame
    }
}

public enum TextNodeCutoutPosition {
    case TopLeft
    case TopRight
}

public struct TextNodeCutout: Equatable {
    public let position: TextNodeCutoutPosition
    public let size: NSSize
    public init(position: TextNodeCutoutPosition, size: NSSize) {
        self.position = position
        self.size = size
    }
}

public func ==(lhs: TextNodeCutout, rhs: TextNodeCutout) -> Bool {
    return lhs.position == rhs.position && lhs.size == rhs.size
}

public final class TextNodeLayout: NSObject {
    fileprivate let attributedString: NSAttributedString?
    fileprivate let maximumNumberOfLines: Int
    fileprivate let truncationType: CTLineTruncationType
    fileprivate let lineSpacing: CGFloat
    fileprivate let constrainedSize: NSSize
    fileprivate let cutout: TextNodeCutout?
    fileprivate let alignment:NSTextAlignment
    fileprivate let renderedSelected: Bool
    public let isPerfectSized: Bool
    public let size: NSSize
    fileprivate let lines: [TextNodeLine]
    public var selected:Bool = false
    
    fileprivate init(attributedString: NSAttributedString?, maximumNumberOfLines: Int, truncationType: CTLineTruncationType, constrainedSize: NSSize, cutout: TextNodeCutout?, size: NSSize, lines: [TextNodeLine], lineSpacing: CGFloat, selected: Bool, alignment:NSTextAlignment = .left, isPerfectSized: Bool) {
        self.attributedString = attributedString
        self.maximumNumberOfLines = maximumNumberOfLines
        self.truncationType = truncationType
        self.constrainedSize = constrainedSize
        self.cutout = cutout
        self.size = size
        self.lines = lines
        self.lineSpacing = lineSpacing
        self.renderedSelected = selected
        self.selected = selected
        self.alignment = alignment
        self.isPerfectSized = isPerfectSized
    }
    
    public var numberOfLines: Int {
        return self.lines.count
    }
    
    public var firstLineWidth: CGFloat {
        if let first = self.lines.first {
            return first.frame.width
        } else {
            return 0.0
        }
    }
    
    var trailingLineWidth: CGFloat {
        if let lastLine = self.lines.last {
            return lastLine.frame.width
        } else {
            return 0.0
        }
    }
}

public class TextNode: NSObject {
    private var currentLayout: TextNodeLayout?
    public var backgroundColor:NSColor
    
    public override init() {
        self.backgroundColor = NSColor.red
        super.init()
    }
    
    deinit {
        var bp:Int = 0
        bp += 1
    }
    
    
    private class func getlayout(attributedString: NSAttributedString?, maximumNumberOfLines: Int, truncationType: CTLineTruncationType, backgroundColor: NSColor?, constrainedSize: NSSize, cutout: TextNodeCutout?, selected:Bool, alignment:NSTextAlignment, lineSpacing: CGFloat? = nil) -> TextNodeLayout {
        
        let source = attributedString?.copy() as? NSAttributedString
        var attr = source
        let isPerfectSized = false
        if let a = attr {
            if (selected && a.length > 0) {
                
                let c:NSMutableAttributedString = a.mutableCopy() as! NSMutableAttributedString
                
                if let color = c.attribute(.selectedColor, at: 0, effectiveRange: nil) {
                    c.addAttribute(NSAttributedString.Key.foregroundColor, value: color, range: c.range)
                }
                
                attr = c
                
            }

        }
        
        
        if let attributedString = attr {
            

            let font: CTFont
            if attributedString.length != 0 {
                if let stringFont = attributedString.attribute(NSAttributedString.Key(kCTFontAttributeName as String), at: 0, effectiveRange: nil) {
                    font = stringFont as! CTFont
                } else {
                    font = defaultFont
                }
            } else {
                font = defaultFont
            }
            
            let fontAscent = CTFontGetAscent(font)
            let fontDescent = CTFontGetDescent(font)
            let fontLineHeight = floor(fontAscent + fontDescent) + (lineSpacing ?? 0)
            let fontLineSpacing = floor(fontLineHeight * 0.12)
            
            var lines: [TextNodeLine] = []
            
           
            
            var maybeTypesetter: CTTypesetter?
            let useDirectLine = maximumNumberOfLines == 1 && attributedString.length > 0 && constrainedSize.width > 0 && constrainedSize.width.isFinite && (constrainedSize.width - (cutout?.size.width ?? 0)).isFinite
            if !useDirectLine {
                maybeTypesetter = CTTypesetterCreateWithAttributedString(attributedString as CFAttributedString)
            }
            if !useDirectLine && maybeTypesetter == nil {
                return TextNodeLayout(attributedString: source, maximumNumberOfLines: maximumNumberOfLines, truncationType: truncationType, constrainedSize: constrainedSize, cutout: cutout, size: NSSize(), lines: [], lineSpacing: lineSpacing ?? 0, selected: selected, alignment:alignment, isPerfectSized: true)
            }
            
            let typesetter = maybeTypesetter
            
            var lastLineCharacterIndex: CFIndex = 0
            var layoutSize = NSSize()
            
            var cutoutEnabled = false
            var cutoutMinY: CGFloat = 0.0
            var cutoutMaxY: CGFloat = 0.0
            var cutoutWidth: CGFloat = 0.0
            var cutoutOffset: CGFloat = 0.0
            if let cutout = cutout {
                cutoutMinY = -fontLineSpacing
                cutoutMaxY = cutout.size.height + fontLineSpacing
                cutoutWidth = cutout.size.width
                if case .TopLeft = cutout.position {
                    cutoutOffset = cutoutWidth
                }
                cutoutEnabled = true
            }
            
            var first = true
            while true {
                var lineConstrainedWidth = constrainedSize.width
                var lineOriginY = floor(layoutSize.height + fontLineHeight - fontLineSpacing * 2.0)
                if !first {
                    lineOriginY += fontLineSpacing
                }
                var lineCutoutOffset: CGFloat = 0.0
                var lineAdditionalWidth: CGFloat = 0.0
                
                if cutoutEnabled {
                    if lineOriginY < cutoutMaxY && lineOriginY + fontLineHeight > cutoutMinY {
                        lineConstrainedWidth = max(1.0, lineConstrainedWidth - cutoutWidth)
                        lineCutoutOffset = cutoutOffset
                        lineAdditionalWidth = cutoutWidth
                    }
                }
                
                let isLastAllowedLine = maximumNumberOfLines > 0 && lines.count == maximumNumberOfLines - 1
                let lineCharacterCount: CFIndex
                if isLastAllowedLine && lastLineCharacterIndex < attributedString.length && lineConstrainedWidth > 0 && lineConstrainedWidth.isFinite {
                    lineCharacterCount = 1
                } else {
                    lineCharacterCount = CTTypesetterSuggestLineBreak(typesetter!, lastLineCharacterIndex, Double(lineConstrainedWidth))
                }
                
                if isLastAllowedLine && lineCharacterCount > 0 {
                    if first {
                        first = false
                    } else {
                        layoutSize.height += fontLineSpacing
                    }
                    
                    let coreTextLine: CTLine
                    let lineWidth: CGFloat
                    
                    let originalLine = useDirectLine ? CTLineCreateWithAttributedString(attributedString as CFAttributedString) : CTTypesetterCreateLineWithOffset(typesetter!, CFRange(location: lastLineCharacterIndex, length: attributedString.length - lastLineCharacterIndex), 0.0)
                    
                    let originalLineWidth = CTLineGetTypographicBounds(originalLine, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(originalLine)
                    if originalLineWidth < Double(constrainedSize.width) {
                        coreTextLine = originalLine
                        lineWidth = ceil(CGFloat(originalLineWidth))
                    } else {
                        var truncationTokenAttributes: [NSAttributedString.Key : Any] = [:]
                        truncationTokenAttributes[NSAttributedString.Key(kCTFontAttributeName as String)] = font
                        truncationTokenAttributes[NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String)] = true as NSNumber
                        let tokenString = "\u{2026}"
                        let truncatedTokenString = NSAttributedString(string: tokenString, attributes: truncationTokenAttributes)
                        let truncationToken = CTLineCreateWithAttributedString(truncatedTokenString)
                        
                        coreTextLine = CTLineCreateTruncatedLine(originalLine, Double(constrainedSize.width), truncationType, truncationToken) ?? truncationToken
                        lineWidth = ceil(CGFloat(CTLineGetTypographicBounds(coreTextLine, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(coreTextLine)))
                    }

                    let lineFrame = CGRect(x: lineCutoutOffset, y: lineOriginY, width: lineWidth, height: fontLineHeight)
                    layoutSize.height += fontLineHeight + fontLineSpacing
                    layoutSize.width = max(layoutSize.width, lineWidth + lineAdditionalWidth)
                    
                    lines.append(TextNodeLine(line: coreTextLine, frame: lineFrame))
                    
                    break
                } else {
                    if lineCharacterCount > 0 {
                        if first {
                            first = false
                        } else {
                            layoutSize.height += fontLineSpacing
                        }
                        
                        let coreTextLine = CTTypesetterCreateLineWithOffset(typesetter!, CFRangeMake(lastLineCharacterIndex, lineCharacterCount), 100.0)
                        lastLineCharacterIndex += lineCharacterCount
                        
                        let lineWidth = ceil(CGFloat(CTLineGetTypographicBounds(coreTextLine, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(coreTextLine)))
                        let lineFrame = CGRect(x: lineCutoutOffset, y: lineOriginY, width: lineWidth, height: fontLineHeight)
                        layoutSize.height += fontLineHeight
                        layoutSize.width = max(layoutSize.width, lineWidth + lineAdditionalWidth)
                        
                       
                        
                        lines.append(TextNodeLine(line: coreTextLine, frame: lineFrame))
                    } else {
                        if !lines.isEmpty {
                            layoutSize.height += fontLineSpacing
                        }
                        break
                    }
                }
            }
            
            return TextNodeLayout(attributedString: source, maximumNumberOfLines: maximumNumberOfLines, truncationType: truncationType, constrainedSize: constrainedSize, cutout: cutout, size: NSSize(width: ceil(layoutSize.width), height: ceil(layoutSize.height)), lines: lines, lineSpacing: lineSpacing ?? 0, selected: selected, alignment:alignment, isPerfectSized: isPerfectSized)
        } else {
            return TextNodeLayout(attributedString: source, maximumNumberOfLines: maximumNumberOfLines, truncationType: truncationType, constrainedSize: constrainedSize, cutout: cutout, size: NSSize(), lines: [], lineSpacing: lineSpacing ?? 0, selected: selected, alignment:alignment, isPerfectSized: isPerfectSized)
        }
    }
    

    open func draw(_ dirtyRect: NSRect, in ctx: CGContext, backingScaleFactor: CGFloat, backgroundColor: NSColor) {
        
        if !System.supportsTransparentFontDrawing {
            if backingScaleFactor == 1.0 {
                ctx.setFillColor(backgroundColor.cgColor)
                ctx.fill(dirtyRect)
            }
            
            ctx.setAllowsAntialiasing(true)
            ctx.setAllowsFontSmoothing(backingScaleFactor == 1.0)
            ctx.setShouldSmoothFonts(backingScaleFactor == 1.0)
            
            ctx.setAllowsFontSubpixelPositioning(true)
            ctx.setShouldSubpixelPositionFonts(true)
        } else {
            ctx.setAllowsFontSubpixelPositioning(true)
            ctx.setShouldSubpixelPositionFonts(true)
            
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)
            
            ctx.setAllowsFontSmoothing(backingScaleFactor == 1.0)
            ctx.setShouldSmoothFonts(backingScaleFactor == 1.0)
        }

        
        
        //let contextPtr = NSGraphicsContext.current()?.graphicsPort
        let context:CGContext = ctx //unsafeBitCast(contextPtr, to: CGContext.self)
        

        

       // ctx.setAllowsFontSmoothing(true)
       // ctx.setAllowsAntialiasing(true)
//        context.setAllowsAntialiasing(true)
//        context.setShouldSmoothFonts(!System.isRetina)
//        context.setAllowsFontSmoothing(!System.isRetina)
        
        if #available(OSX 10.11, *) {
            
        } else {
           // context.setBlendMode(.hardLight)
        }
        
        if let layout = self.currentLayout {
            let textMatrix = context.textMatrix
            let textPosition = context.textPosition
            context.textMatrix = CGAffineTransform(scaleX: 1.0, y: -1.0)
             for i in 0 ..< layout.lines.count {
                let line = layout.lines[i]
                
                var penFlush:CGFloat = 0.0
                if layout.alignment == .center {
                    penFlush = 0.5
                }
                
                let penOffset = CGFloat( CTLineGetPenOffsetForFlush(line.line, penFlush, Double(dirtyRect.width)))

                context.textPosition = CGPoint(x: penOffset + dirtyRect.minX + line.frame.minX, y: line.frame.minY + dirtyRect.minY)
                
               
                var drawnGlyphCount = 0
                drawTextLineRuns(line.line, in: context, drawnGlyphCount: &drawnGlyphCount)
                                
            }
            
            context.textMatrix = textMatrix
            context.textPosition = CGPoint(x: textPosition.x, y: textPosition.y)
        }
        
      //  context.setBlendMode(.normal)
    }
    

    
    open class func layoutText(maybeNode:TextNode? = nil, _ attributedString: NSAttributedString?, _ backgroundColor: NSColor?, _ maximumNumberOfLines: Int, _ truncationType: CTLineTruncationType, _ constrainedSize: NSSize, _ cutout: TextNodeCutout?,_ selected:Bool, _ alignment:NSTextAlignment, _ lineSpacing: CGFloat? = nil) -> (TextNodeLayout, TextNode) {
        
        let existingLayout: TextNodeLayout? = maybeNode?.currentLayout
        
        let layout: TextNodeLayout
        
        if let existingLayout = existingLayout, existingLayout.constrainedSize == constrainedSize && existingLayout.maximumNumberOfLines == maximumNumberOfLines && existingLayout.truncationType == truncationType && existingLayout.cutout == cutout && existingLayout.selected == selected && existingLayout.renderedSelected == selected && existingLayout.alignment == alignment && existingLayout.lineSpacing == (lineSpacing ?? 0) {
            let stringMatch: Bool
            if let existingString = existingLayout.attributedString, let string = attributedString {
                stringMatch = existingString.isEqual(to: string)
            } else if existingLayout.attributedString == nil && attributedString == nil {
                stringMatch = true
            } else {
                stringMatch = false
            }
            
            if stringMatch {
                layout = existingLayout
            } else {
                layout = TextNode.getlayout(attributedString: attributedString, maximumNumberOfLines: maximumNumberOfLines, truncationType: truncationType, backgroundColor: backgroundColor, constrainedSize: constrainedSize, cutout: cutout,selected:selected, alignment: alignment, lineSpacing: lineSpacing)
            }
        } else {
            layout = TextNode.getlayout(attributedString: attributedString, maximumNumberOfLines: maximumNumberOfLines, truncationType: truncationType, backgroundColor: backgroundColor, constrainedSize: constrainedSize, cutout: cutout,selected:selected, alignment: alignment, lineSpacing: lineSpacing)
        }
        
        let node = maybeNode ?? TextNode()
        node.currentLayout = layout
        return (layout, node)
    }
}
