import XCTest
import CrashRecoveryUI
import CrashSignalMarkerTestSupport

private func engineOwnsThread(_ name: String) -> Bool {
    return name.hasPrefix("mtproto-")
}

private func engineOwnsQueue(_ label: String) -> Bool {
    return label.hasPrefix("org.telegram.MTProtoRust.")
}

private func legacyCrashedOnLaunch(_ contents: String) -> Bool {
    let components = contents.split(whereSeparator: { $0 == " " || $0 == "\n" })
    guard components.count >= 2, let elapsed = Double(components[1]) else {
        return false
    }
    return elapsed < 15
}

final class CrashMarkerTests: XCTestCase {
    private var folder: String!

    private var markerPath: String {
        return folder + "/crashhandler-signal"
    }

    override func setUp() {
        super.setUp()
        folder = NSTemporaryDirectory() + "CrashMarkerTests-" + UUID().uuidString
        try! FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: nil)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: folder)
        super.tearDown()
    }

    private func crash(thread: String, queue: String = "", bundleVersion: String = "283288", signal: Int32 = SIGABRT, file: StaticString = #filePath, line: UInt = #line) -> CrashMarker? {
        let status = crashOnThreadInChildProcess(markerPath, bundleVersion, thread, queue, signal)
        XCTAssertEqual(status, 0, file: file, line: line)
        return readCrashMarker(folder: folder)
    }

    private func engineCrash(_ marker: CrashMarker) -> CrashedRun? {
        return marker.crashedRun(onThread: engineOwnsThread, orQueue: engineOwnsQueue)
    }

    private func write(_ contents: String) {
        try! contents.write(toFile: markerPath, atomically: true, encoding: .utf8)
    }

    func testEngineThreadAbortRoundTrip() throws {
        let before = Int32(Date().timeIntervalSince1970)
        let marker = try XCTUnwrap(crash(thread: "mtproto-worker-2"))
        let after = Int32(Date().timeIntervalSince1970)
        XCTAssertEqual(marker.signal, SIGABRT)
        XCTAssertLessThanOrEqual(marker.elapsed, 1)
        XCTAssertEqual(marker.bundleVersion, "283288")
        XCTAssertEqual(marker.threadName, "mtproto-worker-2")
        XCTAssertNotNil(marker.queueLabel)
        XCTAssertFalse(engineOwnsQueue(marker.queueLabel ?? ""))
        XCTAssertTrue(marker.isInstantCrash)
        XCTAssertGreaterThanOrEqual(marker.timestamp, before - 1)
        XCTAssertLessThanOrEqual(marker.timestamp, after + 1)
        XCTAssertEqual(engineCrash(marker), CrashedRun(bundleVersion: "283288", timestamp: marker.timestamp))
    }

    func testWrittenFormat() throws {
        _ = crash(thread: "mtproto-main", queue: "org.telegram.MTProtoRust.session", signal: SIGSEGV)
        let contents = try String(contentsOfFile: markerPath, encoding: .utf8)
        XCTAssertTrue(["11 0\n", "11 1\n"].contains(where: { contents.hasPrefix($0) }), contents)
        XCTAssertTrue(contents.hasSuffix("\nbundle 283288\nqueue org.telegram.MTProtoRust.session\nthread mtproto-main\n"), contents)
        XCTAssertEqual(contents.split(separator: "\n", omittingEmptySubsequences: false).count, 5)
    }

    func testEngineFaultIsReported() throws {
        let marker = try XCTUnwrap(crash(thread: "mtproto-resolver", signal: SIGBUS))
        XCTAssertEqual(marker.signal, SIGBUS)
        XCTAssertEqual(marker.threadName, "mtproto-resolver")
        XCTAssertNotNil(engineCrash(marker))
    }

    func testCrashOnEngineQueueOfUnnamedThread() throws {
        let marker = try XCTUnwrap(crash(thread: "", queue: "org.telegram.MTProtoRust.streams"))
        XCTAssertNil(marker.threadName)
        XCTAssertEqual(marker.queueLabel, "org.telegram.MTProtoRust.streams")
        XCTAssertEqual(engineCrash(marker), CrashedRun(bundleVersion: "283288", timestamp: marker.timestamp))
    }

    func testCrashOnOtherQueue() throws {
        let marker = try XCTUnwrap(crash(thread: "", queue: "org.telegram.Telegram.trace"))
        XCTAssertEqual(marker.queueLabel, "org.telegram.Telegram.trace")
        XCTAssertNil(engineCrash(marker))
    }

    func testUnnamedThread() throws {
        let marker = try XCTUnwrap(crash(thread: ""))
        XCTAssertEqual(marker.bundleVersion, "283288")
        XCTAssertNil(marker.threadName)
        XCTAssertNil(engineCrash(marker))
    }

    func testOtherThread() throws {
        let marker = try XCTUnwrap(crash(thread: "com.apple.NSURLConnectionLoader"))
        XCTAssertEqual(marker.threadName, "com.apple.NSURLConnectionLoader")
        XCTAssertNil(engineCrash(marker))
    }

    func testThreadNameKeepsSpaces() throws {
        let marker = try XCTUnwrap(crash(thread: "mtproto- worker 1", queue: "org.telegram.MTProtoRust. carrier 2"))
        XCTAssertEqual(marker.threadName, "mtproto- worker 1")
        XCTAssertEqual(marker.queueLabel, "org.telegram.MTProtoRust. carrier 2")
    }

    func testControlAndNonASCIIBytesAreReplaced() throws {
        let marker = try XCTUnwrap(crash(thread: "mtproto-\nworker-\u{e9}", queue: "org.telegram.MTProtoRust.\u{e9}\nx", bundleVersion: "28\n3288"))
        XCTAssertEqual(marker.threadName, "mtproto-?worker-??")
        XCTAssertEqual(marker.queueLabel, "org.telegram.MTProtoRust.???x")
        XCTAssertEqual(marker.bundleVersion, "28?3288")
        let data = try XCTUnwrap(FileManager.default.contents(atPath: markerPath))
        XCTAssertTrue(data.allSatisfy { $0 == 0x0a || (0x20...0x7e).contains($0) })
    }

    func testLongQueueLabelIsCut() throws {
        let label = "org.telegram.MTProtoRust." + String(repeating: "q", count: 600)
        let marker = try XCTUnwrap(crash(thread: "mtproto-main", queue: label))
        let written = try XCTUnwrap(marker.queueLabel)
        XCTAssertTrue(label.hasPrefix(written))
        XCTAssertGreaterThan(written.count, 300)
        XCTAssertEqual(marker.threadName, "mtproto-main")
        XCTAssertEqual(marker.bundleVersion, "283288")
    }

    private func crashWithCorruptQueueSlot(aborts: Bool, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let start = Date()
        let status = crashWithCorruptQueueSlotInChildProcess(markerPath, "283288", aborts ? 1 : 0)
        XCTAssertEqual(status, 100 + SIGSEGV, "the nested fault reaches the previous SIGSEGV action instead of hanging until the alarm", file: file, line: line)
        XCTAssertLessThan(Date().timeIntervalSince(start), 9, file: file, line: line)
        return try String(contentsOfFile: markerPath, encoding: .utf8)
    }

    func testFaultReadingTheQueueLabelKeepsHeaderAndDies() throws {
        let contents = try crashWithCorruptQueueSlot(aborts: false)
        XCTAssertTrue(["11 0\nbundle 283288\n", "11 1\nbundle 283288\n"].contains(contents), contents)
        let marker = try XCTUnwrap(readCrashMarker(folder: folder))
        XCTAssertEqual(marker.signal, SIGSEGV)
        XCTAssertEqual(marker.bundleVersion, "283288")
        XCTAssertNil(marker.queueLabel)
        XCTAssertNil(marker.threadName)
    }

    func testFaultReadingTheQueueLabelDuringAbortKeepsHeaderAndDies() throws {
        let contents = try crashWithCorruptQueueSlot(aborts: true)
        XCTAssertTrue(["6 0\nbundle 283288\n", "6 1\nbundle 283288\n"].contains(contents), contents)
        XCTAssertEqual(readCrashMarker(folder: folder)?.signal, SIGABRT)
    }

    func testEmptyBundleVersion() throws {
        let marker = try XCTUnwrap(crash(thread: "mtproto-worker-0", queue: "org.telegram.MTProtoRust.session", bundleVersion: ""))
        XCTAssertNil(marker.bundleVersion)
        XCTAssertNil(engineCrash(marker))
    }

    func testLegacyReaderStillReadsNewMarker() throws {
        _ = crash(thread: "mtproto-worker-1", queue: "org.telegram.MTProtoRust.carrier")
        XCTAssertTrue(legacyCrashedOnLaunch(try String(contentsOfFile: markerPath, encoding: .utf8)))
        write("6 42\nbundle 283288\nqueue org.telegram.MTProtoRust.carrier\nthread mtproto-worker-1\n")
        XCTAssertFalse(legacyCrashedOnLaunch(try String(contentsOfFile: markerPath, encoding: .utf8)))
    }

    func testLegacyMarker() throws {
        write("6 3\n")
        let marker = try XCTUnwrap(readCrashMarker(folder: folder))
        XCTAssertEqual(marker.signal, 6)
        XCTAssertEqual(marker.elapsed, 3)
        XCTAssertNil(marker.bundleVersion)
        XCTAssertNil(marker.queueLabel)
        XCTAssertNil(marker.threadName)
        XCTAssertTrue(marker.isInstantCrash)
        XCTAssertNil(marker.crashedRun(onThread: { _ in true }, orQueue: { _ in true }))
    }

    func testMarkerWithoutQueueLine() throws {
        write("6 3\nbundle 283288\nthread mtproto-worker-1\n")
        let marker = try XCTUnwrap(readCrashMarker(folder: folder))
        XCTAssertNil(marker.queueLabel)
        XCTAssertEqual(engineCrash(marker)?.bundleVersion, "283288")
    }

    func testMarkerWithoutThreadLine() throws {
        write("6 3\nbundle 283288\nqueue org.telegram.MTProtoRust.network\n")
        let marker = try XCTUnwrap(readCrashMarker(folder: folder))
        XCTAssertNil(marker.threadName)
        XCTAssertEqual(engineCrash(marker)?.bundleVersion, "283288")
        write("6 3\nbundle 283288\nqueue com.apple.root.default-qos\n")
        XCTAssertNil(engineCrash(try XCTUnwrap(readCrashMarker(folder: folder))))
    }

    func testEngineCrashCountsOutsideInstantWindow() throws {
        write("6 3600\nbundle 283288\nqueue com.apple.root.default-qos\nthread mtproto-worker-3\n")
        let marker = try XCTUnwrap(readCrashMarker(folder: folder))
        XCTAssertFalse(marker.isInstantCrash)
        XCTAssertEqual(engineCrash(marker)?.bundleVersion, "283288")
        write("6 3600\nbundle 283288\nqueue org.telegram.MTProtoRust.session\nthread \n")
        XCTAssertEqual(engineCrash(try XCTUnwrap(readCrashMarker(folder: folder)))?.bundleVersion, "283288")
    }

    func testUnknownLinesAreIgnored() throws {
        write("11 1\nfuture value\nthread mtproto-main\nqueue org.telegram.MTProtoRust.streams\nbundle 283290\n")
        let marker = try XCTUnwrap(readCrashMarker(folder: folder))
        XCTAssertEqual(marker.bundleVersion, "283290")
        XCTAssertEqual(marker.queueLabel, "org.telegram.MTProtoRust.streams")
        XCTAssertEqual(marker.threadName, "mtproto-main")
    }

    func testTimestampIsMarkerModificationDate() throws {
        write("6 3\nbundle 283288\nqueue com.apple.main-thread\nthread mtproto-main\n")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)], ofItemAtPath: markerPath)
        let marker = try XCTUnwrap(readCrashMarker(folder: folder))
        XCTAssertEqual(marker.timestamp, 1_700_000_000)
        XCTAssertEqual(engineCrash(marker), CrashedRun(bundleVersion: "283288", timestamp: 1_700_000_000))
    }

    func testMissingAndMalformedMarkers() {
        XCTAssertNil(readCrashMarker(folder: folder))
        write("")
        XCTAssertNil(readCrashMarker(folder: folder))
        write("6\n")
        XCTAssertNil(readCrashMarker(folder: folder))
        write("abort 3\n")
        XCTAssertNil(readCrashMarker(folder: folder))
    }

    func testClearCrashMarker() {
        write("6 3\n")
        clearCrashMarker(folder: folder)
        XCTAssertNil(readCrashMarker(folder: folder))
    }
}
