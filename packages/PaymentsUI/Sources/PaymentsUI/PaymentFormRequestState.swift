import Foundation

final class PaymentFormRequestState {
    private let lock = NSLock()
    private var active = true
    private var request: UUID?

    func begin() -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        guard active else { return nil }
        let id = UUID()
        request = id
        return id
    }

    func take(_ id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard active, request == id else { return false }
        request = nil
        return true
    }

    func invalidate() {
        lock.lock()
        request = nil
        lock.unlock()
    }

    func suspend() {
        lock.lock()
        active = false
        request = nil
        lock.unlock()
    }

    func resume() {
        lock.lock()
        active = true
        lock.unlock()
    }
}
