import Cocoa
import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramContext
import TelegramTheme
import NovagramCore

private let novagramOtherAccountsSeparatorIndex = 5000
private let novagramReturnKeyCode: UInt16 = 36
private let novagramEnterKeyCode: UInt16 = 76

func novagramIsOpenGesture() -> Bool {
    guard let event = NSApp.currentEvent else {
        return false
    }
    switch event.type {
    case .leftMouseDown, .leftMouseUp:
        return true
    case .keyDown:
        return event.keyCode == novagramReturnKeyCode || event.keyCode == novagramEnterKeyCode
    default:
        return false
    }
}

func novagramOtherAccountsSearch(
    _ context: any AccountContextProtocol,
    query: String,
    target: SearchControllerTarget,
    tags: SearchTags,
    options: AppSearchOptions
) -> Signal<[NovagramForeignPeerHit], NoError> {
    guard target.isCommon, options.contains(.chats), tags.isEmpty, !query.hasPrefix("#"), !query.hasPrefix("$") else {
        return NovagramCrossAccountSearch.empty(currentAccountId: context.account.id)
    }
    return NovagramCrossAccountSearch.peers(
        sharedContext: context.sharedContext,
        currentAccountId: context.account.id,
        query: query
    )
}

private func novagramOtherAccountsHits(
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
    var seen = Set<ChatListSearchEntryStableId>()
    return hits.filter { hit in
        guard !shownIds.contains(hit.peer.id) else {
            return false
        }
        return seen.insert(.novagramForeignPeerId(hit.accountId, hit.peer.id)).inserted
    }
}

func novagramOtherAccountsEntries<Entry>(
    _ hits: [NovagramForeignPeerHit],
    shown: [ChatListSearchEntryStableId],
    separator: (String, Int) -> Entry,
    row: (NovagramForeignPeerHit, Int) -> Entry
) -> [Entry] {
    let kept = novagramOtherAccountsHits(hits, shown: shown)
    guard !kept.isEmpty else {
        return []
    }
    let start = novagramOtherAccountsSeparatorIndex
    var entries = [separator(NovagramL10n.current.search_otherAccounts, start)]
    entries += kept.enumerated().map { row($0.element, start + 1 + $0.offset) }
    return entries
}

func novagramOtherAccountsRow(
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

private func novagramOtherAccountsTarget(_ item: TableRowItem) -> (AccountRecordId, PeerId)? {
    guard let stableId = item.stableId.base as? ChatListSearchEntryStableId else {
        return nil
    }
    if case let .novagramForeignPeerId(accountId, peerId) = stableId {
        return (accountId, peerId)
    }
    return nil
}

func novagramIsOtherAccountsRow(_ item: TableRowItem) -> Bool {
    return novagramOtherAccountsTarget(item) != nil
}

func novagramOpenOtherAccountsRow(_ item: TableRowItem, context: any AccountContextProtocol) -> Bool {
    guard let (accountId, peerId) = novagramOtherAccountsTarget(item) else {
        return false
    }
    if novagramIsOpenGesture() {
        context.sharedContext.switchToAccount(id: accountId, action: .chat(peerId, necessary: true))
    }
    return true
}
