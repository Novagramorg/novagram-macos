import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import TelegramTheme
import SceneEffects

@available(macOS 10.15, *)
public struct ChatWalletTransferFlightSource {
    public let diamond: InteractiveDiamondView
    public let window: NSWindow
    public let center: NSPoint
    public let width: CGFloat

    public init(diamond: InteractiveDiamondView, window: NSWindow, center: NSPoint, width: CGFloat) {
        self.diamond = diamond
        self.window = window
        self.center = center
        self.width = width
    }
}

@available(macOS 10.15, *)
public struct ChatWalletSendHandlers {
    public let transferAnimationWillStart: ((String) -> Void)?
    public let transferAnimation: ((String, ChatWalletTransferFlightSource?) -> Bool)?
    public let completed: () -> Void

    init(transferAnimationWillStart: ((String) -> Void)?, transferAnimation: ((String, ChatWalletTransferFlightSource?) -> Bool)?, completed: @escaping () -> Void) {
        self.transferAnimationWillStart = transferAnimationWillStart
        self.transferAnimation = transferAnimation
        self.completed = completed
    }
}

@available(macOS 10.15, *)
final class ChatWalletTransferAnimation {
    enum ArrivalState {
        case queued(rise: Bool)
        case playing(startTime: CFTimeInterval, rise: Bool)
        case finished
    }

    private final class Arrival {
        let id: MessageId
        let index: MessageIndex
        let rise: Bool
        var startTime: CFTimeInterval?
        weak var target: ChatWalletTransferView?

        init(id: MessageId, index: MessageIndex, rise: Bool) {
            self.id = id
            self.index = index
            self.rise = rise
        }
    }

    private final class Flight {
        let id: String
        let operationId: String
        var source: ChatWalletTransferFlightSource?
        var overlay: View?
        var createdAt: CFTimeInterval
        var startedAt: CFTimeInterval?
        var stableId: UInt32?
        var transactionHash: Data?
        weak var target: ChatWalletTransferView?

        init(id: String) {
            self.id = id
            self.operationId = String(id.dropFirst("pending:".count))
            self.createdAt = CACurrentMediaTime()
        }

        func launch(source: ChatWalletTransferFlightSource) {
            guard let contentView = source.window.contentView else {
                return
            }
            self.source = source
            self.createdAt = CACurrentMediaTime()
            let overlay = View(frame: contentView.bounds)
            overlay.userInteractionEnabled = false
            overlay.autoresizingMask = [.width, .height]
            overlay.layer?.masksToBounds = false
            contentView.addSubview(overlay)
            overlay.addSubview(source.diamond)
            let center = overlay.convert(source.center, from: nil)
            source.diamond.setFrameOrigin(NSMakePoint(center.x - source.diamond.frame.width / 2, center.y - source.diamond.frame.height / 2))
            source.diamond.isRenderingEnabled = true
            self.overlay = overlay
        }

        func matches(_ view: ChatWalletTransferView) -> Bool {
            guard !view.isIncomingTransfer else {
                return false
            }
            let matches = view.transferOperationId == self.operationId
                || (self.stableId != nil && view.messageStableId == self.stableId)
                || (self.transactionHash != nil && view.transferTransactionHash == self.transactionHash)
            if matches {
                self.stableId = view.messageStableId
            }
            return matches
        }
    }

    private weak var chatInteraction: ChatInteraction?
    private weak var tableView: TableView?
    private var flights: [String: Flight] = [:]
    private var endedFlights = Set<String>()
    private var arrivals: [MessageId: Arrival] = [:]
    private var seenArrivals = Set<MessageId>()
    private var openReadStates: [PeerId: CombinedPeerReadState]?
    private var lastArrivalStartTime: CFTimeInterval?
    private let openTimestamp: Int32
    private var link: SharedDisplayLinkDriver.Link?
    private var scrollListener: TableScrollListener?
    private var activityObservers: [NSObjectProtocol] = []

    init(chatInteraction: ChatInteraction, tableView: TableView) {
        self.chatInteraction = chatInteraction
        self.tableView = tableView
        self.openTimestamp = Int32(Date().timeIntervalSince1970 + chatInteraction.context.timeDifference)
        let scrollListener = TableScrollListener(dispatchWhenVisibleRangeUpdated: true, { [weak self] _ in
            self?.updateVisibleIncomingTransfers()
        })
        self.scrollListener = scrollListener
        tableView.addScroll(listener: scrollListener)
        let center = NotificationCenter.default
        self.activityObservers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: nil, using: { [weak self] notification in
                guard let self, let window = self.tableView?.window, notification.object as? NSWindow === window else {
                    return
                }
                self.updateVisibleIncomingTransfers()
            }),
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil, using: { [weak self] _ in
                self?.updateVisibleIncomingTransfers()
            })
        ]
    }

    deinit {
        if let scrollListener = self.scrollListener {
            self.tableView?.removeScroll(listener: scrollListener)
        }
        for observer in self.activityObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        self.link?.invalidate()
        for flight in self.flights.values {
            flight.source?.diamond.isRenderingEnabled = false
            flight.overlay?.removeFromSuperview()
        }
        for arrival in self.arrivals.values {
            arrival.target?.finishIncomingTransferAnimation()
        }
    }

    func arrivalState(_ id: MessageId) -> ArrivalState? {
        if let arrival = self.arrivals[id] {
            if let startTime = arrival.startTime {
                return .playing(startTime: startTime, rise: arrival.rise)
            }
            return .queued(rise: arrival.rise)
        }
        return self.seenArrivals.contains(id) ? .finished : nil
    }

    func updateOpenReadStates(_ readStates: MessageHistoryViewReadState?) {
        guard self.openReadStates == nil, case let .peer(states)? = readStates else {
            return
        }
        self.openReadStates = states
    }

    func arrivalRise(_ message: Message) -> Bool? {
        guard self.chatInteraction?.mode != .preview else {
            return nil
        }
        let rise = message.timestamp >= self.openTimestamp
        let isUnread = self.openReadStates?[message.id.peerId].map { !$0.isIncomingMessageIndexRead(message.index) } ?? false
        guard !self.seenArrivals.contains(message.id), message.flags.contains(.Incoming), isUnread || rise else {
            return nil
        }
        return rise
    }

    func requestArrival(_ message: Message) {
        guard let rise = self.arrivalRise(message) else {
            return
        }
        self.seenArrivals.insert(message.id)
        guard !self.reduceMotion else {
            return
        }
        self.arrivals[message.id] = Arrival(id: message.id, index: message.index, rise: rise)
        self.ensureLink()
    }

    func cancelArrival(_ id: MessageId) {
        guard let arrival = self.arrivals.removeValue(forKey: id) else {
            return
        }
        arrival.target?.finishIncomingTransferAnimation()
        for view in self.transferViews() where view.messageId == id && view !== arrival.target {
            view.finishIncomingTransferAnimation()
        }
        if self.arrivals.isEmpty {
            self.lastArrivalStartTime = nil
        }
        self.stopLinkIfIdle()
    }

    private func updateArrivals(at now: CFTimeInterval, views: [ChatWalletTransferView]) {
        for arrival in self.arrivals.values.sorted(by: { $0.index < $1.index }) {
            let id = arrival.id
            guard !self.reduceMotion, let view = views.first(where: { $0.messageId == id && $0.canPlayIncomingTransferAnimation }) else {
                self.cancelArrival(id)
                continue
            }
            if let previous = arrival.target, previous !== view {
                previous.finishIncomingTransferAnimation()
            }
            arrival.target = view
            if arrival.startTime == nil {
                if let previousStart = self.lastArrivalStartTime, now - previousStart < ChatWalletTransferArrivalMotion.spacing {
                    continue
                }
                arrival.startTime = now
                self.lastArrivalStartTime = now
            }
            guard let startTime = arrival.startTime else {
                continue
            }
            if let finish = view.updateIncomingTransferAnimation(startTime: startTime, rise: arrival.rise, at: now), finish >= ChatWalletTransferArrivalMotion.afterLanding {
                self.cancelArrival(id)
            }
        }
    }

    private var snapshot: ChatWalletTransferSnapshot? {
        guard let context = self.chatInteraction?.context else {
            return nil
        }
        return ChatHistoryUIHooks.shared.walletHooks.walletContext(context)?.chatTransferSnapshot
    }

    private var reduceMotion: Bool {
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func isAwaitingFlight(_ view: ChatWalletTransferView) -> Bool {
        let snapshot = self.snapshot
        for flight in self.flights.values {
            if let snapshot {
                self.refresh(flight, snapshot: snapshot)
            }
            if flight.matches(view) {
                return true
            }
        }
        return false
    }

    func prepare(id: String) {
        guard !self.reduceMotion, id.hasPrefix("pending:"), self.flights[id] == nil, !self.endedFlights.contains(id),
              let snapshot = self.snapshot,
              let transaction = snapshot.transactions.first(where: { $0.presentationId == id }),
              transaction.status != .failed else {
            return
        }
        let flight = Flight(id: id)
        self.refresh(flight, snapshot: snapshot)
        self.flights[id] = flight
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for view in self.transferViews() where flight.matches(view) {
            view.setAwaitingTransferFlight(true)
        }
        CATransaction.commit()
        self.ensureLink()
    }

    func receive(id: String, source: ChatWalletTransferFlightSource?) -> Bool {
        guard !self.reduceMotion, id.hasPrefix("pending:"), self.flights[id]?.source == nil, !self.endedFlights.contains(id),
              let window = self.tableView?.window, let snapshot = self.snapshot,
              let transaction = snapshot.transactions.first(where: { $0.presentationId == id }),
              transaction.status != .failed, let source, source.window === window, source.window.contentView != nil else {
            self.cancel(id: id, animated: true)
            self.stopLinkIfIdle()
            return false
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let flight = self.flights[id] ?? Flight(id: id)
        flight.launch(source: source)
        self.refresh(flight, snapshot: snapshot)
        self.flights[id] = flight
        for view in self.transferViews() where flight.matches(view) {
            view.setAwaitingTransferFlight(true)
        }
        CATransaction.commit()
        self.chatInteraction?.scrollToLatest(true)
        self.update()
        self.ensureLink()
        return true
    }

    func cancelAll() {
        for id in Array(self.arrivals.keys) {
            self.cancelArrival(id)
        }
        for id in Array(self.flights.keys) {
            self.cancel(id: id, animated: false)
        }
        self.stopLinkIfIdle()
    }

    private func ensureLink() {
        if (!self.flights.isEmpty || !self.arrivals.isEmpty) && self.link == nil {
            self.link = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max, { [weak self] _ in
                self?.update()
            })
        }
    }

    private func stopLinkIfIdle() {
        if self.flights.isEmpty && self.arrivals.isEmpty {
            self.link?.invalidate()
            self.link = nil
        }
    }

    private func refresh(_ flight: Flight, snapshot: ChatWalletTransferSnapshot) {
        if let pending = snapshot.pendingTransfers.first(where: { $0.id == flight.operationId }) {
            flight.transactionHash = chatWalletTransferTransactionHash(pending.transactionHash) ?? flight.transactionHash
        }
        if let transaction = snapshot.transactions.first(where: { $0.presentationId == flight.id }) {
            flight.transactionHash = chatWalletTransferTransactionHash(transaction.transactionHash ?? transaction.id) ?? flight.transactionHash
        }
    }

    private func updateVisibleIncomingTransfers() {
        for view in self.transferViews(visibleOnly: true) {
            view.updateIncomingTransferVisibility()
        }
    }

    private func transferViews(visibleOnly: Bool = false) -> [ChatWalletTransferView] {
        var result: [ChatWalletTransferView] = []
        if visibleOnly {
            self.tableView?.enumerateVisibleViews(with: { view in
                if let view = (view as? ChatServiceRowView)?.walletTransferView {
                    result.append(view)
                }
            })
        } else {
            self.tableView?.enumerateViews(with: { view in
                if let view = (view as? ChatServiceRowView)?.walletTransferView {
                    result.append(view)
                }
                return true
            })
        }
        return result
    }

    private func update() {
        guard let tableView = self.tableView, tableView.window != nil else {
            self.cancelAll()
            return
        }
        let now = CACurrentMediaTime()
        let views = self.transferViews(visibleOnly: true)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer {
            CATransaction.commit()
        }
        self.updateArrivals(at: now, views: views)
        let snapshot = self.snapshot
        for id in Array(self.flights.keys) {
            guard let flight = self.flights[id] else {
                continue
            }
            guard let snapshot else {
                self.cancel(id: id, animated: false)
                continue
            }
            self.refresh(flight, snapshot: snapshot)
            let transaction = snapshot.transactions.first(where: { $0.presentationId == id })
            let hasPending = snapshot.pendingTransfers.contains(where: { $0.id == flight.operationId })
            guard !self.reduceMotion, transaction?.status != .failed, transaction != nil || hasPending else {
                self.cancel(id: id, animated: true)
                continue
            }
            guard let source = flight.source, let overlay = flight.overlay else {
                if now - flight.createdAt >= ChatWalletTransferFlightMotion.handOverTimeout {
                    self.cancel(id: id, animated: true)
                }
                continue
            }
            let target = views.first(where: { view in
                return flight.matches(view) && view.transferDiamondTarget(in: overlay) != nil
            })
            if let previous = flight.target, previous !== target, flight.matches(previous) {
                previous.setAwaitingTransferFlight(false)
            }
            flight.target = target
            guard let target, let slot = target.transferDiamondTarget(in: overlay), overlay.bounds.contains(slot.center) else {
                if flight.startedAt != nil || now - flight.createdAt >= ChatWalletTransferFlightMotion.cardTimeout {
                    self.cancel(id: id, animated: true)
                }
                continue
            }
            target.setAwaitingTransferFlight(true)
            if flight.startedAt == nil {
                flight.startedAt = now
            }
            let t = ChatWalletTransferFlightMotion.progress(now: now, start: flight.startedAt ?? now)
            let center = ChatWalletTransferFlightMotion.center(origin: overlay.convert(source.center, from: nil), target: slot.center, t: t)
            let diamond = source.diamond
            diamond.setFrameOrigin(NSMakePoint(center.x - diamond.frame.width / 2, center.y - diamond.frame.height / 2))
            let width = ChatWalletTransferFlightMotion.width(sourceWidth: source.width, targetWidth: slot.width, t: t)
            diamond.updateWalletTransfer(width: width, rotationSpeed: ChatWalletTransferFlightMotion.rotationSpeed(t: t), completion: false, isDark: theme.colors.isDark, appearance: ChatWalletTransferFlightMotion.usesCardAppearance(t: t) ? .cool : .blue)
            if t >= 1.0 {
                self.flights.removeValue(forKey: id)
                self.endedFlights.insert(id)
                target.acceptTransferDiamond(diamond)
                flight.overlay?.removeFromSuperview()
            }
        }
        self.stopLinkIfIdle()
    }

    private func cancel(id: String, animated: Bool) {
        guard let flight = self.flights.removeValue(forKey: id) else {
            return
        }
        self.endedFlights.insert(id)
        for view in self.transferViews() where flight.matches(view) {
            view.setAwaitingTransferFlight(false, animated: animated)
        }
        flight.source?.diamond.isRenderingEnabled = false
        if animated, let overlay = flight.overlay {
            overlay.layer?.opacity = 0
            overlay.layer?.animateAlpha(from: 1, to: 0, duration: 0.15, completion: { _ in
                overlay.removeFromSuperview()
            })
        } else {
            flight.overlay?.removeFromSuperview()
        }
    }
}
