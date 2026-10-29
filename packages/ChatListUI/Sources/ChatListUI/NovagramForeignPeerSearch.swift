import Cocoa
import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramContext
import TelegramTheme
import TelegramUtils
import ShortPeerRow
import NovagramCore

func novagramForeignPeerSearch(
    _ context: any AccountContextProtocol,
    query: String,
    target: SearchControllerTarget,
    tags: SearchTags,
    options: AppSearchOptions
) -> Signal<[NovagramForeignPeerHit], NoError> {
    guard target.isCommon, options.contains(.chats), tags.isEmpty, !query.hasPrefix("#"), !query.hasPrefix("$") else {
        return .single([])
    }
    let sharedContext = context.sharedContext
    let accountId = context.account.id
    return NovagramCrossAccountSearch.peers(sharedContext: sharedContext, currentAccountId: accountId, query: query)
}

func novagramForeignHits(
    _ hits: [NovagramForeignPeerHit],
    shown: [ChatListSearchEntryStableId]
) -> [NovagramForeignPeerHit] {
    var shownIds = Set<PeerId>()
    for stableId in shown {
        switch stableId {
        case let .localPeerId(peerId), let .globalPeerId(peerId), let .recentSearchPeerId(peerId):
            shownIds.insert(peerId)
        default:
            break
        }
    }
    return hits.filter { !shownIds.contains($0.peer.id) }
}

func novagramForeignSectionTitle() -> String {
    return NovagramL10n.current.search_otherAccounts
}

func novagramForeignPeerRow(
    _ initialSize: NSSize,
    hit: NovagramForeignPeerHit,
    context: any AccountContextProtocol,
    stableId: AnyHashable
) -> TableRowItem {
    let statusStyle = ControlStyle(font: .normal(.text), foregroundColor: theme.colors.grayText, highlightColor: .white)
    return RecentPeerRowItem(
        initialSize,
        peer: hit.peer,
        account: hit.account,
        context: context,
        stableId: stableId,
        statusStyle: statusStyle,
        status: hit.accountPeer.displayTitle,
        borderType: [.Right]
    )
}

private func novagramForeignTarget(_ item: TableRowItem) -> (AccountRecordId, PeerId)? {
    guard let item = item as? ShortPeerRowItem, let stableId = item.stableId.base as? ChatListSearchEntryStableId else {
        return nil
    }
    if case let .novagramForeignPeerId(accountId, peerId) = stableId {
        return (accountId, peerId)
    }
    return nil
}

func novagramIsForeignPeerRow(_ item: TableRowItem) -> Bool {
    return novagramForeignTarget(item) != nil
}

func novagramOpenForeignPeer(_ item: TableRowItem, context: any AccountContextProtocol) -> Bool {
    guard let (accountId, peerId) = novagramForeignTarget(item) else {
        return false
    }
    context.sharedContext.switchToAccount(id: accountId, action: .chat(peerId, necessary: true))
    return true
}
