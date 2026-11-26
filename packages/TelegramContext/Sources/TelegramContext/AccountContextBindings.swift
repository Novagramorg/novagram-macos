import Foundation
import Postbox
import TelegramCore
import TGUIKit

public struct CachedSearchMessages : Equatable {
    public var result: SearchMessagesResult
    public var state: SearchMessagesState
    public init(result: SearchMessagesResult, state: SearchMessagesState) {
        self.result = result
        self.state = state
    }
}

public final class AccountContextBindings {
    #if !SHARE
    public let rootNavigation: () -> MajorNavigationController
    public let mainController: () -> ViewController
    public let globalSearch:(String, PeerId?, CachedSearchMessages?)->Void
    public let switchSplitLayout:(SplitViewState)->Void
    public let entertainment:()->ViewController
    public let needFullsize:()->Void
    public let displayUpgradeProgress:(CGFloat)->Void
    public var setGlobalBackgroundMode: (TableBackgroundMode?) -> Void = { _ in }
    public var doGlobalBackgroundAction: () -> Void = { }
    public init(rootNavigation: @escaping() -> MajorNavigationController = { fatalError() }, mainController: @escaping() -> ViewController = { fatalError() }, globalSearch: @escaping(String, PeerId?, CachedSearchMessages?) -> Void = { _, _, _ in fatalError() }, entertainment: @escaping()->ViewController = { fatalError() }, switchSplitLayout: @escaping(SplitViewState)->Void = { _ in fatalError() }, needFullsize: @escaping() -> Void = { fatalError() }, displayUpgradeProgress: @escaping(CGFloat)->Void = { _ in fatalError() }) {
        self.rootNavigation = rootNavigation
        self.mainController = mainController
        self.globalSearch = globalSearch
        self.entertainment = entertainment
        self.switchSplitLayout = switchSplitLayout
        self.needFullsize = needFullsize
        self.displayUpgradeProgress = displayUpgradeProgress
    }
    #else
    public init() {}
    #endif
}
