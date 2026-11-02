import Cocoa
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramContext
import NovagramCore

private let novagramSuperSearchTabUniqueId: Int64 = -1_000_001

private final class NovagramSuperSearchTabBinding {
    weak var view: ScrollableSegmentView?
    let accountPeerId: PeerId
    var baseItems: [ScrollableSegmentItem] = []
    var insets: NSEdgeInsets
    var theme: ScrollableSegmentTheme
    var isGlobal: Bool = false
    var enabled: Bool = NovagramSuperSearchAvailability.isEnabled
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
        let title = NovagramL10n.current.superSearch_tab
        return ScrollableSegmentItem(title: title, index: baseItems.count, uniqueId: novagramSuperSearchTabUniqueId, selected: false, insets: insets, icon: nil, theme: theme, equatable: UIEquatable(title))
    }

    var items: [ScrollableSegmentItem] {
        return baseItems + (tabItem.map { [$0] } ?? [])
    }
}

private var novagramSuperSearchTabBindings: [ObjectIdentifier: NovagramSuperSearchTabBinding] = [:]

func novagramSuperSearchTabItems(_ items: [ScrollableSegmentItem], state: PeerListState, context: (any AccountContextProtocol)?, view: ScrollableSegmentView, insets: NSEdgeInsets, theme: ScrollableSegmentTheme) -> [ScrollableSegmentItem] {
    guard let context else {
        return items
    }
    novagramSuperSearchTabBindings = novagramSuperSearchTabBindings.filter { $0.value.view != nil }
    let key = ObjectIdentifier(view)
    let existing = novagramSuperSearchTabBindings[key].flatMap { $0.accountPeerId == context.peerId ? $0 : nil }
    let binding = existing ?? NovagramSuperSearchTabBinding(view: view, accountPeerId: context.peerId, insets: insets, theme: theme)
    binding.baseItems = items
    binding.insets = insets
    binding.theme = theme
    binding.isGlobal = state.peerTag == nil && state.forumPeer == nil && !state.mode.isForumLike && !state.mode.isCommunity
    if existing == nil {
        novagramSuperSearchTabBindings[key] = binding
        binding.disposable.set((NovagramSuperSearchAvailability.signal() |> deliverOnMainQueue).start(next: { [weak binding] enabled in
            guard let binding, binding.enabled != enabled else {
                return
            }
            binding.enabled = enabled
            binding.view?.updateItems(binding.items, animated: false, autoscroll: false)
        }))
    }
    return binding.items
}

func novagramSuperSearchTabDidSelect(_ item: ScrollableSegmentItem, context: (any AccountContextProtocol)?) -> Bool {
    guard item.uniqueId == novagramSuperSearchTabUniqueId else {
        return false
    }
    if let context, NovagramSuperSearchAvailability.isEnabled {
        NovagramHooks.shared.openSuperSearch(context)
    }
    return true
}
