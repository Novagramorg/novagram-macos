import Foundation
import NovagramServices

// Bridge from the analytics manager's completion API to the NovagramServices SDK.
//
// The Novagram Statistics API base URL and its x-api-key live ONLY inside the SDK binary
// (packages/NovagramCore/Frameworks). This public repo holds no value: never add the URL or the
// key back here.
//
// The server dedups by `device_id`, so every call is idempotent: sending one twice with the
// same id does not count twice. The SDK sends one request per call and never retries.
// Completions arrive on a background thread.
public final class NovagramStatisticsClient {
    public static let shared = NovagramStatisticsClient()

    private let statistics: StatisticsAPI

    private init() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        self.statistics = ServicesClient(configuration: ServicesConfiguration(
            timeout: 15.0,
            userAgent: "Novagram-macOS/\(version)"
        )).statistics
    }

    // false in a build whose SDK carries no Statistics values: then nothing is sent.
    public var isConfigured: Bool {
        return self.statistics.isConfigured
    }

    // POST /v1/install. completion gets false on any failure (network, HTTP, decoding).
    public func registerInstall(deviceId: String, completion: @escaping (Bool) -> Void) {
        let statistics = self.statistics
        Task {
            completion((try? await statistics.registerInstall(deviceID: deviceId)) != nil)
        }
    }

    // POST /v1/account/create.
    public func registerAccount(deviceId: String, completion: @escaping (Bool) -> Void) {
        let statistics = self.statistics
        Task {
            completion((try? await statistics.registerAccount(deviceID: deviceId)) != nil)
        }
    }

    // POST /v1/account/delete. Deletes nothing in Telegram; it only updates the counter.
    public func deleteAccount(deviceId: String, completion: @escaping (Bool) -> Void) {
        let statistics = self.statistics
        Task {
            completion((try? await statistics.deleteAccount(deviceID: deviceId)) != nil)
        }
    }

    // GET /v1/stats. completion gets (downloads, active), or nil on failure.
    public func fetchStats(completion: @escaping ((downloads: Int, active: Int)?) -> Void) {
        let statistics = self.statistics
        Task {
            let counts = try? await statistics.counts()
            completion(counts.map { ($0.downloads, $0.active) })
        }
    }
}
