#if DEBUG
import AppKit

public struct PerfLabScrollSegment {
    public let duration: Double
    public let velocity: Double

    public init(duration: Double, velocity: Double) {
        self.duration = duration
        self.velocity = velocity
    }
}

public final class PerfLabScrollDriver {
    private let scrollView: NSScrollView
    private let eventTarget: (() -> NSResponder?)?
    private let segments: [PerfLabScrollSegment]
    private let wheelSign: Double
    private var startTime: Double?
    private var lastTime: Double?
    private var pending: Double = 0
    public private(set) var requestedDistance: Double = 0

    public var totalDuration: Double {
        return self.segments.reduce(0, { $0 + $1.duration })
    }

    public init(scrollView: NSScrollView, segments: [PerfLabScrollSegment], wheelSign: Double, eventTarget: (() -> NSResponder?)? = nil) {
        self.scrollView = scrollView
        self.eventTarget = eventTarget
        self.segments = segments
        self.wheelSign = wheelSign
    }

    private func velocity(at elapsed: Double) -> Double? {
        var offset = 0.0
        for segment in self.segments {
            if elapsed < offset + segment.duration {
                return segment.velocity
            }
            offset += segment.duration
        }
        return nil
    }

    public func step(timestamp: Double) -> Bool {
        guard let startTime = self.startTime, let lastTime = self.lastTime else {
            self.startTime = timestamp
            self.lastTime = timestamp
            return true
        }
        guard let velocity = self.velocity(at: timestamp - startTime) else {
            return false
        }
        self.pending += velocity * (timestamp - lastTime)
        self.lastTime = timestamp
        let delta = self.pending.rounded(.towardZero)
        if delta != 0 {
            self.pending -= delta
            self.requestedDistance += abs(delta)
            self.post(delta: delta)
        }
        return true
    }

    private func post(delta: Double) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(delta * self.wheelSign), wheel2: 0, wheel3: 0), let nsEvent = NSEvent(cgEvent: event) else {
            return
        }
        if let eventTarget = self.eventTarget {
            eventTarget()?.scrollWheel(with: nsEvent)
        } else {
            self.scrollView.scrollWheel(with: nsEvent)
        }
    }
}
#endif
