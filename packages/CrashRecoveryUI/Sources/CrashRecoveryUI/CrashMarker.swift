import Foundation
import CrashSignalMarker

private let instantCrashInterval: Double = 15

private func crashMarkerPath(_ folder: String) -> String {
    return folder + "/" + "crashhandler-signal"
}

public struct CrashMarker: Equatable {
    public let signal: Int32
    public let elapsed: Double
    public let bundleVersion: String?
    public let queueLabel: String?
    public let threadName: String?
    public let timestamp: Int32

    public var isInstantCrash: Bool {
        return elapsed < instantCrashInterval
    }

    public func crashedRun(onThread ownsThread: (String) -> Bool, orQueue ownsQueue: (String) -> Bool) -> CrashedRun? {
        guard let bundleVersion = self.bundleVersion else {
            return nil
        }
        let onThread = self.threadName.map(ownsThread) ?? false
        let onQueue = self.queueLabel.map(ownsQueue) ?? false
        guard onThread || onQueue else {
            return nil
        }
        return CrashedRun(bundleVersion: bundleVersion, timestamp: self.timestamp)
    }
}

public struct CrashedRun: Equatable {
    public let bundleVersion: String
    public let timestamp: Int32

    public init(bundleVersion: String, timestamp: Int32) {
        self.bundleVersion = bundleVersion
        self.timestamp = timestamp
    }
}

public func armCrashMarker(folder: String) {
    armCrashSignalMarker(crashMarkerPath(folder), Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")
}

public func disarmCrashMarker() {
    disarmCrashSignalMarker()
}

public func readCrashMarker(folder: String) -> CrashMarker? {
    let path = crashMarkerPath(folder)
    guard let data = FileManager.default.contents(atPath: path) else {
        return nil
    }
    let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date ?? Date()
    return parseCrashMarker(String(decoding: data, as: UTF8.self), timestamp: Int32(clamping: Int64(modified.timeIntervalSince1970)))
}

private func parseCrashMarker(_ contents: String, timestamp: Int32) -> CrashMarker? {
    let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
    guard let first = lines.first else {
        return nil
    }
    let header = first.split(separator: " ")
    guard header.count >= 2, let signal = Int32(header[0]), let elapsed = Double(header[1]) else {
        return nil
    }
    var bundleVersion: String?
    var queueLabel: String?
    var threadName: String?
    for line in lines.dropFirst() {
        if let value = crashMarkerValue(line, key: "bundle") {
            bundleVersion = value
        } else if let value = crashMarkerValue(line, key: "queue") {
            queueLabel = value
        } else if let value = crashMarkerValue(line, key: "thread") {
            threadName = value
        }
    }
    return CrashMarker(signal: signal, elapsed: elapsed, bundleVersion: bundleVersion, queueLabel: queueLabel, threadName: threadName, timestamp: timestamp)
}

private func crashMarkerValue(_ line: Substring, key: String) -> String? {
    let prefix = key + " "
    guard line.hasPrefix(prefix) else {
        return nil
    }
    let value = String(line.dropFirst(prefix.count))
    return value.isEmpty ? nil : value
}

public func clearCrashMarker(folder: String) {
    try? FileManager.default.removeItem(atPath: folder + "/" + "crashhandler")
    try? FileManager.default.removeItem(atPath: crashMarkerPath(folder))
}
