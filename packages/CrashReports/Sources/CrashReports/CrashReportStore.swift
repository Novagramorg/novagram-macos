import Foundation
import SwiftSignalKit

public let crashReportsBotUsername = "macos_stable_updater_bot"

public struct CrashReport: Equatable {
    public let url: URL
    public let date: Date
    public let incidentId: String
    public let appVersion: String
    public let buildVersion: String
}

public final class CrashReportStore {
    private static let rescanDelays: [Double] = [0, 15, 45, 120, 300]
    private static let maxReports = 5

    private let directory: URL
    private let executablePath: String
    private let anonymizedExecutablePath: String
    private let processName: String
    private let handledKey: String
    private let defaults: UserDefaults
    private let queue = Queue(name: "org.telegram.crashReports")
    private let reportsPromise = ValuePromise<[CrashReport]>([], ignoreRepeated: true)
    private var started = false

    public init(handledKey: String, directory: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/DiagnosticReports"), executablePath: String = Bundle.main.executablePath ?? "", homeDirectory: String = NSHomeDirectory(), defaults: UserDefaults = .standard, now: Date = Date()) {
        self.directory = directory
        self.executablePath = executablePath
        if !homeDirectory.isEmpty, executablePath.hasPrefix(homeDirectory + "/") {
            self.anonymizedExecutablePath = "/Users/USER" + executablePath.dropFirst(homeDirectory.count)
        } else {
            self.anonymizedExecutablePath = executablePath
        }
        self.processName = URL(fileURLWithPath: executablePath).lastPathComponent
        self.handledKey = handledKey
        self.defaults = defaults
        if defaults.object(forKey: handledKey) == nil {
            defaults.set(now.timeIntervalSince1970, forKey: handledKey)
        }
    }

    public var reports: Signal<[CrashReport], NoError> {
        self.queue.async {
            guard !self.started else {
                return
            }
            self.started = true
            for delay in CrashReportStore.rescanDelays {
                self.queue.after(delay, { [weak self] in
                    self?.rescan()
                })
            }
        }
        return self.reportsPromise.get()
    }

    public func markHandled(_ reports: [CrashReport]) {
        guard let newest = reports.map({ $0.date }).max() else {
            return
        }
        self.queue.async {
            let handled = self.defaults.double(forKey: self.handledKey)
            self.defaults.set(max(handled, newest.timeIntervalSince1970), forKey: self.handledKey)
            self.rescan()
        }
    }

    public func rescan() {
        self.reportsPromise.set(self.scan())
    }

    public func scan() -> [CrashReport] {
        let handled = self.defaults.double(forKey: self.handledKey)
        guard let contents = try? FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var reports: [CrashReport] = []
        for url in contents where url.pathExtension == "ips" && url.lastPathComponent.hasPrefix(self.processName + "-") {
            guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, date.timeIntervalSince1970 > handled else {
                continue
            }
            if let report = self.parse(url: url, date: date) {
                reports.append(report)
            }
        }
        reports.sort(by: { $0.date > $1.date })
        return Array(reports.prefix(CrashReportStore.maxReports))
    }

    private func parse(url: URL, date: Date) -> CrashReport? {
        guard let data = try? Data(contentsOf: url), let newline = data.firstIndex(of: UInt8(ascii: "\n")) else {
            return nil
        }
        guard let header = (try? JSONSerialization.jsonObject(with: data[data.startIndex ..< newline])) as? [String: Any], header["bug_type"] as? String == "309" else {
            return nil
        }
        guard let body = (try? JSONSerialization.jsonObject(with: data[data.index(after: newline)...])) as? [String: Any], let procPath = body["procPath"] as? String else {
            return nil
        }
        guard procPath == self.executablePath || procPath == self.anonymizedExecutablePath else {
            return nil
        }
        return CrashReport(url: url, date: date, incidentId: header["incident_id"] as? String ?? url.lastPathComponent, appVersion: header["app_version"] as? String ?? "", buildVersion: header["build_version"] as? String ?? "")
    }
}
