// Chat list paging: ChatListController drops a page request that comes within 0.5 s of the previous one.
// When the list already shows its last loaded row no new scroll event follows, so the next page was never
// requested (fast scroll in a big folder). This asks again once the guard has expired, while still at the edge.

import Foundation
import TGUIKit
import SwiftSignalKit

final class FenixuzChatListPageRetry {
    private let disposable = MetaDisposable()

    /// The chat list scroll handler, called again for the dropped request.
    var handler: ((ScrollPosition) -> Void)?

    func schedule(_ scroll: ScrollPosition, after delay: Double, tableView: TableView) {
        disposable.set(delaySignal(max(delay, 0) + 0.05).start(completed: { [weak self, weak tableView] in
            guard let self = self, let tableView = tableView else {
                return
            }
            if Self.isAtEdge(tableView, direction: scroll.direction) {
                self.handler?(scroll)
            }
        }))
    }

    func cancel() {
        disposable.set(nil)
    }

    // same edge test TableView uses before it calls the scroll handler
    private static func isAtEdge(_ tableView: TableView, direction: ScrollDirection) -> Bool {
        let range = tableView.visibleRows()
        if range.location == NSNotFound {
            return false
        }
        let reqCount = tableView.count / 6
        switch direction {
        case .bottom:
            return tableView.count - (range.location + range.length) <= reqCount
        case .top:
            return range.location <= reqCount
        case .none:
            return false
        }
    }

    deinit {
        disposable.dispose()
    }
}
