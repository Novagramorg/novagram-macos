import Foundation
import SwiftSignalKit

private final class NovagramJobRequestSlot {
    var started = false
    var released = false
    var cancelled = false
}

final class NovagramJobRequestLimiter {
    static let shared = NovagramJobRequestLimiter()
    static let maxConcurrentRequests = 6

    private let queue = Queue()
    private var active = 0
    private var waiting: [(slot: NovagramJobRequestSlot, start: () -> Void)] = []

    func limited<T>(_ signal: Signal<T, NoError>) -> Signal<T, NoError> {
        return Signal { [weak self] subscriber in
            guard let self else {
                return EmptyDisposable
            }
            let disposable = MetaDisposable()
            let slot = NovagramJobRequestSlot()
            let queue = self.queue
            queue.async {
                guard !slot.cancelled else {
                    return
                }
                self.enqueue(slot, start: {
                    disposable.set(signal.start(next: { value in
                        subscriber.putNext(value)
                    }, completed: {
                        queue.async {
                            self.release(slot)
                        }
                        subscriber.putCompletion()
                    }))
                })
            }
            return ActionDisposable {
                disposable.dispose()
                queue.async {
                    slot.cancelled = true
                    self.release(slot)
                }
            }
        }
    }

    private func enqueue(_ slot: NovagramJobRequestSlot, start: @escaping () -> Void) {
        if active < NovagramJobRequestLimiter.maxConcurrentRequests {
            slot.started = true
            active += 1
            start()
        } else {
            waiting.append((slot, start))
        }
    }

    private func release(_ slot: NovagramJobRequestSlot) {
        guard slot.started else {
            waiting.removeAll(where: { $0.slot === slot })
            return
        }
        guard !slot.released else {
            return
        }
        slot.released = true
        active -= 1
        while active < NovagramJobRequestLimiter.maxConcurrentRequests, !waiting.isEmpty {
            let next = waiting.removeFirst()
            guard !next.slot.cancelled else {
                continue
            }
            next.slot.started = true
            active += 1
            next.start()
        }
    }
}
