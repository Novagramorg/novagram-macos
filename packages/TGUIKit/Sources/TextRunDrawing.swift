import Cocoa

@inline(__always)
func drawTextLineRuns(_ line: CTLine, in context: CGContext, at position: CGPoint? = nil, maximumGlyphCount: Int? = nil, drawnGlyphCount: inout Int) {
    let runs = CTLineGetGlyphRuns(line)
    if let maximumGlyphCount {
        for index in 0..<CFArrayGetCount(runs) {
            let run = unsafeBitCast(CFArrayGetValueAtIndex(runs, index), to: CTRun.self)
            let glyphCount = CTRunGetGlyphCount(run)
            if let position {
                context.textPosition = position
            }
            if drawnGlyphCount >= maximumGlyphCount {
                break
            }
            let count = max(0, min(glyphCount, maximumGlyphCount - drawnGlyphCount))
            CTRunDraw(run, context, CFRange(location: 0, length: count))
            drawnGlyphCount += glyphCount
        }
    } else {
        for index in 0..<CFArrayGetCount(runs) {
            let run = unsafeBitCast(CFArrayGetValueAtIndex(runs, index), to: CTRun.self)
            let glyphCount = CTRunGetGlyphCount(run)
            if let position {
                context.textPosition = position
            }
            CTRunDraw(run, context, CFRange(location: 0, length: glyphCount))
        }
    }
}
