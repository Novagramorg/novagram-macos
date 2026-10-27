//
//  NovagramAdsGate.swift
//  Telegram-Mac
//
//  Hidden admin toggle "Remove all ads" (iOS Feature #6, same UserDefaults keys and semantics):
//
//    UserDefaults(suiteName: "pro_messager")
//      "fenix_show_ads"             Bool, default true  — false = "Remove all ads" is ON
//      "fenix_ads_section_revealed" Bool, default false — the hidden row is visible
//
//  ON  = no Novagram and no Telegram ads anywhere (chat/channel, bot panel, search, chat-list banner,
//        video player). OFF = ads as usual.
//  Trigger (like iOS): hold the version row at the bottom of Settings (AccountViewController) for
//  NovagramDeveloperSection.revealDuration (20 s), then release. Revealing asks for the developer login
//  + password (NovagramAdsAdminAuth) and opens Novagram Settings, where the toggle shows in the Developer
//  section with the other Developer switches (NovagramDeveloperFlags); hiding it again needs no
//  password. No deep link reaches it.
//
//  Consumers: every Novagram ad source gates on `enabledSignal` live (NovagramAdsCenter.gated), and
//  ChatController skips Telegram's ChatAdData when `showAds` is false at chat open.
//

import Cocoa
import TGUIKit
import SwiftSignalKit
import NovagramCore

final class NovagramAdsGate {
    struct UIState: Equatable {
        var revealed: Bool
        var showAds: Bool
    }

    private static let defaults = UserDefaults(suiteName: "pro_messager")
    private static let showAdsKey = "fenix_show_ads"
    private static let revealedKey = "fenix_ads_section_revealed"

    // In-memory source of truth, seeded once from the persisted defaults (after the one-time migration
    // that re-enables ads hidden by the old password-less egg). The UI is always driven from memory,
    // never from a re-read: a sandboxed suite's read can lag its own write (cfprefsd).
    private static var memoRevealed: Bool = {
        NovagramAdsAdminAuth.migrateLegacyRevealIfNeeded()
        return defaults?.object(forKey: revealedKey) as? Bool ?? false
    }()
    private static var memoShowAds: Bool = {
        NovagramAdsAdminAuth.migrateLegacyRevealIfNeeded()
        return defaults?.object(forKey: showAdsKey) as? Bool ?? true
    }()

    // Drives the Settings list rebuild (combined into AccountViewController's signal) and the ad gates.
    static let uiState: ValuePromise<UIState> = ValuePromise(NovagramAdsGate.currentState(), ignoreRepeated: true)

    private static func currentState() -> UIState {
        return UIState(revealed: memoRevealed, showAds: memoShowAds)
    }

    /// False while "Remove all ads" is on. Read by ChatController when a chat opens.
    static var showAds: Bool {
        return memoShowAds
    }

    /// Current value, then every change ("Remove all ads" flipped).
    static var enabledSignal: Signal<Bool, NoError> {
        return uiState.get()
        |> map { $0.showAds }
        |> distinctUntilChanged
    }

    /// The Developer section row's title ("Remove all ads"; the switch is ON when `showAds` is false).
    static var toggleTitle: String {
        return NovagramL10n.current.ads_removeAll_title
    }

    static func setShowAds(_ value: Bool) {
        memoShowAds = value
        defaults?.set(value, forKey: showAdsKey)
        uiState.set(currentState())
    }

    private static var isPrompting = false

    /// The version row was released. After a hold of `NovagramDeveloperSection.revealDuration` this
    /// toggles the Developer section and returns true, so Settings skips copying the version string;
    /// `onUnlocked` runs after a successful developer login (not when the section is hidden again).
    @discardableResult
    static func handleVersionRelease(window: Window, onUnlocked: (() -> Void)? = nil) -> Bool {
        guard NovagramDeveloperSection.currentPressDuration >= NovagramDeveloperSection.revealDuration else {
            return false
        }
        guard !isPrompting else {
            return true
        }
        // Hiding the section again is always allowed; revealing it needs the developer login.
        if memoRevealed {
            setRevealed(false, window: window)
            return true
        }
        isPrompting = true
        NovagramAdsAdminAuth.presentPrompt(window: window) { granted in
            isPrompting = false
            if granted {
                setRevealed(true, window: window)
                onUnlocked?()
            }
        }
        return true
    }

    private static func setRevealed(_ revealed: Bool, window: Window) {
        memoRevealed = revealed
        defaults?.set(revealed, forKey: revealedKey)
        uiState.set(currentState())
        let strings = NovagramL10n.current
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        alert(for: window, info: revealed ? strings.developer_shownAlert(path: strings.developer_settingsPath) : strings.developer_hiddenAlert)
    }
}
