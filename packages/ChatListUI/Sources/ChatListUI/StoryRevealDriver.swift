import Cocoa
import TGUIKit

final class StoryRevealDriver {
    let model: StoryRevealModel
    private weak var table: TableView?
    private var link: SharedDisplayLinkDriver.Link?
    private let now: () -> Double

    var didChange: (_ previousFraction: CGFloat, _ tracking: Bool) -> Void = { _, _ in }

    init(table: TableView, model: StoryRevealModel = StoryRevealModel(), now: @escaping () -> Double = CACurrentMediaTime) {
        self.table = table
        self.model = model
        self.now = now
    }

    deinit {
        self.link?.invalidate()
    }

    var isTicking: Bool {
        return self.link != nil
    }

    func handle(_ event: NSEvent) -> Bool {
        let now = self.now()
        return self.handle(StoryRevealModel.input(event, time: StoryRevealDriver.eventTime(event, now: now)))
    }

    private struct Snapshot: Equatable {
        var fraction: CGFloat
        var animating: Bool
        var tracking: Bool
    }

    private var snapshot: Snapshot {
        return Snapshot(fraction: self.model.fraction, animating: self.model.isAnimating, tracking: self.model.isTracking)
    }

    func handle(_ input: StoryRevealInput) -> Bool {
        guard let table = self.table else {
            return false
        }
        let previous = self.snapshot
        let decision = self.model.handle(input, tableOffset: table.documentOffset.y)
        self.sync(from: previous)
        return decision == .consumed
    }

    func tableDidScroll() {
        guard let table = self.table else {
            return
        }
        let previous = self.snapshot
        self.model.tableDidScroll(offset: table.documentOffset.y, time: self.now())
        self.sync(from: previous)
    }

    func finishIfPartial() {
        let previous = self.snapshot
        self.model.finishIfPartial(time: self.now())
        self.sync(from: previous)
    }

    func setRevealed(_ revealed: Bool, animated: Bool) {
        let previous = self.snapshot
        self.model.setRevealed(revealed, animated: animated, time: self.now())
        self.sync(from: previous)
    }

    func setEnabled(_ enabled: Bool) {
        guard self.model.enabled != enabled else {
            return
        }
        let previous = self.snapshot
        self.model.advance(to: self.now())
        self.model.enabled = enabled
        self.sync(from: previous)
    }

    #if DEBUG
    private(set) var ticks = 0
    #endif

    func tick() {
        #if DEBUG
        self.ticks += 1
        #endif
        let previous = self.snapshot
        self.model.advance(to: self.now())
        self.sync(from: previous)
    }

    private func sync(from previous: Snapshot) {
        if self.snapshot != previous {
            self.didChange(previous.fraction, self.model.isTracking)
        }
        if let delta = self.model.takeTableDelta() {
            self.scrollTable(by: delta)
        }
        if self.model.isAnimating {
            if self.link == nil {
                self.link = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max, { [weak self] _ in
                    self?.tick()
                })
            }
        } else if let link = self.link {
            link.invalidate()
            self.link = nil
        }
    }

    private func scrollTable(by delta: CGFloat) {
        guard let table = self.table else {
            return
        }
        let limit = max(0, table.documentSize.height - table.clipView.bounds.height)
        let target = table.documentOffset.y + delta
        let y = min(max(0, target), limit)
        if abs(table.documentOffset.y - y) > 0.01 {
            table.clipView.scroll(to: NSPoint(x: 0, y: y), animated: false)
        }
        if target >= limit {
            self.model.stopGlide()
        }
    }

    static func eventTime(_ event: NSEvent, now: Double) -> Double {
        return abs(now - event.timestamp) < 0.5 ? min(event.timestamp, now) : now
    }
}

extension StoryRevealModel {
    static func input(_ event: NSEvent, time: Double) -> StoryRevealInput {
        let phase: StoryRevealInput.Phase
        switch event.phase {
        case .began:
            phase = .began
        case .changed:
            phase = .changed
        case .stationary:
            phase = .stationary
        case .ended:
            phase = .ended
        case .cancelled:
            phase = .cancelled
        case .mayBegin:
            phase = .mayBegin
        default:
            phase = .none
        }
        let momentum: StoryRevealInput.Momentum
        switch event.momentumPhase {
        case .began:
            momentum = .began
        case .changed, .stationary:
            momentum = .changed
        case .ended, .cancelled:
            momentum = .ended
        default:
            momentum = .none
        }
        return StoryRevealInput(phase: phase, momentum: momentum, deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas, time: time)
    }
}
