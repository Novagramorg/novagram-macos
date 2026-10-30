import Foundation

public enum NovagramJobMode: String, Codable, CaseIterable {
    case findJob
    case findCandidates
}

public enum NovagramJobPostKind: String, Codable {
    case vacancy
    case resume
    case unknown
}

public enum NovagramJobWorkFormat: String, Codable, CaseIterable {
    case office
    case remote
    case hybrid
}

public enum NovagramJobEmployment: String, Codable, CaseIterable {
    case fullTime
    case partTime
}

public enum NovagramJobCurrency: String, Codable {
    case usd
    case uzs
    case rub
    case eur
}

public struct NovagramJobSalary: Equatable {
    public var text: String
    public var min: Double?
    public var max: Double?
    public var currency: NovagramJobCurrency?
    public var isNegotiable: Bool

    public init(text: String, min: Double? = nil, max: Double? = nil, currency: NovagramJobCurrency? = nil, isNegotiable: Bool = false) {
        self.text = text
        self.min = min
        self.max = max
        self.currency = currency
        self.isNegotiable = isNegotiable
    }
}

public struct NovagramJobCity: Equatable, Hashable {
    public let id: String
    public let en: String
    public let uz: String
    public let ru: String
    public let variants: [String]

    public init(id: String, en: String, uz: String, ru: String, variants: [String]) {
        self.id = id
        self.en = en
        self.uz = uz
        self.ru = ru
        self.variants = variants
    }

    public func title(languageCode: String) -> String {
        switch languageCode {
        case "uz":
            return uz
        case "ru":
            return ru
        default:
            return en
        }
    }
}

public enum NovagramJobContact: Equatable, Hashable {
    case username(String)
    case phone(String)
    case email(String)
    case link(String)
}

public struct NovagramJobPostInfo: Equatable {
    public var kind: NovagramJobPostKind
    public var title: String?
    public var salary: NovagramJobSalary?
    public var cityIds: [String]
    public var formats: Set<NovagramJobWorkFormat>
    public var employment: Set<NovagramJobEmployment>
    public var experienceYears: Int?
    public var contacts: [NovagramJobContact]

    public init(kind: NovagramJobPostKind = .unknown, title: String? = nil, salary: NovagramJobSalary? = nil, cityIds: [String] = [], formats: Set<NovagramJobWorkFormat> = [], employment: Set<NovagramJobEmployment> = [], experienceYears: Int? = nil, contacts: [NovagramJobContact] = []) {
        self.kind = kind
        self.title = title
        self.salary = salary
        self.cityIds = cityIds
        self.formats = formats
        self.employment = employment
        self.experienceYears = experienceYears
        self.contacts = contacts
    }
}

public enum NovagramJobPeriod: String, Codable, CaseIterable {
    case day
    case week
    case month
    case any

    public func minDate(now: Int32) -> Int32? {
        switch self {
        case .day:
            return now - 24 * 60 * 60
        case .week:
            return now - 7 * 24 * 60 * 60
        case .month:
            return now - 30 * 24 * 60 * 60
        case .any:
            return nil
        }
    }
}

public struct NovagramJobFilter: Equatable, Codable {
    public var mode: NovagramJobMode
    public var query: String
    public var cityIds: Set<String>
    public var formats: Set<NovagramJobWorkFormat>
    public var period: NovagramJobPeriod
    public var onlyWithSalary: Bool
    public var languages: Set<NovagramSearchLanguage>
    public var jobHashtags: [String]?
    public var candidateHashtags: [String]?

    public static let maxHashtags = 12
    public static let maxHashtagLength = 32

    public init(mode: NovagramJobMode = .findJob, query: String = "", cityIds: Set<String> = [], formats: Set<NovagramJobWorkFormat> = [], period: NovagramJobPeriod = .week, onlyWithSalary: Bool = false, languages: Set<NovagramSearchLanguage> = NovagramSearchLanguage.all, jobHashtags: [String]? = nil, candidateHashtags: [String]? = nil) {
        self.mode = mode
        self.query = query
        self.cityIds = cityIds
        self.formats = formats
        self.period = period
        self.onlyWithSalary = onlyWithSalary
        self.languages = languages
        self.jobHashtags = jobHashtags.map(NovagramJobFilter.normalizedHashtags)
        self.candidateHashtags = candidateHashtags.map(NovagramJobFilter.normalizedHashtags)
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case query
        case cityIds
        case formats
        case period
        case onlyWithSalary
        case languages
        case jobHashtags
        case candidateHashtags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mode = try container.decodeIfPresent(NovagramJobMode.self, forKey: .mode) ?? .findJob
        self.query = try container.decodeIfPresent(String.self, forKey: .query) ?? ""
        self.cityIds = try container.decodeIfPresent(Set<String>.self, forKey: .cityIds) ?? []
        self.formats = try container.decodeIfPresent(Set<NovagramJobWorkFormat>.self, forKey: .formats) ?? []
        self.period = try container.decodeIfPresent(NovagramJobPeriod.self, forKey: .period) ?? .week
        self.onlyWithSalary = try container.decodeIfPresent(Bool.self, forKey: .onlyWithSalary) ?? false
        self.languages = try container.decodeIfPresent(Set<NovagramSearchLanguage>.self, forKey: .languages) ?? NovagramSearchLanguage.all
        self.jobHashtags = try container.decodeIfPresent([String].self, forKey: .jobHashtags).map(NovagramJobFilter.normalizedHashtags)
        self.candidateHashtags = try container.decodeIfPresent([String].self, forKey: .candidateHashtags).map(NovagramJobFilter.normalizedHashtags)
    }

    public func hashtags(for mode: NovagramJobMode) -> [String] {
        let custom = mode == .findJob ? jobHashtags : candidateHashtags
        return custom ?? NovagramJobPresets.hashtags(for: mode)
    }

    public func hasCustomHashtags(for mode: NovagramJobMode) -> Bool {
        return hashtags(for: mode) != NovagramJobPresets.hashtags(for: mode)
    }

    public mutating func setHashtags(_ tags: [String]?, for mode: NovagramJobMode) {
        let value = tags.map(NovagramJobFilter.normalizedHashtags)
        switch mode {
        case .findJob:
            jobHashtags = value
        case .findCandidates:
            candidateHashtags = value
        }
    }

    public static func normalizedHashtag(_ raw: String) -> String? {
        let stripped = raw.filter { $0 != "#" && !$0.isWhitespace }
        guard !stripped.isEmpty, stripped.count <= maxHashtagLength, stripped.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            return nil
        }
        return stripped
    }

    public static func normalizedHashtags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            guard result.count < maxHashtags, let clean = normalizedHashtag(tag), seen.insert(clean.lowercased()).inserted else {
                continue
            }
            result.append(clean)
        }
        return result
    }

    public func accepts(text: String, info: NovagramJobPostInfo, date: Int32, now: Int32, query: NovagramJobQuery) -> Bool {
        if let minDate = period.minDate(now: now), date < minDate {
            return false
        }
        switch mode {
        case .findJob:
            if info.kind != .vacancy {
                return false
            }
        case .findCandidates:
            if info.kind != .resume {
                return false
            }
        }
        if !cityIds.isEmpty && !info.cityIds.isEmpty && cityIds.isDisjoint(with: info.cityIds) {
            return false
        }
        if !formats.isEmpty && !info.formats.isEmpty && formats.isDisjoint(with: info.formats) {
            return false
        }
        if onlyWithSalary && info.salary?.min == nil && info.salary?.max == nil {
            return false
        }
        return query.matches(text)
    }
}

public struct NovagramJobAccount: Equatable {
    public let peerId: Int64
    public let recordId: Int64

    public init(peerId: Int64, recordId: Int64) {
        self.peerId = peerId
        self.recordId = recordId
    }
}

public struct NovagramJobSavedSearch: Equatable, Codable {
    public var id: String
    public var title: String
    public var filter: NovagramJobFilter
    public var alertsEnabled: Bool
    public var lastSeenDate: Int32

    public init(id: String = UUID().uuidString, title: String, filter: NovagramJobFilter, alertsEnabled: Bool = false, lastSeenDate: Int32 = 0) {
        self.id = id
        self.title = title
        self.filter = filter
        self.alertsEnabled = alertsEnabled
        self.lastSeenDate = lastSeenDate
    }
}
