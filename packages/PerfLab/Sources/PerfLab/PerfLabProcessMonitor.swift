#if DEBUG
import Foundation
import Darwin

public struct PerfLabProcessSnapshot {
    public let time: Double
    public let cpuTime: Double
    public let mainThreadCpuTime: Double
    public let footprint: UInt64
}

public final class PerfLabProcessMonitor {
    private let mainThread: thread_act_t

    public init() {
        precondition(Thread.isMainThread)
        self.mainThread = mach_thread_self()
    }

    public func snapshot() -> PerfLabProcessSnapshot {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpuTime = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000.0 + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000.0

        var threadInfo = thread_basic_info()
        var threadInfoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size)
        let threadResult = withUnsafeMutablePointer(to: &threadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(threadInfoCount)) {
                thread_info(self.mainThread, thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
            }
        }
        var mainThreadCpuTime = 0.0
        if threadResult == KERN_SUCCESS {
            mainThreadCpuTime = Double(threadInfo.user_time.seconds) + Double(threadInfo.user_time.microseconds) / 1_000_000.0 + Double(threadInfo.system_time.seconds) + Double(threadInfo.system_time.microseconds) / 1_000_000.0
        }

        var vmInfo = task_vm_info_data_t()
        var vmInfoCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmInfoCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmInfoCount)
            }
        }
        let footprint = vmResult == KERN_SUCCESS ? UInt64(vmInfo.phys_footprint) : 0

        return PerfLabProcessSnapshot(time: CFAbsoluteTimeGetCurrent(), cpuTime: cpuTime, mainThreadCpuTime: mainThreadCpuTime, footprint: footprint)
    }
}
#endif
