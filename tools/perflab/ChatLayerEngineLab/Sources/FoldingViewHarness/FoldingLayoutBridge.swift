import Cocoa
import TGUIKit
@testable import InputTextView
@testable import ChatLayerEngine

extension ChatLayerMessageTextPresentation.Folding {
    convenience init(_ layout: FoldingTextLayout.ViewLayout) {
        self.init(InputTextView.FoldingTextLayout.ViewLayout(text: layout.text, arrowDown: layout.arrowDown, arrowUp: layout.arrowUp, mask: layout.mask, isRevealed: layout.isRevealed, collapsable: layout.collapsable, size: layout.size))
    }
}
