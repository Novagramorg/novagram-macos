import AppKit
import QuartzCore

public extension CALayer {
    var isTimelineFrozen: Bool {
        return self.speed == 0
    }
    
    func setTimelineFrozen(_ frozen: Bool) {
        if frozen == self.isTimelineFrozen {
            return
        }
        if frozen {
            let pausedTime = self.convertTime(CACurrentMediaTime(), from: nil)
            self.speed = 0
            self.timeOffset = pausedTime
        } else {
            let pausedTime = self.timeOffset
            self.speed = 1
            self.timeOffset = 0
            self.beginTime = 0
            self.beginTime = self.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        }
    }
}

public final class WindowKeyObserver {
    private weak var window: NSWindow?
    private var tokens: [NSObjectProtocol] = []
    private let update: () -> Void
    
    public init(update: @escaping () -> Void) {
        self.update = update
    }
    
    deinit {
        self.removeTokens()
    }
    
    public func observe(_ window: NSWindow?) {
        if self.window === window, !self.tokens.isEmpty || window == nil {
            return
        }
        self.removeTokens()
        self.window = window
        guard let window = window else {
            return
        }
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            self.tokens.append(center.addObserver(forName: name, object: window, queue: .main, using: { [weak self] _ in
                self?.update()
            }))
        }
    }
    
    public static func isKey(_ window: NSWindow?) -> Bool {
        guard let window = window else {
            return false
        }
        return window.isKeyWindow || !window.canBecomeKey
    }
    
    private func removeTokens() {
        for token in self.tokens {
            NotificationCenter.default.removeObserver(token)
        }
        self.tokens.removeAll()
    }
}
