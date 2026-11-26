import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import AvatarUI
import InputDataUI
import GeneralRows
import TelegramUtils
import TelegramContext
import TelegramTheme
import Localization
import ColorPalette


private final class Arguments {
    public let context: any AccountContextProtocol
    public let selectPeer: (Int) -> Void
    public let confirmSelection: () -> Void

    public init(context: any AccountContextProtocol, selectPeer: @escaping (Int) -> Void, confirmSelection: @escaping () -> Void) {
        self.context = context
        self.selectPeer = selectPeer
        self.confirmSelection = confirmSelection
    }
}


private struct State: Equatable {
    public var peers: [PeerEquatable] = []
    public var selectedIndex: Int = 0

    public var selectedPeer: Peer? {
        guard selectedIndex < peers.count else { return nil }
        return peers[selectedIndex].peer
    }
}


private let _id_peers_row = InputDataIdentifier("_id_peers_row")


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    let sectionId: Int32 = 0
    var index: Int32 = 0

    struct PeersRowTuple: Equatable {
        let peers: [PeerEquatable]
        let selectedIndex: Int
    }

    let tuple = PeersRowTuple(peers: state.peers, selectedIndex: state.selectedIndex)

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_peers_row, equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
        return AltTabPeersRowItem(initialSize, stableId: stableId, context: arguments.context, peers: state.peers.map { $0.peer }, selectedIndex: state.selectedIndex, selectPeer: arguments.selectPeer, confirmSelection: arguments.confirmSelection)
    }))
    index += 1

    return entries
}


private final class AltTabPeerCellView: Control {
    private let avatarView: AvatarControl = AvatarControl(font: .avatar(22))
    private let textView: TextView = TextView()
    private let selectionView: View = View()

    private var selectAction: (() -> Void)?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        avatarView.setFrameSize(50, 50)

        selectionView.layer?.cornerRadius = 12
        selectionView.layer?.borderWidth = 2
        selectionView.layer?.borderColor = theme.colors.accent.cgColor

        addSubview(selectionView)
        addSubview(avatarView)
        addSubview(textView)

        textView.isSelectable = false
        textView.userInteractionEnabled = false

        avatarView.set(handler: { [weak self] _ in
            self?.selectAction?()
        }, for: .Click)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(peer: Peer, context: any AccountContextProtocol, isSelected: Bool, select: @escaping () -> Void) {
        self.selectAction = select

        let photoSize = avatarView.frame.size
        let isSavedMessages = peer.id == context.peerId

        if isSavedMessages {
            let icon = theme.icons.searchSaved
            let photo = generateEmptyPhoto(photoSize, type: .icon(colors: theme.colors.peerColors(5), icon: icon, iconSize: icon.backingSize.aspectFitted(NSMakeSize(photoSize.width - 15, photoSize.height - 15)), cornerRadius: nil), bubble: false) |> map { ($0, false) }
            avatarView.setSignal(photo)
        } else {
            avatarView.setPeer(account: context.account, peer: peer)
        }

        let displayTitle = isSavedMessages ? strings().peerSavedMessages : peer.compactDisplayTitle
        let layout = TextViewLayout(
            .initialize(
                string: displayTitle,
                color: .white,
                font: .normal(11)
            ),
            maximumNumberOfLines: 1,
            truncationType: .middle
        )
        layout.measure(width: frame.width - 18)
        textView.update(layout)

        selectionView.isHidden = !isSelected
        selectionView.layer?.borderColor = theme.colors.accent.cgColor

        needsLayout = true
    }

    public override func layout() {
        super.layout()
        avatarView.centerX(y: 8)
        textView.centerX(y: avatarView.frame.maxY + 4)
        selectionView.frame = NSMakeRect(4, 2, frame.width - 8, frame.height - 4)
    }
}


private final class AltTabPeersRowItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let peers: [Peer]
    fileprivate let selectedIndex: Int
    fileprivate let selectPeer: (Int) -> Void
    fileprivate let confirmSelection: () -> Void
    fileprivate let rowCount: Int

    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, peers: [Peer], selectedIndex: Int, selectPeer: @escaping (Int) -> Void, confirmSelection: @escaping () -> Void) {
        self.context = context
        self.peers = peers
        self.selectedIndex = selectedIndex
        self.selectPeer = selectPeer
        self.confirmSelection = confirmSelection
        self.rowCount = peers.count > 4 ? 2 : 1

        super.init(initialSize, stableId: stableId)
    }

    public override func viewClass() -> AnyClass {
        return AltTabPeersRowView.self
    }

    public override var accessibilityLabel: String? {
        if selectedIndex >= 0 && selectedIndex < peers.count {
            return peers[selectedIndex].displayTitle
        }
        return peers.map { $0.displayTitle }.joined(separator: ", ")
    }

    public override var height: CGFloat {
        let cellHeight: CGFloat = 80
        let padding: CGFloat = 10
        return CGFloat(rowCount) * cellHeight + padding
    }
}


private final class AltTabPeersRowView: GeneralRowView {
    private var cellViews: [AltTabPeerCellView] = []

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var backdorColor: NSColor {
        return .clear
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? AltTabPeersRowItem else { return }

        while cellViews.count < item.peers.count {
            let cell = AltTabPeerCellView(frame: NSMakeRect(0, 0, 80, 80))
            addSubview(cell)
            cellViews.append(cell)
        }

        while cellViews.count > item.peers.count {
            cellViews.last?.removeFromSuperview()
            cellViews.removeLast()
        }

        for (index, peer) in item.peers.enumerated() {
            cellViews[index].update(
                peer: peer,
                context: item.context,
                isSelected: index == item.selectedIndex,
                select: { [weak item] in
                    item?.selectPeer(index)
                    item?.confirmSelection()
                }
            )
        }

        needsLayout = true
    }

    public override func layout() {
        super.layout()

        let cellWidth: CGFloat = 80
        let cellHeight: CGFloat = 80
        let columns = 4

        for (index, cell) in cellViews.enumerated() {
            let col = index % columns
            let row = index / columns
            let x = CGFloat(col) * cellWidth
            let y = 5 + CGFloat(row) * cellHeight
            cell.frame = NSMakeRect(x, y, cellWidth, cellHeight)
        }
    }
}


private final class AltTabModalView: View {
    private let backgroundView: NSVisualEffectView = NSVisualEffectView()
    fileprivate let tableView: TableView = TableView()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        if #available(macOS 10.14, *) {
            backgroundView.material = .hudWindow
        } else {
            backgroundView.material = .sidebar
        }
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 12

        addSubview(backgroundView)
        addSubview(tableView)

        tableView.getBackgroundColor = {
            .clear
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layout() {
        super.layout()
        backgroundView.frame = bounds
        tableView.frame = bounds
    }
}


private func calculateSize(for peerCount: Int) -> NSSize {
    let columns = min(4, peerCount)
    let rows = peerCount > 4 ? 2 : 1
    let width = CGFloat(columns) * 80
    let height = CGFloat(rows) * 80 + 10
    return NSMakeSize(width, height)
}


public final class AltTabSwitcherController: ModalViewController {

    private let context: any AccountContextProtocol
    private let preloadedPeers: [Peer]
    private let actionsDisposable = DisposableSet()
    private var flagsMonitor: Any?

    private let statePromise: ValuePromise<State>
    private let stateValue: Atomic<State>

    private var updateState: ((State) -> State) -> Void {
        return { [weak self] f in
            guard let self = self else { return }
            self.statePromise.set(self.stateValue.modify(f))
        }
    }

    public init(context: any AccountContextProtocol, peers: [Peer]) {
        self.context = context
        self.preloadedPeers = peers

        let initialState = State(
            peers: peers.map { PeerEquatable($0) },
            selectedIndex: min(1, peers.count - 1)
        )
        self.statePromise = ValuePromise(initialState, ignoreRepeated: true)
        self.stateValue = Atomic(value: initialState)

        let size = calculateSize(for: peers.count)
        super.init(frame: NSMakeRect(0, 0, size.width, size.height))
        bar = .init(height: 0)
    }

    deinit {
        actionsDisposable.dispose()
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    public override var background: NSColor {
        return .clear
    }

    public override var containerBackground: NSColor {
        return .clear
    }

    public override var isVisualEffectBackground: Bool {
        return false
    }

    public override var hasBorder: Bool {
        return false
    }

    public override func viewClass() -> AnyClass {
        return AltTabModalView.self
    }

    private var genericView: AltTabModalView {
        return view as! AltTabModalView
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        let updateState = self.updateState

        let arguments = Arguments(
            context: context,
            selectPeer: { index in
                updateState { current in
                    var current = current
                    current.selectedIndex = index
                    return current
                }
            },
            confirmSelection: { [weak self] in
                self?.confirmSelection()
            }
        )

        let previous: Atomic<[AppearanceWrapperEntry<InputDataEntry>]> = Atomic(value: [])
        let initialSize = self.atomicSize

        let signal: Signal<TableUpdateTransition, NoError> = combineLatest(statePromise.get(), appearanceSignal)
            |> mapToSignal { state, appearance -> Signal<TableUpdateTransition, NoError> in
                let entries = entries(state, arguments: arguments).map { AppearanceWrapperEntry(entry: $0, appearance: appearance) }
                return prepareInputDataTransition(left: previous.swap(entries), right: entries, animated: false, searchState: nil, initialSize: initialSize.with { $0 }, arguments: InputDataArguments(select: { _, _ in }, dataUpdated: {}), onMainQueue: true)
            }
            |> deliverOnMainQueue

        actionsDisposable.add(signal.start(next: { [weak self] transition in
            self?.genericView.tableView.merge(with: transition)
            self?.readyOnce()
        }))

        setupFlagsMonitor()
    }

    private func setupFlagsMonitor() {
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return event }

            if !event.modifierFlags.contains(.control) {
                self.confirmSelection()
            }
            return event
        }
    }

    public func selectNext() {
        updateState { current in
            var current = current
            guard !current.peers.isEmpty else { return current }
            current.selectedIndex = (current.selectedIndex + 1) % current.peers.count
            return current
        }
    }

    public func selectPrevious() {
        updateState { current in
            var current = current
            guard !current.peers.isEmpty else { return current }
            current.selectedIndex = (current.selectedIndex - 1 + current.peers.count) % current.peers.count
            return current
        }
    }

    public func confirmSelection() {
        let state = stateValue.with { $0 }
        guard let peer = state.selectedPeer else {
            close()
            return
        }

        QuickSwitcherHooks.shared.navigateToChat(
            context.bindings.rootNavigation(),
            context,
            .peer(peer.id)
        )
        close()
    }

    public override func escapeKeyAction() -> KeyHandlerResult {
        close()
        return .invoked
    }

    public override func returnKeyAction() -> KeyHandlerResult {
        confirmSelection()
        return .invoked
    }
}


public struct AltTabSwitcherData {
    public let peers: [Peer]
    public let isEmpty: Bool

    public init(peers: [Peer]) {
        self.peers = peers
        self.isEmpty = peers.isEmpty
    }
}

public func preloadAltTabSwitcherData(context: any AccountContextProtocol) -> Signal<AltTabSwitcherData, NoError> {
    return context.recentlyUserPeerIds
        |> mapToSignal { [weak context] peerIds -> Signal<AltTabSwitcherData, NoError> in
            let recentPeerIds = Array(peerIds.prefix(8))

            guard !recentPeerIds.isEmpty, let context = context else {
                return .single(AltTabSwitcherData(peers: []))
            }

            return context.account.postbox.multiplePeersView(recentPeerIds)
                |> take(1)
                |> map { view -> AltTabSwitcherData in
                    var orderedPeers: [Peer] = []
                    for peerId in recentPeerIds {
                        if let peer = view.peers[peerId] {
                            if let secretChat = peer as? TelegramSecretChat {
                                if let associatedPeer = view.peers[secretChat.associatedPeerId!] {
                                    orderedPeers.append(associatedPeer)
                                }
                            } else {
                                orderedPeers.append(peer)
                            }
                        }
                    }
                    return AltTabSwitcherData(peers: orderedPeers)
                }
        }
}

public func showAltTabSwitcher(context: any AccountContextProtocol, data: AltTabSwitcherData, window: Window) -> AltTabSwitcherController? {
    guard !data.isEmpty else { return nil }

    let controller = AltTabSwitcherController(context: context, peers: data.peers)
    showModal(with: controller, for: window)
    return controller
}
