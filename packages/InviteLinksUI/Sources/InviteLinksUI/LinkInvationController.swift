import Cocoa

import Foundation
import TGUIKit
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import GeneralRows
import InputDataUI
import AlertsUI
import AvatarUI
import ShortPeerRow
import LocalAnimations
import InAppSettings
import ColorPalette
import DateUtils
import TelegramIconsTheme
import InputView
import InputTextView
import SwiftSignalKit
import Postbox
import TelegramCore

private enum GroupLinkInvationEntryStableId : Hashable {
    case section(Int)
    case index(Int)
    case loading
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case let .section(id):
            hasher.combine(id)
        case let .index(id):
            hasher.combine(id)
        case .loading:
            hasher.combine(1000000)
        }
    }
}

private enum GroupLinkInvationEntry : Identifiable, Comparable {
    case section(sectionId:Int)
    case text(sectionId:Int, uniqueIdx:Int, text:String)
    case link(sectionId:Int, uniqueIdx:Int, text:String)
    case action(sectionId:Int, uniqueIdx:Int, text:String, callback:()->Void)
    case loading
    
    var stableId:GroupLinkInvationEntryStableId {
        switch self {
        case let .section(id):
            return .section(id)
        case let .text(_, uniqueIdx, _):
            return .index(uniqueIdx)
        case let .link(_, uniqueIdx, _):
            return .index(uniqueIdx)
        case let .action(_, uniqueIdx, _, _):
            return .index(uniqueIdx)
        case .loading:
            return .loading
        }
    }
    
    var index:Int {
        switch self {
        case let .section(sectionId):
            return (sectionId + 1) * 1000 - sectionId
        case let .text(sectionId, uniqueIdx, _):
            return (sectionId * 1000) + uniqueIdx
        case let .link(sectionId, uniqueIdx, _):
            return (sectionId * 1000) + uniqueIdx
        case let .action(sectionId, uniqueIdx, _, _):
            return (sectionId * 1000) + uniqueIdx
        case .loading:
            return 0
        }
    }
}

private func ==(lhs:GroupLinkInvationEntry, rhs:GroupLinkInvationEntry) -> Bool {
    switch lhs {
    case let .text(_, lhsUniqueIdx, lhsText):
        if case let .text(_, rhsUniqueIdx, rhsText) = rhs {
            if lhsUniqueIdx != rhsUniqueIdx {
                return false
            }
            if lhsText != rhsText {
                return false
            }
            return true
        }
        return false
    case let .action(_, lhsUniqueIdx, lhsText, _):
        if case let .action(_, rhsUniqueIdx, rhsText, _) = rhs {
            if lhsUniqueIdx != rhsUniqueIdx {
                return false
            }
            if lhsText != rhsText {
                return false
            }
            return true
        }
        return false
    case let .link(_, lhsUniqueIdx, lhsText):
        if case let .link(_, rhsUniqueIdx, rhsText) = rhs {
            if lhsUniqueIdx != rhsUniqueIdx {
                return false
            }
            if lhsText != rhsText {
                return false
            }
            return true
        }
        return false
    default:
        return lhs.stableId == rhs.stableId
    }
}

private func <(lhs:GroupLinkInvationEntry, rhs:GroupLinkInvationEntry) -> Bool {
    return lhs.index < rhs.index
}

final class GroupLinkInvationArguments {
    let context: any AccountContextProtocol
    let copy:()->Void
    let share:()->Void
    let revoke:()->Void
    
    init(context: any AccountContextProtocol, copy:@escaping()->Void, share:@escaping()->Void, revoke:@escaping()->Void) {
        self.context = context
        self.copy = copy
        self.share = share
        self.revoke = revoke
    }
}

private func groupInvationEntries(view:PeerView, arguments:GroupLinkInvationArguments) -> [GroupLinkInvationEntry] {
    
    let isGroup:Bool
    if let peer = peerViewMainPeer(view) {
        isGroup = !peer.isChannel
    } else {
        isGroup = true
    }
    
    let exportLink:String?
    if let cachedData = view.cachedData as? CachedChannelData {
        exportLink = cachedData.exportedInvitation?.link
    } else if let cachedData = view.cachedData as? CachedGroupData {
        exportLink = cachedData.exportedInvitation?.link
    } else {
        exportLink = nil
    }
    
    if let link = exportLink {
        var entries:[GroupLinkInvationEntry] = []
        var sectionId:Int = 0
        
        entries.append(.section(sectionId: sectionId))
        sectionId += 1
        
        var uniqueId:Int = 1
        
        entries.append(.link(sectionId: sectionId, uniqueIdx: uniqueId, text: link))
        uniqueId += 1
        entries.append(.text(sectionId: sectionId, uniqueIdx: uniqueId, text: isGroup ? strings().groupInvationGroupDescription : strings().groupInvationChannelDescription))
        uniqueId += 1
        
        entries.append(.section(sectionId: sectionId))
        sectionId += 1
        
        entries.append(.action(sectionId: sectionId, uniqueIdx: uniqueId, text: strings().groupInvationCopyLink, callback: {
            arguments.copy()
        }))
        uniqueId += 1
        entries.append(.action(sectionId: sectionId, uniqueIdx: uniqueId, text: strings().groupInvationRevoke, callback: {
            arguments.revoke()
        }))
        uniqueId += 1
        entries.append(.action(sectionId: sectionId, uniqueIdx: uniqueId, text: strings().groupInvationShare, callback: {
            arguments.share()
        }))
        uniqueId += 1
        
        return entries
    } else {
        return [.loading]
    }
}

private func prepareEntries(left:[GroupLinkInvationEntry], right: [GroupLinkInvationEntry], initialSize:NSSize) -> TableUpdateTransition {
    
    let (removed, inserted, updated) = proccessEntriesWithoutReverse(left, right: right) { entry -> TableRowItem in
        switch entry {
        case .section:
            return GeneralRowItem(initialSize, height: 20, stableId: entry.stableId)
        case let .text(sectionId: _, uniqueIdx: _, text: text):
            return GeneralTextRowItem(initialSize, stableId: entry.stableId, text: text)
        case let .action(sectionId: _, uniqueIdx: _, text: text, callback: action):
            return GeneralInteractedRowItem(initialSize, stableId: entry.stableId, name: text, nameStyle: blueActionButton, type: .none, action: action)
        case let .link(sectionId: _, uniqueIdx: _, text: text):
            return GeneralInteractedRowItem(initialSize, stableId: entry.stableId, name: text, type: .none)
        case .loading:
            return SearchEmptyRowItem(initialSize, stableId: entry.stableId, isLoading: true)
        }
    }
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: true)
    
}

open class LinkInvationController<Context: AccountContextProtocol>: TableViewController<Context> {

    private let peerId:PeerId
    
    private let revokeLinkDisposable = MetaDisposable()
    private let disposable:MetaDisposable = MetaDisposable()
    
    public init(_ context: Context, peerId:PeerId) {
        self.peerId = peerId
        super.init(context)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        let context = self.context
        let peerId = self.peerId
        
        let link:Atomic<String?> = Atomic(value: nil)
        let peer:Atomic<Peer?> = Atomic(value: nil)

        
        let arguments = GroupLinkInvationArguments(context: context, copy: {
            if let link = link.modify({$0}) {
                copyToClipboard(link)
                showModalText(for: context.window, text: strings().shareLinkCopied)
            }
        }, share: {
            if let link = link.modify({$0}) {
                InviteLinksHooks.shared.shareLink(context, link, context.window)
            }
        }, revoke: { [weak self] in
            if let peer = peer.modify({$0}), let context = self?.context {
                let info = peer.isChannel ? strings().linkInvationChannelConfirmRevoke : strings().linkInvationGroupConfirmRevoke
                let signal = verifyAlertSignal(for: context.window, information: info, ok: strings().linkInvationConfirmOk)
                |> filter { $0 == .basic }
                    |> mapToSignal { _ -> Signal<Void, NoError> in
                        
                        return context.engine.peers.revokePersistentPeerExportedInvitation(peerId: peer.id) |> map { _ in return }
                    }
                self?.revokeLinkDisposable.set(signal.start())
            }
        })
        
        let previous:Atomic<[GroupLinkInvationEntry]> = Atomic(value: [])
        let atomicSize = self.atomicSize
        let apply = context.account.viewTracker.peerView( peerId) |> deliverOn(prepareQueue) |> map { view -> TableUpdateTransition in
            
            let exportLink:String?
            if let cachedData = view.cachedData as? CachedChannelData {
                exportLink = cachedData.exportedInvitation?.link
            } else if let cachedData = view.cachedData as? CachedGroupData {
                exportLink = cachedData.exportedInvitation?.link
            } else {
                exportLink = nil
            }
            _ = link.swap(exportLink)
            _ = peer.swap(peerViewMainPeer(view))
            
            let entries = groupInvationEntries(view: view, arguments: arguments)
            return prepareEntries(left: previous.swap(entries), right: entries, initialSize: atomicSize.modify {$0})
        } |> deliverOnMainQueue
        
        
        disposable.set(apply.start(next: { [weak self] transition in
            self?.genericView.merge(with: transition)
            self?.readyOnce()
        }))
    }
    
    deinit {
        disposable.dispose()
        revokeLinkDisposable.dispose()
    }
    
}
