#if DEBUG
import AppKit
import QuartzCore

public final class PerfLabFrameStats {
    public private(set) var frames: Int = 0
    public private(set) var hitches: Int = 0
    public private(set) var longHitches: Int = 0
    public private(set) var hitchTime: Double = 0
    public private(set) var worstGap: Double = 0
    public private(set) var frameDuration: Double = 1.0 / 60.0

    fileprivate func record(gap: Double, frameDuration: Double) {
        self.frames += 1
        self.frameDuration = frameDuration
        self.worstGap = max(self.worstGap, gap)
        if gap > frameDuration * 1.5 {
            self.hitches += 1
            self.hitchTime += gap - frameDuration
        }
        if gap > 0.0334 {
            self.longHitches += 1
        }
    }
}

public final class PerfLabFrameClock: NSObject {
    private weak var view: NSView?
    private var link: AnyObject?
    private var fallbackTimer: Timer?
    private var lastTimestamp: Double?
    public private(set) var stats = PerfLabFrameStats()
    public var onFrame: ((Double) -> Void)?

    public init(view: NSView) {
        self.view = view
        super.init()
    }

    public func start() {
        self.stats = PerfLabFrameStats()
        self.lastTimestamp = nil
        if #available(macOS 14.0, *), let view = self.view {
            let link = view.displayLink(target: self, selector: #selector(self.displayLinkTick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        } else {
            let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true, block: { [weak self] _ in
                self?.frame(timestamp: CACurrentMediaTime(), frameDuration: 1.0 / 60.0)
            })
            RunLoop.main.add(timer, forMode: .common)
            self.fallbackTimer = timer
        }
    }

    public func stop() {
        if #available(macOS 14.0, *), let link = self.link as? CADisplayLink {
            link.invalidate()
        }
        self.link = nil
        self.fallbackTimer?.invalidate()
        self.fallbackTimer = nil
    }

    @available(macOS 14.0, *)
    @objc private func displayLinkTick(_ link: CADisplayLink) {
        let frameDuration = link.targetTimestamp - link.timestamp
        self.frame(timestamp: link.timestamp, frameDuration: frameDuration > 0 ? frameDuration : 1.0 / 60.0)
    }

    private func frame(timestamp: Double, frameDuration: Double) {
        if let lastTimestamp = self.lastTimestamp {
            self.stats.record(gap: timestamp - lastTimestamp, frameDuration: frameDuration)
        }
        self.lastTimestamp = timestamp
        self.onFrame?(timestamp)
    }
}
#endif
