import Cocoa
import InstantPageUI

extension ChatUnsupportedPapercutLayout: InstantPageV2UnsupportedBandLayout {

}

extension ChatUnsupportedPapercutStyle: InstantPageV2UnsupportedBandStyle {
    public func makeBandLayout(title: String, subtitle: String, action: String) -> any InstantPageV2UnsupportedBandLayout {
        return ChatUnsupportedPapercutLayout(title: title, subtitle: subtitle, action: action, style: self)
    }
}
