import Foundation
import TGUIKit
import TelegramTheme
import ColorPalette

extension GeneralContainableRowView {
    public func updateHighlightColors() {
        guard let item = item as? GeneralRowItem else {
            return
        }
        self.background = item.viewType.rowBackground
        let highlighted = isSelect ? self.backdorColor : theme.colors.grayHighlight
        containerView.set(background: self.backdorColor, for: .Normal)
        containerView.set(background: highlighted, for: .Highlight)
    }
}
