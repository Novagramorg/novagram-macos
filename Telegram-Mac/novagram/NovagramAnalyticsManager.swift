import Foundation
import Security
import SwiftSignalKit
import Postbox
import TelegramCore
import NovagramCore

// Drives the two analytics counters of the Novagram Statistics API (through the NovagramServices
// SDK, see NovagramStatisticsClient in NovagramCore):
//   • "Novagram users"   — devices that ever installed the app (downloads).
//   • "Active accounts"  — devices that hold at least one signed-in account (active).
//
// The server counts DEVICES by `device_id` and dedups, so every call is idempotent. When to call:
//   • POST /v1/install         — the first open after install; on success "sent" is saved in
//                                UserDefaults (a reinstall sends it again: the server ignores a
//                                known device id).
//   • POST /v1/account/create  — every account that is added and has loaded (first login, every
//                                Add Account).
//   • POST /v1/account/delete  — every logout the user confirms (see accountWillLogOut). The
//                                server then drops the whole device from "active", so if other
//                                accounts stay signed in, /v1/account/create is sent again right after.
//   • Every emission of the account list also reconciles with the `deviceActive` flag: it repairs
//     a call that failed offline and a session that was ended from another device.
//
// The device id is a random UUID in the macOS KEYCHAIN (survives app deletion + reinstall, so a
// reinstall is never counted as a new device), with a UserDefaults fallback for the rare case
// where the Keychain is unavailable. Do not change its service/account names: every existing
// device would be counted again.
//
// Port of submodules/Fenixuz/Analytics/Sources/FenixuzAnalyticsManager.swift (iOS).
final class NovagramAnalyticsManager {
    static let shared = NovagramAnalyticsManager()

    private let stateQueue = DispatchQueue(label: "uz.fenixuz.app.Analytics.state")
    private let keychainService = "uz.fenixuz.app.Analytics"

    private let deviceIdKey = "deviceId"
    private let deviceActiveKey = "deviceActive"
    private let installRegisteredDefaultsKey = "uz.fenixuz.app.Analytics.installRegistered"

    // UserDefaults fallback (used only when the Keychain read/write fails).
    private let fallbackDefaults = UserDefaults(suiteName: "uz.fenixuz.app.Analytics")

    private var accountsDisposable: Disposable?
    private var started = false
    // stateQueue only. nil until the first emission of the account list after launch.
    private var knownAccountIds: Set<AccountRecordId>?

    private init() {}

    deinit {
        self.accountsDisposable?.dispose()
    }

    // Called once from AppDelegate after the shared account context is ready.
    func start(sharedContext: SharedAccountContext) {
        self.stateQueue.async { [weak self] in
            self?.registerInstallIfNeeded()
        }
        if !self.started {
            self.started = true
            self.observeAccounts(sharedContext: sharedContext)
        }
    }

    // MARK: - Install (downloads, the first open after install)

    private func registerInstallIfNeeded() {
        guard NovagramStatisticsClient.shared.isConfigured else {
            return
        }
        if UserDefaults.standard.bool(forKey: self.installRegisteredDefaultsKey) {
            return
        }
        let deviceId = self.deviceId()
        NovagramStatisticsClient.shared.registerInstall(deviceId: deviceId, completion: { [weak self] success in
            guard let self = self, success else {
                // Not saved: the next open tries again.
                return
            }
            UserDefaults.standard.set(true, forKey: self.installRegisteredDefaultsKey)
        })
    }

    // MARK: - Accounts (active)

    private func observeAccounts(sharedContext: SharedAccountContext) {
        self.accountsDisposable = (sharedContext.activeAccounts
        |> deliverOnMainQueue).start(next: { [weak self] value in
            guard let self = self else {
                return
            }
            let accountIds = Set(value.accounts.map { $0.0 })
            self.stateQueue.async {
                self.accountsChanged(accountIds)
            }
        })
    }

    // Runs on stateQueue.
    private func accountsChanged(_ accountIds: Set<AccountRecordId>) {
        let previous = self.knownAccountIds
        self.knownAccountIds = accountIds
        guard NovagramStatisticsClient.shared.isConfigured else {
            return
        }
        // Accounts that appear after the first emission were added and have loaded.
        let added = previous.map { accountIds.subtracting($0) } ?? []
        let isActive = self.readState(key: self.deviceActiveKey) == "1"
        if !added.isEmpty {
            for _ in added {
                self.sendRegisterAccount()
            }
        } else if !accountIds.isEmpty && !isActive {
            // Reconcile: accounts are here but the server may not count the device (a failed
            // call, or an app version that never sent it).
            self.sendRegisterAccount()
        } else if accountIds.isEmpty && isActive {
            // Reconcile: no account left without a confirmed logout (for example the session was
            // ended from another device), or the logout's delete failed.
            self.sendDeleteAccount(thenRegisterAgain: false)
        }
    }

    // Call when the user confirms a logout, before the account is removed (installed as
    // NovagramHooks.accountWillLogOut). Sends /v1/account/delete, then /v1/account/create again
    // if other accounts stay signed in.
    func accountWillLogOut(accountId: AccountRecordId) {
        self.stateQueue.async {
            guard NovagramStatisticsClient.shared.isConfigured else {
                return
            }
            let remaining = (self.knownAccountIds ?? []).subtracting([accountId])
            self.sendDeleteAccount(thenRegisterAgain: !remaining.isEmpty)
        }
    }

    // Runs on stateQueue. The flag changes only after a successful call, so a failed one is
    // repaired by the reconcile step on a later emission or launch.
    private func sendRegisterAccount() {
        NovagramStatisticsClient.shared.registerAccount(deviceId: self.deviceId(), completion: { [weak self] success in
            guard let self = self, success else {
                return
            }
            self.stateQueue.async {
                self.writeState("1", key: self.deviceActiveKey)
            }
        })
    }

    // Runs on stateQueue. The two calls run one after the other, never in parallel.
    private func sendDeleteAccount(thenRegisterAgain: Bool) {
        NovagramStatisticsClient.shared.deleteAccount(deviceId: self.deviceId(), completion: { [weak self] success in
            guard let self = self else {
                return
            }
            self.stateQueue.async {
                if success {
                    self.writeState("0", key: self.deviceActiveKey)
                }
                if thenRegisterAgain {
                    self.sendRegisterAccount()
                }
            }
        })
    }

    // MARK: - Reading the counts for the UI

    func counts() -> Signal<(devices: Int?, accounts: Int?), NoError> {
        return Signal { subscriber in
            NovagramStatisticsClient.shared.fetchStats(completion: { result in
                if let result = result {
                    subscriber.putNext((result.downloads, result.active))
                } else {
                    subscriber.putNext((nil, nil))
                }
                subscriber.putCompletion()
            })
            return EmptyDisposable
        }
    }

    // MARK: - Device id (Keychain — survives reinstall on the same device)

    private func deviceId() -> String {
        if let existing = self.readState(key: self.deviceIdKey) {
            return existing
        }
        let generated = UUID().uuidString
        self.writeState(generated, key: self.deviceIdKey)
        return generated
    }

    // MARK: - State plumbing (Keychain primary, UserDefaults fallback)

    private func readState(key: String) -> String? {
        if let value = self.readKeychain(key: key) {
            return value
        }
        return self.fallbackDefaults?.string(forKey: key)
    }

    private func writeState(_ value: String, key: String) {
        if self.writeKeychain(value, key: key) {
            return
        }
        self.fallbackDefaults?.set(value, forKey: key)
    }

    // MARK: - Keychain plumbing

    private func baseQuery(key: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.keychainService,
            kSecAttrAccount as String: key
        ]
    }

    private func readKeychain(key: String) -> String? {
        var query = self.baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    // Returns true on success, false if the Keychain rejected the write (caller falls back).
    @discardableResult
    private func writeKeychain(_ value: String, key: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            return false
        }
        let updateQuery = self.baseQuery(key: key)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        if SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary) == errSecSuccess {
            return true
        }
        var addQuery = self.baseQuery(key: key)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }
}
