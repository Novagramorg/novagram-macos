import Cocoa

public struct WindowAttachment {
    private weak var window: NSWindow?

    public init() {
    }

    public mutating func update(_ window: NSWindow?) -> Bool {
        guard window !== self.window else {
            return false
        }
        self.window = window
        return true
    }
}
