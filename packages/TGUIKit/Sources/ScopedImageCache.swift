import Cocoa
import CoreMedia

public final class ImageDisplayScope {
    public let id: Int

    fileprivate init(id: Int) {
        self.id = id
    }

    deinit {
        ScopedImageCache.scopeClosed(id)
    }
}

public final class ScopedImageCache {
    private struct Entry {
        let image: CGImage
        let sampleBuffer: CMSampleBuffer?
        let cost: Int
        var lastUsed: CFAbsoluteTime
        var scopes: Set<Int>
        var orphanedAt: CFAbsoluteTime?
    }

    private final class WeakCache {
        weak var value: ScopedImageCache?
        init(_ value: ScopedImageCache) {
            self.value = value
        }
    }

    public let countLimit: Int
    public let byteLimit: Int
    public let idleTimeout: TimeInterval
    public let closedScopeGrace: TimeInterval
    private let sweepInterval: TimeInterval
    private let clock: () -> CFAbsoluteTime

    private let lock = NSLock()
    private var entries: [Int: Entry] = [:]
    private var keysByImage: [ObjectIdentifier: [Int]] = [:]
    private var keysByScope: [Int: Set<Int>] = [:]
    private var totalCost: Int = 0
    private var sweepTimer: DispatchSourceTimer?
    private let sweepQueue = DispatchQueue(label: "org.telegram.scopedImageCache.sweep", qos: .utility)

    public init(countLimit: Int, byteLimit: Int, idleTimeout: TimeInterval, closedScopeGrace: TimeInterval, sweepInterval: TimeInterval = 60, clock: @escaping () -> CFAbsoluteTime = CFAbsoluteTimeGetCurrent) {
        self.countLimit = countLimit
        self.byteLimit = byteLimit
        self.idleTimeout = idleTimeout
        self.closedScopeGrace = closedScopeGrace
        self.sweepInterval = sweepInterval
        self.clock = clock
        ScopedImageCache.register(self)
    }

    deinit {
        sweepTimer?.cancel()
    }

    public func setImage(_ image: CGImage, sampleBuffer: CMSampleBuffer?, forKey key: Int) {
        let cost = image.bytesPerRow * image.height
        var released: [Entry] = []

        lock.lock()
        if let previous = removeEntry(key) {
            released.append(previous)
        }
        entries[key] = Entry(image: image, sampleBuffer: sampleBuffer, cost: cost, lastUsed: clock(), scopes: [], orphanedAt: nil)
        keysByImage[ObjectIdentifier(image), default: []].append(key)
        totalCost += cost
        released.append(contentsOf: evictIfNeeded())
        startSweepTimerIfNeeded()
        lock.unlock()

        released.removeAll()
    }

    public func image(forKey key: Int) -> (CGImage, CMSampleBuffer?)? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key] else {
            return nil
        }
        entries[key]?.lastUsed = clock()
        return (entry.image, entry.sampleBuffer)
    }

    public func removeImage(forKey key: Int) {
        lock.lock()
        let removed = removeEntry(key)
        if entries.isEmpty {
            stopSweepTimer()
        }
        lock.unlock()
        _ = removed
    }

    public func removeAll() {
        lock.lock()
        let removed = entries
        entries.removeAll()
        keysByImage.removeAll()
        keysByScope.removeAll()
        totalCost = 0
        stopSweepTimer()
        lock.unlock()
        _ = removed
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    var cost: Int {
        lock.lock()
        defer { lock.unlock() }
        return totalCost
    }

    var isSweeping: Bool {
        lock.lock()
        defer { lock.unlock() }
        return sweepTimer != nil
    }

    func sweep() {
        let now = clock()
        var released: [Entry] = []

        lock.lock()
        let expired = entries.compactMap { key, entry -> Int? in
            if now - entry.lastUsed >= idleTimeout {
                return key
            }
            if let orphanedAt = entry.orphanedAt, now - orphanedAt >= closedScopeGrace {
                return key
            }
            return nil
        }
        for key in expired {
            if let entry = removeEntry(key) {
                released.append(entry)
            }
        }
        if entries.isEmpty {
            stopSweepTimer()
        }
        lock.unlock()

        released.removeAll()
    }

    private func contains(_ image: CGImage) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return keysByImage[ObjectIdentifier(image)] != nil
    }

    private func attach(_ image: CGImage, to scope: Int) {
        lock.lock()
        if let keys = keysByImage[ObjectIdentifier(image)] {
            let now = clock()
            for key in keys where entries[key] != nil {
                entries[key]?.lastUsed = now
                entries[key]?.orphanedAt = nil
                if entries[key]?.scopes.insert(scope).inserted == true {
                    keysByScope[scope, default: []].insert(key)
                }
            }
        }
        lock.unlock()
    }

    private func closeScope(_ scope: Int) {
        var released: [Entry] = []
        var orphaned = false

        lock.lock()
        if let keys = keysByScope.removeValue(forKey: scope) {
            let now = clock()
            for key in keys {
                guard entries[key]?.scopes.remove(scope) != nil, entries[key]?.scopes.isEmpty == true else {
                    continue
                }
                if closedScopeGrace <= 0 {
                    if let entry = removeEntry(key) {
                        released.append(entry)
                    }
                } else {
                    entries[key]?.orphanedAt = now
                    orphaned = true
                }
            }
        }
        if entries.isEmpty {
            stopSweepTimer()
        }
        lock.unlock()

        if orphaned {
            sweepQueue.asyncAfter(deadline: .now() + closedScopeGrace) { [weak self] in
                self?.sweep()
            }
        }
        released.removeAll()
    }

    private func removeEntry(_ key: Int) -> Entry? {
        guard let entry = entries.removeValue(forKey: key) else {
            return nil
        }
        totalCost -= entry.cost
        let imageId = ObjectIdentifier(entry.image)
        if var keys = keysByImage[imageId] {
            keys.removeAll(where: { $0 == key })
            keysByImage[imageId] = keys.isEmpty ? nil : keys
        }
        for scope in entry.scopes {
            keysByScope[scope]?.remove(key)
            if keysByScope[scope]?.isEmpty == true {
                keysByScope.removeValue(forKey: scope)
            }
        }
        return entry
    }

    private func evictIfNeeded() -> [Entry] {
        guard entries.count > countLimit || totalCost > byteLimit else {
            return []
        }
        let evictsFirst: ((key: Int, value: Entry), (key: Int, value: Entry)) -> Bool = { lhs, rhs in
            let lhsOrphaned = lhs.value.orphanedAt != nil
            let rhsOrphaned = rhs.value.orphanedAt != nil
            if lhsOrphaned != rhsOrphaned {
                return lhsOrphaned
            }
            return lhs.value.lastUsed < rhs.value.lastUsed
        }
        var released: [Entry] = []
        if let first = entries.min(by: evictsFirst), let entry = removeEntry(first.key) {
            released.append(entry)
        }
        guard entries.count > countLimit || totalCost > byteLimit else {
            return released
        }
        for (key, _) in entries.sorted(by: evictsFirst) {
            if entries.count <= countLimit && totalCost <= byteLimit {
                break
            }
            if let entry = removeEntry(key) {
                released.append(entry)
            }
        }
        return released
    }

    private func startSweepTimerIfNeeded() {
        guard !entries.isEmpty else {
            stopSweepTimer()
            return
        }
        guard sweepTimer == nil else {
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: sweepQueue)
        timer.schedule(deadline: .now() + sweepInterval, repeating: sweepInterval, leeway: .milliseconds(Int(sweepInterval * 100)))
        timer.setEventHandler { [weak self] in
            self?.sweep()
        }
        timer.resume()
        sweepTimer = timer
    }

    private func stopSweepTimer() {
        sweepTimer?.cancel()
        sweepTimer = nil
    }
}

extension ScopedImageCache {
    private static let registryLock = NSLock()
    private static var registry: [WeakCache] = []
    private static var nextScopeId: Int = 0
    private static var scopeKey: UInt8 = 0

    private static func register(_ cache: ScopedImageCache) {
        registryLock.lock()
        registry.removeAll(where: { $0.value == nil })
        registry.append(WeakCache(cache))
        registryLock.unlock()
    }

    private static var liveCaches: [ScopedImageCache] {
        registryLock.lock()
        defer { registryLock.unlock() }
        return registry.compactMap { $0.value }
    }

    public static func noteDisplayed(_ image: CGImage, in view: NSView) {
        let holders = liveCaches.filter { $0.contains(image) }
        guard !holders.isEmpty, let scope = displayScope(for: view) else {
            return
        }
        for cache in holders {
            cache.attach(image, to: scope.id)
        }
    }

    static func displayScope(for view: NSView) -> ImageDisplayScope? {
        guard let window = view.window else {
            return nil
        }
        var anchor: AnyObject = window
        var current: NSView? = view
        while let candidate = current {
            if candidate is NSScrollView {
                anchor = candidate
            }
            current = candidate.superview
        }
        if let scope = objc_getAssociatedObject(anchor, &scopeKey) as? ImageDisplayScope {
            return scope
        }
        registryLock.lock()
        nextScopeId += 1
        let scope = ImageDisplayScope(id: nextScopeId)
        registryLock.unlock()
        objc_setAssociatedObject(anchor, &scopeKey, scope, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return scope
    }

    fileprivate static func scopeClosed(_ scope: Int) {
        for cache in liveCaches {
            cache.closeScope(scope)
        }
    }
}
