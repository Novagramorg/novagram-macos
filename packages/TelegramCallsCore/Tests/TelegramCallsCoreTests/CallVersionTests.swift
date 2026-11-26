import XCTest
@testable import TelegramCallsCore

final class CallVersionTests: XCTestCase {
    private let knownVersions: Set<String> = ["2.7.7", "5.0.0", "7.0.0", "8.0.0", "9.0.0", "10.0.0", "11.0.0", "12.0.0", "13.0.0"]

    func testRegisteredVersionsAreKnown() {
        let versions = Set(OngoingCallContext.versions(includeExperimental: true, includeReference: true).map { $0.version })
        XCTAssertEqual(versions, knownVersions, "tgcalls changed its versions: check whether new implementations honor mediaDevicesConfig and update referenceImplementationVersions")
    }

    func testReferenceVersionsAreRegistered() {
        let versions = Set(OngoingCallContext.versions(includeExperimental: true, includeReference: true).map { $0.version })
        XCTAssertTrue(OngoingCallContext.referenceImplementationVersions.isSubset(of: versions))
    }

    func testOnlyReferenceVersionsIgnoreInitialDevices() {
        XCTAssertTrue(OngoingCallContext.ignoresInitialAudioDevices(version: "10.0.0"))
        XCTAssertTrue(OngoingCallContext.ignoresInitialAudioDevices(version: "11.0.0"))
        for version in knownVersions.subtracting(["10.0.0", "11.0.0"]) {
            XCTAssertFalse(OngoingCallContext.ignoresInitialAudioDevices(version: version), version)
        }
        XCTAssertFalse(OngoingCallContext.ignoresInitialAudioDevices(version: ""))
        XCTAssertFalse(OngoingCallContext.ignoresInitialAudioDevices(version: "unknown"))
    }

    func testEveryVersionSupportsVideo() {
        for entry in OngoingCallContext.versions(includeExperimental: true, includeReference: true) {
            XCTAssertTrue(entry.supportsVideo, entry.version)
        }
    }
}

final class CallLogsCleanupTests: XCTestCase {
    private func file(_ name: String, _ age: TimeInterval) -> (URL, Date) {
        return (URL(fileURLWithPath: "/tmp/calls/\(name)"), Date(timeIntervalSince1970: 1_000_000 - age))
    }

    func testNothingRemovedAtOrBelowLimit() {
        XCTAssertEqual(callLogsToRemove([], limit: 20), [])
        let files = (0 ..< 20).map { file("\($0)", TimeInterval($0)) }
        XCTAssertEqual(callLogsToRemove(files, limit: 20), [])
    }

    func testRemovesOldestAboveLimit() {
        let files = [file("new", 1), file("oldest", 100), file("mid", 50), file("older", 70)]
        XCTAssertEqual(callLogsToRemove(files, limit: 2).map { $0.lastPathComponent }, ["oldest", "older"])
    }

    func testRemovesEverythingAboveLimitAtOnce() {
        let files = (0 ..< 45).map { file("\($0)", TimeInterval($0)) }
        let removed = callLogsToRemove(files, limit: 20)
        XCTAssertEqual(removed.count, 25)
        XCTAssertEqual(Set(removed.map { $0.lastPathComponent }), Set((20 ..< 45).map { "\($0)" }))
    }

    func testZeroLimitRemovesAll() {
        let files = [file("a", 1), file("b", 2)]
        XCTAssertEqual(Set(callLogsToRemove(files, limit: 0).map { $0.lastPathComponent }), ["a", "b"])
    }
}
