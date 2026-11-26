import XCTest
import Darwin
@testable import TelegramMedia

final class AudioRendererIdleStopTests: XCTestCase {
    private func usage() -> (wakeups: UInt64, cpu: Double) {
        var info = task_power_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_power_info>.size / MemoryLayout<natural_t>.size)
        _ = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_POWER_INFO), $0, &count)
            }
        }
        var rusage = rusage_info_current()
        _ = withUnsafeMutablePointer(to: &rusage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, $0)
            }
        }
        return (info.task_interrupt_wakeups + info.task_platform_idle_wakeups, Double(rusage.ri_user_time + rusage.ri_system_time) / 1e9)
    }

    private func wait(_ seconds: Double) {
        let done = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            done.fulfill()
        }
        self.wait(for: [done], timeout: seconds + 5)
    }

    private func isRunning(_ renderer: MediaPlayerAudioRenderer) -> Bool {
        let done = expectation(description: "running")
        var result = false
        renderer.isOutputRunning { value in
            result = value
            done.fulfill()
        }
        self.wait(for: [done], timeout: 5)
        return result
    }

    private func measure(_ seconds: Double) -> (wakeupsPerSecond: Double, cpuPercent: Double) {
        let start = self.usage()
        self.wait(seconds)
        let end = self.usage()
        return (Double(end.wakeups - start.wakeups) / seconds, (end.cpu - start.cpu) / seconds * 100)
    }

    func testPausedRendererStopsTheOutputAfterTheGracePeriod() throws {
        let renderer = MediaPlayerAudioRenderer(playAndRecord: false, forceAudioToSpeaker: false, baseRate: 1.0, volume: 0.0, updatedRate: {}, audioPaused: {})
        renderer.start()
        renderer.setRate(1.0)
        self.wait(0.5)
        try XCTSkipUnless(self.isRunning(renderer), "no audio output device")

        renderer.setRate(0.0)
        self.wait(0.2)
        XCTAssertTrue(self.isRunning(renderer))
        let paused = self.measure(2.0)

        self.wait(1.5)
        XCTAssertFalse(self.isRunning(renderer))
        let stopped = self.measure(2.0)

        renderer.setRate(1.0)
        self.wait(0.3)
        XCTAssertTrue(self.isRunning(renderer))
        renderer.stop()
        self.wait(0.2)

        print(String(format: "AudioRendererIdleStop: paused with output running %.0f wakeups/s %.2f%% CPU, after idle stop %.0f wakeups/s %.2f%% CPU", paused.wakeupsPerSecond, paused.cpuPercent, stopped.wakeupsPerSecond, stopped.cpuPercent))
    }
}
