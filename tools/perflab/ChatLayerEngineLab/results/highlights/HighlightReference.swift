import Cocoa
import TGUIKit

public final class NativeMessageHighlightHarness {
    let layouts: FoldingTextLayout?
    let textViews: [TextView]
    public init(layouts: FoldingTextLayout, textViews: [TextView]) { self.layouts = layouts; self.textViews = textViews }
    public func highlight(text: String, color: NSColor, range: NSRange? = nil) {
        if let layouts, let range, range.location >= 0, range.location != NSNotFound, range.length >= 0, range.location <= layouts.attributedString.length, range.length <= layouts.attributedString.length - range.location, layouts.attributedString.string.nsstring.substring(with: range) == text {
            var highlighted = false
            for (textView, (block, blockRange)) in zip(textViews, zip(layouts.blocks, layouts.blockRanges)) {
                if let intersection = blockRange.intersection(range) {
                    let localRange = NSRange(location: intersection.location - blockRange.location, length: intersection.length)
                    let localText = block.text.attributedString.string.nsstring.substring(with: localRange)
                    textView.highlight(text: localText, color: color, range: localRange)
                    highlighted = true
                }
            }
            if highlighted {
                return
            }
        }
        for textView in textViews {
            textView.highlight(text: text, color: color)
        }
    }
}
