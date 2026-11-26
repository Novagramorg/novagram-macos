import Cocoa

func legacyDrawTextLineRuns(_ line: CTLine, in context: CGContext, at position: CGPoint? = nil, maximumGlyphCount: Int? = nil, drawnGlyphCount: inout Int) {
    let runs = CTLineGetGlyphRuns(line) as NSArray
    if runs.count != 0 {
        for item in runs {
            let run = item as! CTRun
            let glyphCount = CTRunGetGlyphCount(run)
            _ = CTRunGetStringRange(run)
            if let position {
                context.textPosition = position
            }
            if let maximumGlyphCount {
                if drawnGlyphCount >= maximumGlyphCount {
                    break
                }
                let count = max(0, min(glyphCount, maximumGlyphCount - drawnGlyphCount))
                CTRunDraw(run, context, CFRange(location: 0, length: count))
                drawnGlyphCount += glyphCount
            } else {
                CTRunDraw(run, context, CFRange(location: 0, length: glyphCount))
            }
        }
    }
}
