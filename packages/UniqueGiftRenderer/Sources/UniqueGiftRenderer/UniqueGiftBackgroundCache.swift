import Foundation
import CoreGraphics

public struct UniqueGiftBackgroundKey: Hashable {
    public let geometry: UniqueGiftBackgroundGeometry
    public let colors: UniqueGiftColors
    public let glyphId: Int64?
    public let scale: CGFloat
    public let colorSpace: CGColorSpace

    public init(geometry: UniqueGiftBackgroundGeometry, colors: UniqueGiftColors, glyphId: Int64?, scale: CGFloat, colorSpace: CGColorSpace = UniqueGiftBackgroundRenderer.colorSpace) {
        self.geometry = geometry
        self.colors = colors
        self.glyphId = glyphId
        self.scale = scale
        self.colorSpace = UniqueGiftBackgroundRenderer.renderColorSpace(colorSpace)
    }
}

public final class UniqueGiftBackgroundCache {
    public static let shared = UniqueGiftBackgroundCache(byteLimit: 16 * 1024 * 1024, idleTimeout: 5.0 * 60.0)

    private struct Entry {
        let image: CGImage
        let bytes: Int
        var lastUse: UInt64
        var lastUseTime: CFAbsoluteTime
    }

    private let byteLimit: Int
    private let idleTimeout: TimeInterval
    private let sweepInterval: TimeInterval
    private let lock = NSLock()
    private var entries: [UniqueGiftBackgroundKey: Entry] = [:]
    private var totalBytes = 0
    private var clock: UInt64 = 0
    private var sweepTimer: DispatchSourceTimer?
    private let sweepQueue = DispatchQueue(label: "org.telegram.uniqueGiftBackgroundCache.sweep", qos: .utility)

    public init(byteLimit: Int, idleTimeout: TimeInterval = .infinity, sweepInterval: TimeInterval = 60.0) {
        self.byteLimit = byteLimit
        self.idleTimeout = idleTimeout
        self.sweepInterval = sweepInterval
    }

    deinit {
        self.sweepTimer?.cancel()
    }

    public var byteCount: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.totalBytes
    }

    public func cachedImage(for key: UniqueGiftBackgroundKey) -> CGImage? {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard var entry = self.entries[key] else {
            return nil
        }
        self.clock += 1
        entry.lastUse = self.clock
        entry.lastUseTime = CFAbsoluteTimeGetCurrent()
        self.entries[key] = entry
        return entry.image
    }

    public func image(for key: UniqueGiftBackgroundKey, glyph: CGImage?) -> CGImage? {
        if let image = self.cachedImage(for: key) {
            return image
        }
        guard let image = UniqueGiftBackgroundRenderer.makeImage(geometry: key.geometry, colors: key.colors, glyph: glyph, scale: key.scale, colorSpace: key.colorSpace) else {
            return nil
        }
        self.store(image, for: key)
        return image
    }

    public func store(_ image: CGImage, for key: UniqueGiftBackgroundKey) {
        let bytes = image.bytesPerRow * image.height
        var released: [CGImage] = []
        self.lock.lock()
        if let previous = self.entries[key] {
            self.totalBytes -= previous.bytes
            released.append(previous.image)
        }
        self.clock += 1
        self.entries[key] = Entry(image: image, bytes: bytes, lastUse: self.clock, lastUseTime: CFAbsoluteTimeGetCurrent())
        self.totalBytes += bytes
        while self.totalBytes > self.byteLimit, self.entries.count > 1, let oldest = self.entries.min(by: { $0.value.lastUse < $1.value.lastUse }) {
            self.entries.removeValue(forKey: oldest.key)
            self.totalBytes -= oldest.value.bytes
            released.append(oldest.value.image)
        }
        self.startSweepTimerIfNeeded()
        self.lock.unlock()
        released.removeAll()
    }

    public func removeAll() {
        self.lock.lock()
        let released = self.entries
        self.entries.removeAll()
        self.totalBytes = 0
        self.stopSweepTimer()
        self.lock.unlock()
        _ = released
    }

    func sweepIdleEntries(now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) {
        var released: [CGImage] = []
        self.lock.lock()
        for (key, entry) in self.entries where now - entry.lastUseTime >= self.idleTimeout {
            self.entries.removeValue(forKey: key)
            self.totalBytes -= entry.bytes
            released.append(entry.image)
        }
        if self.entries.isEmpty {
            self.stopSweepTimer()
        }
        self.lock.unlock()
        released.removeAll()
    }

    private func startSweepTimerIfNeeded() {
        guard self.sweepTimer == nil, self.idleTimeout.isFinite else {
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: self.sweepQueue)
        timer.schedule(deadline: .now() + self.sweepInterval, repeating: self.sweepInterval, leeway: .milliseconds(Int(self.sweepInterval * 100.0)))
        timer.setEventHandler { [weak self] in
            self?.sweepIdleEntries()
        }
        timer.resume()
        self.sweepTimer = timer
    }

    private func stopSweepTimer() {
        self.sweepTimer?.cancel()
        self.sweepTimer = nil
    }
}
