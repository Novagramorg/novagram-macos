import Cocoa
import TGUIKit

public final class FoldingTextLayout {
    public var blocks: [ViewLayout]
    public let appendingAnimation: Bool
    public let attributedString: NSAttributedString
    public let blockRanges: [NSRange]
    public init(blocks: [ViewLayout], appendingAnimation: Bool = false, attributedString: NSAttributedString? = nil, blockRanges: [NSRange]? = nil) {
        self.blocks = blocks
        self.appendingAnimation = appendingAnimation
        let combined = NSMutableAttributedString(string: "")
        var ranges: [NSRange] = []
        for block in blocks {
            ranges.append(NSRange(location: combined.length, length: block.text.attributedString.length))
            combined.append(block.text.attributedString)
        }
        self.attributedString = attributedString ?? (combined.copy() as! NSAttributedString)
        self.blockRanges = blockRanges ?? ranges
    }
}

extension FoldingTextLayout.ViewLayout {
    public func measured(width: CGFloat, revealed: Bool) -> Self {
        return updated(width: width, revealed: revealed, collapsable: text.blockCollapsable, isBigEmoji: false)
    }

    public init(text: TextViewLayout, isRevealed: Bool = true, size: NSSize? = nil) {
        self.init(text: text, arrowDown: nil, arrowUp: nil, mask: nil, isRevealed: isRevealed, collapsable: text.blockCollapsable, size: size ?? text.layoutSize)
    }
}
