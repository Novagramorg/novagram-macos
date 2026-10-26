import Cocoa
import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramContext
import TelegramTheme
import FenixuzCore

// Novagram ads v2: our promoted channel row in the global search (SearchController `.novagramAdPeer`).
func fenixuzSearchAdRow(_ initialSize: NSSize, peer: Peer, token: String, context: any AccountContextProtocol, stableId: AnyHashable, contextMenuItems: @escaping () -> Signal<[ContextMenuItem], NoError>) -> TableRowItem {
    let status = peer.addressName.flatMap { "@\($0)" }
    let statusStyle = ControlStyle(font: .normal(.text), foregroundColor: theme.colors.grayText, highlightColor: .white)
    return RecentPeerRowItem(initialSize, peer: peer, account: context.account, context: context, stableId: stableId, statusStyle: statusStyle, status: status, borderType: [.Right], contextMenuItems: contextMenuItems, novagramAdToken: token)
}

// Same "Ad" pill as Telegram's sponsored peer, with our label, our About / Report menu and our view event.
func fenixuzConfigureSearchAd(_ view: RecentPeerRowView.AdView, token: String, window: Window) {
    if let label = NovagramAdsHooks.shared.searchAdLabel(), let textView = view.subviews.compactMap({ $0 as? TextView }).first {
        let layout = TextViewLayout(.initialize(string: label, color: theme.colors.accent, font: .normal(.small)))
        layout.measure(width: .greatestFiniteMagnitude)
        textView.update(layout)
        let imageWidth = view.subviews.compactMap({ $0 as? ImageView }).first?.frame.width ?? 0
        view.setFrameSize(NSSize(width: textView.frame.width + 8 + imageWidth, height: 16))
        view.setAccessibilityLabel(label)
        view.needsLayout = true
    }
    view.contextMenu = {
        return NovagramAdsHooks.shared.searchAdMenu(token, window)
    }
    NovagramAdsHooks.shared.searchRecordView(token)
}
