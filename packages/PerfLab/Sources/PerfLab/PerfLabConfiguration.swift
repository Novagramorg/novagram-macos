#if DEBUG
import Foundation

public struct PerfLabConfiguration {
    public let lab: String
    public let scenarios: [String]
    public let runs: Int
    public let label: String
    public let outputDirectory: URL
    public let quitWhenDone: Bool
    public let arguments: [String: String]

    public static func fromLaunchArguments(defaultOutputDirectory: URL) -> PerfLabConfiguration? {
        let arguments = ProcessInfo.processInfo.arguments
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("-PerfLab"), index + 1 < arguments.count, !arguments[index + 1].hasPrefix("-PerfLab") {
                values[argument] = arguments[index + 1]
                index += 2
            } else {
                if argument.hasPrefix("-PerfLab") {
                    values[argument] = ""
                }
                index += 1
            }
        }
        guard let lab = values["-PerfLab"], !lab.isEmpty else {
            return nil
        }
        let scenarios = (values["-PerfLabScenarios"] ?? "warm").split(separator: ",").map { String($0) }
        let runs = Int(values["-PerfLabRuns"] ?? "") ?? 1
        let label = values["-PerfLabLabel"] ?? "run"
        let outputDirectory = values["-PerfLabOutput"].map { URL(fileURLWithPath: $0) } ?? defaultOutputDirectory
        let quitWhenDone = values["-PerfLabQuit"] != nil
        return PerfLabConfiguration(lab: lab, scenarios: scenarios, runs: max(1, runs), label: label, outputDirectory: outputDirectory, quitWhenDone: quitWhenDone, arguments: values)
    }

    public init(lab: String, scenarios: [String], runs: Int, label: String, outputDirectory: URL, quitWhenDone: Bool, arguments: [String: String]) {
        self.lab = lab
        self.scenarios = scenarios
        self.runs = runs
        self.label = label
        self.outputDirectory = outputDirectory
        self.quitWhenDone = quitWhenDone
        self.arguments = arguments
    }

    public func double(_ name: String, _ defaultValue: Double) -> Double {
        return self.arguments[name].flatMap(Double.init) ?? defaultValue
    }

    public func string(_ name: String, _ defaultValue: String) -> String {
        return self.arguments[name] ?? defaultValue
    }
}
#endif
