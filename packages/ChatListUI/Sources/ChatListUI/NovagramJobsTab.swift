import Cocoa
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramContext
import NovagramCore

private let novagramJobsTabUniqueId: Int64 = -1_000_001

private final class NovagramJobsTabBinding {
    weak var view: ScrollableSegmentView?
    let accountPeerId: PeerId
    var baseItems: [ScrollableSegmentItem] = []
    var insets: NSEdgeInsets
    var theme: ScrollableSegmentTheme
    var isGlobal: Bool = false
    var enabled: Bool = NovagramJobSearchAvailability.isEnabled
    var unseen: Int = 0
    let disposable = MetaDisposable()

    init(view: ScrollableSegmentView, accountPeerId: PeerId, insets: NSEdgeInsets, theme: ScrollableSegmentTheme) {
        self.view = view
        self.accountPeerId = accountPeerId
        self.insets = insets
        self.theme = theme
    }

    deinit {
        disposable.dispose()
    }

    var tabItem: ScrollableSegmentItem? {
        guard isGlobal, enabled else {
            return nil
        }
        let name = NovagramL10n.current.jobSearch_tab
        let title = unseen > 0 ? "\(name) \(unseen)" : name
        return ScrollableSegmentItem(title: title, index: baseItems.count, uniqueId: novagramJobsTabUniqueId, selected: false, insets: insets, icon: nil, theme: theme, equatable: UIEquatable(title))
    }

    var items: [ScrollableSegmentItem] {
        return baseItems + (tabItem.map { [$0] } ?? [])
    }
}

private var novagramJobsTabBindings: [ObjectIdentifier: NovagramJobsTabBinding] = [:]

func novagramJobsTabItems(_ items: [ScrollableSegmentItem], state: PeerListState, context: (any AccountContextProtocol)?, view: ScrollableSegmentView, insets: NSEdgeInsets, theme: ScrollableSegmentTheme) -> [ScrollableSegmentItem] {
    guard let context else {
        return items
    }
    novagramJobsTabBindings = novagramJobsTabBindings.filter { $0.value.view != nil }
    let key = ObjectIdentifier(view)
    let existing = novagramJobsTabBindings[key].flatMap { $0.accountPeerId == context.peerId ? $0 : nil }
    let binding = existing ?? NovagramJobsTabBinding(view: view, accountPeerId: context.peerId, insets: insets, theme: theme)
    binding.baseItems = items
    binding.insets = insets
    binding.theme = theme
    binding.isGlobal = state.peerTag == nil && state.forumPeer == nil && !state.mode.isForumLike && !state.mode.isCommunity
    if existing == nil {
        novagramJobsTabBindings[key] = binding
        let signal = combineLatest(NovagramJobSearchAvailability.signal(), NovagramHooks.shared.jobSearchUnseenCount(context)) |> deliverOnMainQueue
        binding.disposable.set(signal.start(next: { [weak binding] enabled, unseen in
            guard let binding, binding.enabled != enabled || binding.unseen != unseen else {
                return
            }
            binding.enabled = enabled
            binding.unseen = unseen
            binding.view?.updateItems(binding.items, animated: false, autoscroll: false)
        }))
    }
    return binding.items
}

func novagramJobsTabDidSelect(_ item: ScrollableSegmentItem, context: (any AccountContextProtocol)?) -> Bool {
    guard item.uniqueId == novagramJobsTabUniqueId else {
        return false
    }
    if let context, NovagramJobSearchAvailability.isEnabled {
        NovagramHooks.shared.openJobSearch(context, nil)
    }
    return true
}
