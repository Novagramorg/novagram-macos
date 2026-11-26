import Foundation

final class StarPurchaseSession {
    private let lock = NSLock()
    private var open = true
    private var pending: UUID?

    var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return open
    }

    func begin() -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        guard open, pending == nil else { return nil }
        let id = UUID()
        pending = id
        return id
    }

    func isCurrent(_ id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return open && pending == id
    }

    @discardableResult
    func finish(_ id: UUID, paid: Bool = false) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard open, pending == id else { return false }
        pending = nil
        if paid { open = false }
        return true
    }

    func close() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard open else { return false }
        open = false
        pending = nil
        return true
    }
}
