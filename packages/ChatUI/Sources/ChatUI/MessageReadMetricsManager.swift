import Cocoa
import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
#if SHARE
import TelegramThemeShare
import TelegramContextShare
#else
import TelegramTheme
import TelegramContext
#endif

struct ReadTimeSlice: Equatable {
    var totalMs: Int
    var activeMs: Int

    static func between(_ start: CFAbsoluteTime, _ end: CFAbsoluteTime, activeUntil: CFAbsoluteTime) -> ReadTimeSlice {
        let elapsed = max(0, end - start)
        let active = max(0, min(end, activeUntil) - start)
        return ReadTimeSlice(totalMs: Int(elapsed * 1000), activeMs: Int(min(active, elapsed) * 1000))
    }
}

public final class MessageReadMetricsManager {

    public struct VisibleMessageInfo {
        public let messageId: MessageId
        public let itemHeight: CGFloat
        public let visibleRect: NSRect
        public let viewportHeight: CGFloat
        public init(messageId: MessageId, itemHeight: CGFloat, visibleRect: NSRect, viewportHeight: CGFloat) {
            self.messageId = messageId
            self.itemHeight = itemHeight
            self.visibleRect = visibleRect
            self.viewportHeight = viewportHeight
        }
    }

    private struct MessageTrackingState {
        public let viewId: Int64
        public let messageId: MessageId
        public var startTime: CFAbsoluteTime
        public var accumulatedTimeMs: Int
        public var accumulatedActiveTimeMs: Int
        public var lastTickTime: CFAbsoluteTime
        public var postHeight: CGFloat
        public var viewportHeight: CGFloat
        public var seenTop: CGFloat
        public var seenBottom: CGFloat
        public var confirmed: Bool
        public var startGraceTimer: SwiftSignalKit.Timer?
        public var endGraceTimer: SwiftSignalKit.Timer?
    }

    private let context: any AccountContextProtocol
    private let peerId: PeerId

    private var trackingStates: [MessageId: MessageTrackingState] = [:]
    private var pendingMetrics: [TelegramMessageReadMetric] = []

    private var batchTimer: SwiftSignalKit.Timer?
    private var finalizeTimer: SwiftSignalKit.Timer?
    private let trackingLimit: CFAbsoluteTime = 300
    private let reportDisposable = MetaDisposable()

    private var lastUserActivityTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private let userActivityTimeout: CFAbsoluteTime = 15.0
    private var isGloballyPaused: Bool = false

    public init(context: any AccountContextProtocol, peerId: PeerId) {
        self.context = context
        self.peerId = peerId
    }

    deinit {
        finalizeTimer?.invalidate()
        batchTimer?.invalidate()
        reportDisposable.dispose()
        for (_, state) in trackingStates {
            state.startGraceTimer?.invalidate()
            state.endGraceTimer?.invalidate()
        }
    }

    public func updateVisibleMessages(_ messages: [VisibleMessageInfo]) {
        let currentIds = Set(messages.map { $0.messageId })

        for info in messages {
            if var state = trackingStates[info.messageId] {
                if state.endGraceTimer != nil {
                    state.endGraceTimer?.invalidate()
                    state.endGraceTimer = nil
                }
                state.seenTop = min(state.seenTop, info.visibleRect.minY)
                state.seenBottom = max(state.seenBottom, info.visibleRect.maxY)
                trackingStates[info.messageId] = state
            } else {
                beginTracking(info)
            }
        }

        for (messageId, state) in trackingStates {
            if !currentIds.contains(messageId) && state.endGraceTimer == nil {
                startEndGrace(for: messageId)
            }
        }
    }

    public func recordUserActivity() {
        let now = CFAbsoluteTimeGetCurrent()
        if !isGloballyPaused {
            accumulateAll(until: now)
        }
        lastUserActivityTime = now
    }

    private func accumulate(_ state: inout MessageTrackingState, until now: CFAbsoluteTime) {
        let slice = ReadTimeSlice.between(state.lastTickTime, now, activeUntil: lastUserActivityTime + userActivityTimeout)
        state.accumulatedTimeMs += slice.totalMs
        state.accumulatedActiveTimeMs += slice.activeMs
        state.lastTickTime = now
    }

    private func accumulateAll(until now: CFAbsoluteTime) {
        for (id, var state) in trackingStates where state.confirmed {
            accumulate(&state, until: now)
            trackingStates[id] = state
        }
    }

    public func pause() {
        guard !isGloballyPaused else { return }
        isGloballyPaused = true
        accumulateAll(until: CFAbsoluteTimeGetCurrent())
        finalizeTimer?.invalidate()
        finalizeTimer = nil
    }

    public func resume() {
        guard isGloballyPaused else { return }
        isGloballyPaused = false
        let now = CFAbsoluteTimeGetCurrent()
        for (id, var state) in trackingStates {
            if state.confirmed {
                state.lastTickTime = now
                trackingStates[id] = state
            }
        }
        scheduleFinalizeTimer()
    }

    public func finalizeAll() {
        let ids = Array(trackingStates.keys)
        for id in ids {
            finalizeTracking(messageId: id)
        }
        flushBatch()
    }

    private func beginTracking(_ info: VisibleMessageInfo) {
        let messageId = info.messageId
        var state = MessageTrackingState(
            viewId: Int64.random(in: Int64.min...Int64.max),
            messageId: messageId,
            startTime: 0,
            accumulatedTimeMs: 0,
            accumulatedActiveTimeMs: 0,
            lastTickTime: 0,
            postHeight: info.itemHeight,
            viewportHeight: info.viewportHeight,
            seenTop: info.visibleRect.minY,
            seenBottom: info.visibleRect.maxY,
            confirmed: false,
            startGraceTimer: nil,
            endGraceTimer: nil
        )

        let timer = SwiftSignalKit.Timer(timeout: 0.3, repeat: false, completion: { [weak self] in
            self?.confirmTracking(messageId: messageId)
        }, queue: .mainQueue())
        state.startGraceTimer = timer
        trackingStates[messageId] = state
        timer.start()
    }

    private func confirmTracking(messageId: MessageId) {
        guard var state = trackingStates[messageId], !state.confirmed else { return }
        let now = CFAbsoluteTimeGetCurrent()
        state.confirmed = true
        state.startTime = now
        state.lastTickTime = now
        state.startGraceTimer = nil
        trackingStates[messageId] = state
        scheduleFinalizeTimer()
    }

    private func startEndGrace(for messageId: MessageId) {
        guard var state = trackingStates[messageId] else { return }
        if !state.confirmed {
            state.startGraceTimer?.invalidate()
            trackingStates.removeValue(forKey: messageId)
            scheduleFinalizeTimer()
            return
        }
        let timer = SwiftSignalKit.Timer(timeout: 0.3, repeat: false, completion: { [weak self] in
            self?.finalizeTracking(messageId: messageId)
        }, queue: .mainQueue())
        state.endGraceTimer = timer
        trackingStates[messageId] = state
        timer.start()
    }

    private func finalizeTracking(messageId: MessageId) {
        guard var state = trackingStates[messageId] else { return }
        state.startGraceTimer?.invalidate()
        state.endGraceTimer?.invalidate()

        if state.confirmed {
            if !isGloballyPaused {
                accumulate(&state, until: CFAbsoluteTimeGetCurrent())
            }

            if state.accumulatedTimeMs >= 300 {
                let heightToViewportRatio = state.viewportHeight > 0 ? Double(state.postHeight) / Double(state.viewportHeight) : 0
                let seenRangeRatio: Double
                if state.postHeight > 0 {
                    seenRangeRatio = min(max(Double(state.seenBottom - state.seenTop) / Double(state.postHeight), 0), 1)
                } else {
                    seenRangeRatio = 0
                }

                let metric = TelegramMessageReadMetric(
                    id: state.viewId,
                    messageId: state.messageId,
                    timeInViewMs: state.accumulatedTimeMs,
                    activeTimeInViewMs: state.accumulatedActiveTimeMs,
                    heightToViewportRatio: heightToViewportRatio,
                    seenRangeRatio: seenRangeRatio
                )
                pendingMetrics.append(metric)
                scheduleBatch()
            }
        }

        trackingStates.removeValue(forKey: messageId)
        scheduleFinalizeTimer()
    }

    private func finalizeExpired() {
        finalizeTimer = nil
        guard !isGloballyPaused else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let expired = trackingStates.values.filter { $0.confirmed && now - $0.startTime >= trackingLimit }.map { $0.messageId }
        for id in expired {
            finalizeTracking(messageId: id)
        }
        scheduleFinalizeTimer()
    }

    private func scheduleFinalizeTimer() {
        finalizeTimer?.invalidate()
        finalizeTimer = nil
        guard !isGloballyPaused else { return }
        guard let deadline = trackingStates.values.filter({ $0.confirmed }).map({ $0.startTime + trackingLimit }).min() else { return }
        let timer = SwiftSignalKit.Timer(timeout: max(0, deadline - CFAbsoluteTimeGetCurrent()), repeat: false, completion: { [weak self] in
            self?.finalizeExpired()
        }, queue: .mainQueue())
        finalizeTimer = timer
        timer.start()
    }

    private func scheduleBatch() {
        guard batchTimer == nil else { return }
        let timer = SwiftSignalKit.Timer(timeout: 2.0, repeat: false, completion: { [weak self] in
            self?.flushBatch()
        }, queue: .mainQueue())
        batchTimer = timer
        timer.start()
    }

    private func flushBatch() {
        batchTimer?.invalidate()
        batchTimer = nil

        guard !pendingMetrics.isEmpty else { return }
        let metrics = pendingMetrics
        pendingMetrics.removeAll()

        reportDisposable.set(
            context.engine.messages.reportPeerReadMetrics(
                peerId: peerId,
                metrics: metrics
            ).start()
        )
    }
}
