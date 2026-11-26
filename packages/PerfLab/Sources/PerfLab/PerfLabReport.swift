#if DEBUG
import Foundation

public final class PerfLabReport {
    private let configuration: PerfLabConfiguration
    private var entries: [[String: Any]] = []
    private let startedAt = Date()

    public init(configuration: PerfLabConfiguration) {
        self.configuration = configuration
    }

    public func add(scenario: String, run: Int, metrics: [String: Double], notes: [String: String] = [:]) {
        var entry: [String: Any] = ["scenario": scenario, "run": run]
        var roundedMetrics: [String: Double] = [:]
        for (key, value) in metrics {
            roundedMetrics[key] = (value * 1000).rounded() / 1000
        }
        entry["metrics"] = roundedMetrics
        if !notes.isEmpty {
            entry["notes"] = notes
        }
        self.entries.append(entry)
        if let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]), let string = String(data: data, encoding: .utf8) {
            NSLog("PerfLab %@", string)
        }
    }

    @discardableResult
    public func write() -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "\(self.configuration.lab)-\(self.configuration.label)-\(formatter.string(from: self.startedAt)).json"
        let document: [String: Any] = [
            "lab": self.configuration.lab,
            "label": self.configuration.label,
            "startedAt": ISO8601DateFormatter().string(from: self.startedAt),
            "arguments": self.configuration.arguments,
            "entries": self.entries
        ]
        try? FileManager.default.createDirectory(at: self.configuration.outputDirectory, withIntermediateDirectories: true)
        let url = self.configuration.outputDirectory.appendingPathComponent(name)
        guard let data = try? JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        try? data.write(to: url)
        return url
    }
}
#endif
