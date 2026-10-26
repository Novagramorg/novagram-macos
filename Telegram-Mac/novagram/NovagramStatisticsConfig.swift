import Foundation

// Novagram Analytics — Novagram Statistics API (REST) configuration.
//
// Port of submodules/Novagram/Analytics/Sources/NovagramAnalyticsConfig.swift (iOS).
// Backend: REMOVED (FastAPI). Dedup happens SERVER-SIDE by
// `device_id`, so the client just fires simple idempotent calls and never owns a counter.
// Foundation-only on purpose (no Telegram / SwiftSignalKit deps).
enum NovagramAnalyticsConfig {
    // Base URL, NO trailing slash.
    static let baseURL: String = "REMOVED"

    // x-api-key header value. The server enforces this on /install, /account/* and /stats —
    // a request without it gets HTTP 401. Not a high-value secret (at most it lets someone
    // inflate public counters), so it lives here the same way the demo-login endpoint does.
    static let apiKey: String = "REMOVED"

    // Endpoint paths (relative to baseURL).
    static let installPath: String = "/v1/install"               // downloads +1 (per device)
    static let accountCreatePath: String = "/v1/account/create"  // active +1
    static let accountDeletePath: String = "/v1/account/delete"  // active -1
    static let statsPath: String = "/v1/stats"                   // { downloads, active }

    static var isConfigured: Bool {
        return !baseURL.isEmpty && !apiKey.isEmpty
    }
}
