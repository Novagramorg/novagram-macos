import XCTest
@testable import CrashReports

final class CrashReportStoreTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName = ""
    private let home = "/Users/tester"
    private let executable = "/Users/tester/Applications/Telegram.app/Contents/MacOS/Telegram"
    private let key = "crashReports.handled.test"

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CrashReportStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "CrashReportStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func store(now: Date) -> CrashReportStore {
        return CrashReportStore(handledKey: key, directory: directory, executablePath: executable, homeDirectory: home, defaults: defaults, now: now)
    }

    @discardableResult
    private func writeReport(name: String, procPath: String, bugType: String = "309", incident: String = UUID().uuidString, date: Date) throws -> URL {
        let header: [String: Any] = ["app_name": "Telegram", "app_version": "12.10", "build_version": "283256", "bug_type": bugType, "incident_id": incident]
        let body: [String: Any] = ["procPath": procPath, "threads": [], "usedImages": []]
        var data = try JSONSerialization.data(withJSONObject: header)
        data.append(UInt8(ascii: "\n"))
        data.append(try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted]))
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        return url
    }

    func testOnlyThisAppsCrashesAfterInstallationAreReported() throws {
        let installed = Date(timeIntervalSince1970: 1_000_000)
        let store = store(now: installed)
        try writeReport(name: "Telegram-old.ips", procPath: executable, date: installed.addingTimeInterval(-60))
        let anonymized = try writeReport(name: "Telegram-anonymized.ips", procPath: "/Users/USER/Applications/Telegram.app/Contents/MacOS/Telegram", incident: "A", date: installed.addingTimeInterval(10))
        let exact = try writeReport(name: "Telegram-exact.ips", procPath: executable, incident: "B", date: installed.addingTimeInterval(20))
        try writeReport(name: "Telegram-other-channel.ips", procPath: "/Applications/Telegram.app/Contents/MacOS/Telegram", date: installed.addingTimeInterval(30))
        try writeReport(name: "Telegram-hang.ips", procPath: executable, bugType: "288", date: installed.addingTimeInterval(40))
        try writeReport(name: "Other-app.ips", procPath: executable, date: installed.addingTimeInterval(50))
        try "not json".write(to: directory.appendingPathComponent("Telegram-broken.ips"), atomically: true, encoding: .utf8)

        let reports = store.scan()
        XCTAssertEqual(reports.map { $0.url.lastPathComponent }, [exact.lastPathComponent, anonymized.lastPathComponent])
        XCTAssertEqual(reports.map { $0.incidentId }, ["B", "A"])
        XCTAssertEqual(reports.first?.buildVersion, "283256")
    }

    func testHandledReportsDisappearAndNewerOnesShowAgain() throws {
        let installed = Date(timeIntervalSince1970: 2_000_000)
        let store = store(now: installed)
        try writeReport(name: "Telegram-1.ips", procPath: executable, date: installed.addingTimeInterval(10))
        let first = store.scan()
        XCTAssertEqual(first.count, 1)
        store.markHandled(first)
        let handled = expectation(description: "handled")
        _ = store.reports.start(next: { reports in
            if reports.isEmpty {
                handled.fulfill()
            }
        })
        wait(for: [handled], timeout: 5)
        XCTAssertTrue(store.scan().isEmpty)

        try writeReport(name: "Telegram-2.ips", procPath: executable, date: installed.addingTimeInterval(100))
        XCTAssertEqual(store.scan().map { $0.url.lastPathComponent }, ["Telegram-2.ips"])
    }

    func testTheHandledMarkIsKeptAcrossLaunches() throws {
        let installed = Date(timeIntervalSince1970: 3_000_000)
        try writeReport(name: "Telegram-1.ips", procPath: executable, date: installed.addingTimeInterval(10))
        XCTAssertEqual(store(now: installed).scan().count, 1)
        XCTAssertEqual(store(now: installed.addingTimeInterval(1000)).scan().count, 1)
    }

    func testAtMostFiveNewestReportsAreReturned() throws {
        let installed = Date(timeIntervalSince1970: 4_000_000)
        let store = store(now: installed)
        for index in 0 ..< 8 {
            try writeReport(name: "Telegram-\(index).ips", procPath: executable, date: installed.addingTimeInterval(Double(index + 1)))
        }
        XCTAssertEqual(store.scan().map { $0.url.lastPathComponent }, ["Telegram-7.ips", "Telegram-6.ips", "Telegram-5.ips", "Telegram-4.ips", "Telegram-3.ips"])
    }

    func testAMissingDirectoryGivesNoReports() {
        let store = CrashReportStore(handledKey: key, directory: directory.appendingPathComponent("missing"), executablePath: executable, homeDirectory: home, defaults: defaults)
        XCTAssertTrue(store.scan().isEmpty)
    }
}
