import XCTest
import TelegramMediaUtils

final class CallDeviceSelectionTests: XCTestCase {
    private let builtIn = CaptureDeviceCandidate(uniqueID: "BuiltInMicrophoneDevice", isAvailable: true)
    private let usb = CaptureDeviceCandidate(uniqueID: "USBMic", isAvailable: true)
    private let suspendedUsb = CaptureDeviceCandidate(uniqueID: "USBMic", isAvailable: false)

    func testSelectedAvailableMicrophoneWins() {
        XCTAssertEqual(DevicesContext.resolveCaptureDeviceId(selectedId: "USBMic", candidates: [builtIn, usb], defaultId: "BuiltInMicrophoneDevice"), "USBMic")
    }

    func testDefaultUsedWhenNothingSelected() {
        XCTAssertEqual(DevicesContext.resolveCaptureDeviceId(selectedId: nil, candidates: [builtIn, usb], defaultId: "BuiltInMicrophoneDevice"), "BuiltInMicrophoneDevice")
    }

    func testDefaultUsedWhenSelectedMicrophoneUnplugged() {
        XCTAssertEqual(DevicesContext.resolveCaptureDeviceId(selectedId: "USBMic", candidates: [builtIn], defaultId: "BuiltInMicrophoneDevice"), "BuiltInMicrophoneDevice")
    }

    func testDefaultUsedWhenSelectedMicrophoneSuspended() {
        XCTAssertEqual(DevicesContext.resolveCaptureDeviceId(selectedId: "USBMic", candidates: [builtIn, suspendedUsb], defaultId: "BuiltInMicrophoneDevice"), "BuiltInMicrophoneDevice")
    }

    func testNoMicrophoneAtAll() {
        XCTAssertNil(DevicesContext.resolveCaptureDeviceId(selectedId: "USBMic", candidates: [], defaultId: nil))
        XCTAssertNil(DevicesContext.resolveCaptureDeviceId(selectedId: nil, candidates: [], defaultId: nil))
    }

    func testSelectedOutputWinsOnlyWhenPresent() {
        XCTAssertEqual(DevicesContext.resolveOutputDeviceId(selectedId: "Headphones", available: ["Speakers", "Headphones"], defaultId: "Speakers"), "Headphones")
        XCTAssertEqual(DevicesContext.resolveOutputDeviceId(selectedId: "Headphones", available: ["Speakers"], defaultId: "Speakers"), "Speakers")
        XCTAssertEqual(DevicesContext.resolveOutputDeviceId(selectedId: nil, available: ["Speakers", "Headphones"], defaultId: "Speakers"), "Speakers")
        XCTAssertNil(DevicesContext.resolveOutputDeviceId(selectedId: "Headphones", available: [], defaultId: nil))
    }
}

final class DevicesChangeTrackerTests: XCTestCase {
    private func assertUpdate(_ update: DevicesUpdate, camera: String?, input: String?, output: String?, sampleUpdateIndex: Int?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(update.camera, camera, "camera", file: file, line: line)
        XCTAssertEqual(update.input, input, "input", file: file, line: line)
        XCTAssertEqual(update.output, output, "output", file: file, line: line)
        XCTAssertEqual(update.sampleUpdateIndex, sampleUpdateIndex, "sampleUpdateIndex", file: file, line: line)
    }

    func testFirstUpdateReportsEverything() {
        var tracker = DevicesChangeTracker()
        assertUpdate(tracker.update(camera: "cam", input: "mic", output: "spk", sampleIndex: 0), camera: "cam", input: "mic", output: "spk", sampleUpdateIndex: 0)
    }

    func testRepeatedUpdateReportsNothing() {
        var tracker = DevicesChangeTracker()
        _ = tracker.update(camera: "cam", input: "mic", output: "spk", sampleIndex: 0)
        assertUpdate(tracker.update(camera: "cam", input: "mic", output: "spk", sampleIndex: 0), camera: nil, input: nil, output: nil, sampleUpdateIndex: nil)
    }

    func testMicrophoneSwitchReportsOnlyInput() {
        var tracker = DevicesChangeTracker()
        _ = tracker.update(camera: "cam", input: "mic", output: "spk", sampleIndex: 0)
        assertUpdate(tracker.update(camera: "cam", input: "usb", output: "spk", sampleIndex: 0), camera: nil, input: "usb", output: nil, sampleUpdateIndex: nil)
        assertUpdate(tracker.update(camera: "cam", input: "usb", output: "spk", sampleIndex: 0), camera: nil, input: nil, output: nil, sampleUpdateIndex: nil)
        assertUpdate(tracker.update(camera: "cam", input: "mic", output: "spk", sampleIndex: 0), camera: nil, input: "mic", output: nil, sampleUpdateIndex: nil)
    }

    func testOutputSwitchReportsOnlyOutput() {
        var tracker = DevicesChangeTracker()
        _ = tracker.update(camera: "cam", input: "mic", output: "spk", sampleIndex: 0)
        assertUpdate(tracker.update(camera: "cam", input: "mic", output: "headphones", sampleIndex: 0), camera: nil, input: nil, output: "headphones", sampleUpdateIndex: nil)
    }

    func testCameraSwitchReportsOnlyCamera() {
        var tracker = DevicesChangeTracker()
        _ = tracker.update(camera: "cam", input: "mic", output: "spk", sampleIndex: 0)
        assertUpdate(tracker.update(camera: "external", input: "mic", output: "spk", sampleIndex: 0), camera: "external", input: nil, output: nil, sampleUpdateIndex: nil)
    }

    func testSampleRateChangeReappliesAudioDevices() {
        var tracker = DevicesChangeTracker()
        _ = tracker.update(camera: "cam", input: "mic", output: "spk", sampleIndex: 0)
        assertUpdate(tracker.update(camera: "cam", input: "mic", output: "spk", sampleIndex: 1), camera: nil, input: "mic", output: "spk", sampleUpdateIndex: 1)
        assertUpdate(tracker.update(camera: "cam", input: "mic", output: "spk", sampleIndex: 1), camera: nil, input: nil, output: nil, sampleUpdateIndex: nil)
        assertUpdate(tracker.update(camera: "cam", input: "mic", output: "spk", sampleIndex: 2), camera: nil, input: "mic", output: "spk", sampleUpdateIndex: 2)
    }

    func testMicrophoneRemovedReportsNoSwitch() {
        var tracker = DevicesChangeTracker()
        _ = tracker.update(camera: nil, input: "usb", output: "spk", sampleIndex: 0)
        assertUpdate(tracker.update(camera: nil, input: nil, output: "spk", sampleIndex: 0), camera: nil, input: nil, output: nil, sampleUpdateIndex: nil)
        assertUpdate(tracker.update(camera: nil, input: "usb", output: "spk", sampleIndex: 0), camera: nil, input: "usb", output: nil, sampleUpdateIndex: nil)
    }

    func testUnplugFallsBackToDefaultMicrophoneEndToEnd() {
        var tracker = DevicesChangeTracker()
        let builtIn = CaptureDeviceCandidate(uniqueID: "BuiltIn", isAvailable: true)
        let usb = CaptureDeviceCandidate(uniqueID: "USB", isAvailable: true)
        let plugged = DevicesContext.resolveCaptureDeviceId(selectedId: "USB", candidates: [builtIn, usb], defaultId: "BuiltIn")
        XCTAssertEqual(tracker.update(camera: nil, input: plugged, output: "spk", sampleIndex: 0).input, "USB")
        let unplugged = DevicesContext.resolveCaptureDeviceId(selectedId: "USB", candidates: [builtIn], defaultId: "BuiltIn")
        XCTAssertEqual(tracker.update(camera: nil, input: unplugged, output: "spk", sampleIndex: 0).input, "BuiltIn")
        let replugged = DevicesContext.resolveCaptureDeviceId(selectedId: "USB", candidates: [builtIn, usb], defaultId: "BuiltIn")
        XCTAssertEqual(tracker.update(camera: nil, input: replugged, output: "spk", sampleIndex: 0).input, "USB")
    }
}
