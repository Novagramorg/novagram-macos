import Foundation

enum NovagramJobChannelRelevance {
    static let maxDiscoveryQueries = 6
    static let queryJobWords = ["vakansiya", "ish", "вакансия"]
    static let jobSignals = ["vakansiya", "vakansiyalar", "ishbor", "ish bor", "ish e'lon", "job", "jobs", "hr", "hiring", "career", "работа", "вакансии", "вакансия"]
    private static let shortSignalLength = 3
    private static let apostrophes: [Character] = ["ʻ", "ʼ", "’", "‘", "`", "´"]

    static func discoveryQueries(userQuery: String?) -> [String] {
        var queries: [String] = []
        let trimmed = userQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            queries += queryJobWords.map { "\(trimmed) \($0)" }
        }
        queries += NovagramJobPresets.channelDiscoveryQueries
        var seen = Set<String>()
        let unique = queries.filter { seen.insert($0.lowercased()).inserted }
        return Array(unique.prefix(maxDiscoveryQueries))
    }

    static func hasJobSignal(title: String, username: String?) -> Bool {
        let text = normalized(title)
        let name = normalized(username ?? "")
        let tokens = Set((text + " " + name).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        for signal in jobSignals {
            if signal.contains(" ") || signal.contains("'") {
                if text.contains(signal) {
                    return true
                }
            } else if signal.count <= shortSignalLength {
                if tokens.contains(signal) || (signal == "job" && name.contains(signal)) {
                    return true
                }
            } else if text.contains(signal) || name.contains(signal) {
                return true
            }
        }
        return false
    }

    private static func normalized(_ text: String) -> String {
        let unified = String(text.lowercased().map { apostrophes.contains($0) ? "'" : $0 })
        return unified.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
