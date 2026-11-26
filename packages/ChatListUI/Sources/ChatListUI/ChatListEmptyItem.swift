import Foundation
import TGUIKit
import Cocoa
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import StoriesUI

public final class ChatListSpaceItem : GeneralRowItem {
    public let getInterfaceState:()-> StoryListChatListRowItem.InterfaceState
    public let getState:()->PeerListState
    public let getDeltaProgress:()->CGFloat?
    public let getNavigationHeight: ()->CGFloat
    public init(_ initialSize: NSSize, stableId: AnyHashable, getState:@escaping()->PeerListState, getDeltaProgress:@escaping()->CGFloat?, getInterfaceState:@escaping()->StoryListChatListRowItem.InterfaceState, getNavigationHeight: @escaping()->CGFloat) {
        self.getInterfaceState = getInterfaceState
        self.getState = getState
        self.getDeltaProgress = getDeltaProgress
        self.getNavigationHeight = getNavigationHeight
        super.init(initialSize, stableId: stableId)
    }
    
    public override var canBeAnchor: Bool {
        return false
    }
    
    public override var height: CGFloat {
        guard let _ = self.table else {
            return 1
        }
        return self.getNavigationHeight()
    }
    public override func viewClass() -> AnyClass {
        return ChatListSpaceItemView.self
    }
    
    public override var accessibilityIsSpacer: Bool {
        return true
    }
}

private final class ChatListSpaceItemView : TableRowView {
    
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
    }
    
    override var backdorColor: NSColor {
        return .clear
    }

    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        

    }
}
