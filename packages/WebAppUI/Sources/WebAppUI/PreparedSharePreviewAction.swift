final class PreparedSharePreviewAction {
    private var nextId: UInt64 = 0
    private var pending: UInt64?
    private var terminal = false
    private var closing = false

    func begin() -> UInt64? {
        guard !terminal, !closing, pending == nil else { return nil }
        nextId &+= 1
        pending = nextId
        return nextId
    }

    func isCurrent(_ id: UInt64) -> Bool {
        return !terminal && !closing && pending == id
    }

    func finish(_ id: UInt64) -> Bool {
        guard isCurrent(id) else { return false }
        pending = nil
        terminal = true
        return true
    }

    func cancel() -> Bool {
        guard !terminal else { return false }
        terminal = true
        pending = nil
        return true
    }

    func beginClose() -> Bool {
        guard !closing else { return false }
        closing = true
        return true
    }
}
