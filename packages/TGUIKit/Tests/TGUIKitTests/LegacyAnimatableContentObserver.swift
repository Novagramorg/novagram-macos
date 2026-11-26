import AppKit

public struct LegacyAnimatableContentObserverOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    public static let contentBounds = LegacyAnimatableContentObserverOptions(rawValue: 1 << 0)
    public static let documentFrame = LegacyAnimatableContentObserverOptions(rawValue: 1 << 1)
    public static let ownFrame = LegacyAnimatableContentObserverOptions(rawValue: 1 << 2)
    public static let ownBounds = LegacyAnimatableContentObserverOptions(rawValue: 1 << 3)
}

public final class LegacyAnimatableContentObserver {
    private weak var observedWindow: NSWindow?
    private weak var observedContentView: NSView?
    private weak var observedDocumentView: NSView?
    private weak var observedView: NSView?
    private weak var observedTarget: AnyObject?
    private var registrations: [(name: Notification.Name, object: AnyObject)] = []
    private var registered: Bool = false

    public init() {
    }

    public func update(for view: NSView, target: AnyObject, selector: Selector, options: LegacyAnimatableContentObserverOptions = [.contentBounds, .documentFrame]) {
        self.update(for: view, target: target, selector: selector, contentView: view.enclosingScrollView?.contentView, documentView: view.enclosingScrollView?.documentView, options: options)
    }

    public func update(for view: NSView, target: AnyObject, selector: Selector, contentView: NSView?, documentView: NSView?, options: LegacyAnimatableContentObserverOptions) {
        guard let window = view.window else {
            self.unregister()
            return
        }

        if registered
            && observedWindow === window
            && observedContentView === contentView
            && observedDocumentView === documentView
            && observedTarget === target {
            return
        }

        self.unregister()

        let center = NotificationCenter.default
        var registrations: [(name: Notification.Name, object: AnyObject)] = []
        func add(_ name: Notification.Name, _ object: AnyObject) {
            center.addObserver(target, selector: selector, name: name, object: object)
            registrations.append((name, object))
        }
        add(NSWindow.didBecomeKeyNotification, window)
        add(NSWindow.didResignKeyNotification, window)
        if options.contains(.contentBounds) {
            if let contentView = contentView {
                add(NSView.boundsDidChangeNotification, contentView)
            }
        }
        if options.contains(.ownBounds) {
            add(NSView.boundsDidChangeNotification, view)
        }
        if options.contains(.documentFrame) {
            if let documentView = documentView {
                add(NSView.frameDidChangeNotification, documentView)
            }
        }
        if options.contains(.ownFrame) {
            add(NSView.frameDidChangeNotification, view)
        }
        if (options.contains(.contentBounds) && contentView == nil) || (options.contains(.documentFrame) && documentView == nil) {
            add(NSWindow.didResizeNotification, window)
        }
        self.registrations = registrations
        observedWindow = window
        observedContentView = contentView
        observedDocumentView = documentView
        observedView = view
        observedTarget = target
        registered = true
    }

    private func unregister() {
        guard registered else {
            return
        }
        if let target = observedTarget {
            let center = NotificationCenter.default
            for registration in registrations {
                center.removeObserver(target, name: registration.name, object: registration.object)
            }
        }
        registrations.removeAll()
        observedWindow = nil
        observedContentView = nil
        observedDocumentView = nil
        observedView = nil
        observedTarget = nil
        registered = false
    }
}

public final class LegacyAnimatableContentTokenObserver {
    private weak var observedWindow: NSWindow?
    private weak var observedContentView: NSView?
    private weak var observedDocumentView: NSView?
    private var tokens: [NSObjectProtocol] = []

    public init() {
    }

    public func update(for view: NSView, handler: @escaping (Notification) -> Void) {
        guard let w = view.window else {
            return
        }
        let cv = view.enclosingScrollView?.contentView
        let dv = view.enclosingScrollView?.documentView

        if !tokens.isEmpty
            && observedWindow === w
            && observedContentView === cv
            && observedDocumentView === dv {
            return
        }

        let center = NotificationCenter.default
        for token in tokens {
            center.removeObserver(token)
        }
        tokens.removeAll()

        tokens.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: w, queue: .main, using: handler))
        tokens.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: w, queue: .main, using: handler))
        if let cv = cv {
            tokens.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: cv, queue: .main, using: handler))
        }
        if let dv = dv {
            tokens.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: dv, queue: .main, using: handler))
        }
        if cv == nil || dv == nil {
            tokens.append(center.addObserver(forName: NSWindow.didResizeNotification, object: w, queue: .main, using: handler))
        }
        observedWindow = w
        observedContentView = cv
        observedDocumentView = dv
    }

    public func removeObservers() {
        let center = NotificationCenter.default
        for token in tokens {
            center.removeObserver(token)
        }
        tokens.removeAll()
    }
}
