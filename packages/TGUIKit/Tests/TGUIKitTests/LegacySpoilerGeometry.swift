import Cocoa
import TGUIKit

extension TextViewLayout {
    func legacySpoilerRects(_ spoilers: [Spoiler], _ checkRevealed: Bool = true) -> [(CGRect, Spoiler)] {
        if spoilers.isEmpty {
            return []
        }
        var rects:[(CGRect, Spoiler)] = []
        for i in 0 ..< lines.count {
            let line = lines[i]
            for spoiler in spoilers.filter({ !$0.isRevealed || !checkRevealed }) {
                if let spoilerRange = spoiler.range.intersection(line.range) {
                    let range = spoilerRange.intersection(selectedRange.range)

                    var ranges:[(NSRange, NSColor)] = []
                    if let range = range {
                        ranges.append((NSMakeRange(spoiler.range.lowerBound, range.lowerBound - spoiler.range.lowerBound), spoiler.color))
                        ranges.append((NSMakeRange(spoiler.range.upperBound, range.upperBound - spoiler.range.upperBound), spoiler.color))
                    } else {
                        ranges.append((spoilerRange, spoiler.color))
                    }
                    for range in ranges {
                        let startOffset = CTLineGetOffsetForStringIndex(line.line, range.0.lowerBound, nil);
                        let endOffset = CTLineGetOffsetForStringIndex(line.line, range.0.upperBound, nil);

                        var ascent:CGFloat = 0
                        var descent:CGFloat = 0
                        var leading:CGFloat = 0

                        _ = CGFloat(CTLineGetTypographicBounds(line.line, &ascent, &descent, &leading));

                        var rect:NSRect = line.frame

                        rect.size.width = abs(endOffset - startOffset)
                        rect.origin.x = min(startOffset, endOffset) + line.frame.origin.x
                        rect.origin.y = rect.minY - rect.height + 2
                        rect.size.height += ceil(descent - leading)

                        if line.isRTL {
                            rect.origin.x += layoutSize.width - line.frame.width
                        }

                        rects.append((rect, spoiler))

                    }
                }
            }
        }
        return rects
    }
}
