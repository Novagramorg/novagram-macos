import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramContext
import GeneralRows
import NovagramCore

struct NovagramSavedSearchRow: Equatable {
    let search: NovagramSavedSearch?
    let index: Int

    var stableKey: String {
        return search?.query ?? ""
    }
}

func novagramSavedSearchRows(_ searches: [NovagramSavedSearch], after index: Int) -> (rows: [NovagramSavedSearchRow], next: Int) {
    guard !searches.isEmpty else {
        return ([], index)
    }
    var rows = [NovagramSavedSearchRow(search: nil, index: index + 1)]
    for (offset, search) in searches.enumerated() {
        rows.append(NovagramSavedSearchRow(search: search, index: index + 2 + offset))
    }
    return (rows, index + 2 + searches.count)
}

func novagramSavedSearchQuery(_ item: TableRowItem) -> String? {
    guard let stableId = item.stableId.base as? ChatListSearchEntryStableId, case let .novagramSavedSearch(query) = stableId, !query.isEmpty else {
        return nil
    }
    return query
}

func novagramSavedSearchRowItem(_ initialSize: NSSize, row: NovagramSavedSearchRow, stableId: AnyHashable, context: any AccountContextProtocol) -> TableRowItem {
    let strings = NovagramL10n.current
    guard let search = row.search else {
        return SeparatorRowItem(initialSize, stableId, string: strings.search_savedTitle.uppercased(), border: [.Right])
    }
    let accountPeerId = context.peerId
    let accountRecordId = context.account.id
    return GeneralInteractedRowItem(initialSize, stableId: stableId, name: search.query, type: search.isPinned ? .context(strings.search_savedPinned) : .none, border: [.Right], menuItems: {
        let pinTitle = search.isPinned ? strings.search_savedUnpin : strings.search_savedPin
        return [
            ContextMenuItem(pinTitle, handler: {
                NovagramSavedSearches.setPinned(search.query, pinned: !search.isPinned, accountPeerId: accountPeerId, accountRecordId: accountRecordId)
            }),
            ContextMenuItem(strings.search_savedRemove, handler: {
                NovagramSavedSearches.remove(search.query, accountPeerId: accountPeerId, accountRecordId: accountRecordId)
            })
        ]
    })
}
