import Cocoa
import Darwin

final class MainBusyMeter {
    private var observer: CFRunLoopObserver?
    private var busySince: CFTimeInterval?
    private(set) var busyTotal: CFTimeInterval = 0
    private(set) var commitTotal: CFTimeInterval = 0
    private var commitStart: CFTimeInterval?
    private var commitObservers: [CFRunLoopObserver] = []

    init() {
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.entry.rawValue, true, Int.min) { [weak self] _, activity in
            guard let self else { return }
            let now = CACurrentMediaTime()
            if activity == .beforeWaiting {
                if let since = self.busySince {
                    self.busyTotal += now - since
                    self.busySince = nil
                }
            } else if self.busySince == nil {
                self.busySince = now
            }
        }
        self.observer = observer
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        let before = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.exit.rawValue, true, 1999999) { [weak self] _, _ in
            self?.commitStart = CACurrentMediaTime()
        }
        let after = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.exit.rawValue, true, 2000001) { [weak self] _, _ in
            guard let self, let start = self.commitStart else { return }
            self.commitTotal += CACurrentMediaTime() - start
            self.commitStart = nil
        }
        for o in [before!, after!] {
            CFRunLoopAddObserver(CFRunLoopGetMain(), o, .commonModes)
            commitObservers.append(o)
        }
    }

    var busyNow: CFTimeInterval {
        return busyTotal + (busySince.map { CACurrentMediaTime() - $0 } ?? 0)
    }

    deinit {
        if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
    }
}

struct ProcessSample {
    var footprint: UInt64 = 0
    var resident: UInt64 = 0
    var threads = 0

    static func now() -> ProcessSample {
        var sample = ProcessSample()
        var vm = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        if withUnsafeMutablePointer(to: &vm, { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }) == KERN_SUCCESS {
            sample.footprint = vm.phys_footprint
            sample.resident = vm.resident_size
        }
        var list: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        if task_threads(mach_task_self_, &list, &threadCount) == KERN_SUCCESS, let list {
            for i in 0..<Int(threadCount) { mach_port_deallocate(mach_task_self_, list[i]) }
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: list)), vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride))
            sample.threads = Int(threadCount)
        }
        return sample
    }
}

struct FramePhase {
    let name: String
    var frames = 0
    var dropped = 0
    var busyMs: [Double] = []
    var cpuStart = 0.0
    var cpuEnd = 0.0
    var start: CFTimeInterval = 0
    var end: CFTimeInterval = 0
    var peakFootprint: UInt64 = 0
    var peakResident: UInt64 = 0
    var peakThreads = 0
    var peakLive = 0
    var peakTileBytes = 0
    var worstGapMs = 0.0
    var hitchMs = 0.0

    init(name: String) {
        self.name = name
    }

    var cpuPercent: Double {
        return (cpuEnd - cpuStart) / max(0.001, end - start) * 100
    }

    func line() -> String {
        let sorted = busyMs.sorted()
        let avg = busyMs.reduce(0, +) / Double(max(1, busyMs.count))
        let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        let seconds = max(0.001, end - start)
        return String(format: "%@: %.1fs frames=%d dropped=%d (%.1f%%) worstGap=%.1fms main avg=%.2f p95=%.2f max=%.2f ms cpu=%.0f%% footprint=%.0fMB rss=%.0fMB threads=%d live=%d tiles=%.0fMB",
                      name, seconds, frames, dropped, Double(dropped) / Double(max(1, frames + dropped)) * 100, worstGapMs, avg, p95, sorted.last ?? 0, cpuPercent, Double(peakFootprint) / 1048576, Double(peakResident) / 1048576, peakThreads, peakLive, Double(peakTileBytes) / 1048576)
    }
}

func feedCPUSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
}

func feedSavePNG(_ image: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}
