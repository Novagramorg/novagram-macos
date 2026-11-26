#if DEBUG
import AppKit

public final class PerfLabScrollMeasurement {
    private let clock: PerfLabFrameClock
    private let driver: PerfLabScrollDriver
    private let scrollView: NSScrollView
    private let processMonitor: PerfLabProcessMonitor
    private let sampleInterval: Int
    private let sampler: (() -> [String: Double])?
    private var sampleSums: [String: Double] = [:]
    private var sampleCount: Int = 0
    private var frameIndex: Int = 0
    private var completion: (([String: Double]) -> Void)?
    private var startSnapshot: PerfLabProcessSnapshot?
    private var startOffset: CGFloat = 0
    private var minOffset: CGFloat = 0
    private var maxOffset: CGFloat = 0
    private var startUnixTime: Double = 0

    public init(view: NSView, scrollView: NSScrollView, segments: [PerfLabScrollSegment], wheelSign: Double, processMonitor: PerfLabProcessMonitor, sampleInterval: Int = 6, sampler: (() -> [String: Double])? = nil, eventTarget: (() -> NSResponder?)? = nil) {
        self.clock = PerfLabFrameClock(view: view)
        self.driver = PerfLabScrollDriver(scrollView: scrollView, segments: segments, wheelSign: wheelSign, eventTarget: eventTarget)
        self.scrollView = scrollView
        self.processMonitor = processMonitor
        self.sampleInterval = sampleInterval
        self.sampler = sampler
    }

    public func run(completion: @escaping ([String: Double]) -> Void) {
        self.completion = completion
        self.startSnapshot = self.processMonitor.snapshot()
        self.startUnixTime = Date().timeIntervalSince1970
        self.startOffset = self.scrollView.contentView.bounds.minY
        self.minOffset = self.startOffset
        self.maxOffset = self.startOffset
        self.clock.onFrame = { [weak self] timestamp in
            self?.frame(timestamp: timestamp)
        }
        self.clock.start()
    }

    private func frame(timestamp: Double) {
        let offset = self.scrollView.contentView.bounds.minY
        self.minOffset = min(self.minOffset, offset)
        self.maxOffset = max(self.maxOffset, offset)
        self.frameIndex += 1
        if let sampler = self.sampler, self.frameIndex % self.sampleInterval == 0 {
            for (key, value) in sampler() {
                self.sampleSums[key, default: 0] += value
            }
            self.sampleCount += 1
        }
        if !self.driver.step(timestamp: timestamp) {
            self.finish()
        }
    }

    private func finish() {
        self.clock.stop()
        self.clock.onFrame = nil
        guard let startSnapshot = self.startSnapshot, let completion = self.completion else {
            return
        }
        self.completion = nil
        let endSnapshot = self.processMonitor.snapshot()
        let stats = self.clock.stats
        let duration = endSnapshot.time - startSnapshot.time
        var result: [String: Double] = [
            "duration": duration,
            "frames": Double(stats.frames),
            "frameDurationMs": stats.frameDuration * 1000.0,
            "hitches": Double(stats.hitches),
            "hitchesOver33ms": Double(stats.longHitches),
            "hitchTimeMs": stats.hitchTime * 1000.0,
            "hitchTimePercent": duration > 0 ? stats.hitchTime / duration * 100.0 : 0,
            "worstGapMs": stats.worstGap * 1000.0,
            "cpuSeconds": endSnapshot.cpuTime - startSnapshot.cpuTime,
            "cpuCores": duration > 0 ? (endSnapshot.cpuTime - startSnapshot.cpuTime) / duration : 0,
            "mainThreadBusyPercent": duration > 0 ? (endSnapshot.mainThreadCpuTime - startSnapshot.mainThreadCpuTime) / duration * 100.0 : 0,
            "footprintStartMB": Double(startSnapshot.footprint) / 1048576.0,
            "footprintEndMB": Double(endSnapshot.footprint) / 1048576.0,
            "requestedScrollDistance": self.driver.requestedDistance,
            "scrolledRange": Double(self.maxOffset - self.minOffset),
            "endOffsetDelta": Double(self.scrollView.contentView.bounds.minY - self.startOffset),
            "startUnixTime": self.startUnixTime,
            "endUnixTime": Date().timeIntervalSince1970
        ]
        if self.sampleCount > 0 {
            for (key, sum) in self.sampleSums {
                result["avg_" + key] = sum / Double(self.sampleCount)
            }
        }
        completion(result)
    }
}
#endif
