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
//  Trigger: 10 quick clicks (≤ 0.7 s apart) on the version row at the bottom of Settings
//  (AccountViewController). Revealing the toggle then asks for the admin login + password
//  (NovagramAdsAdminAuth) and opens Novagram Settings, where the toggle shows in its own section
//  while revealed (NovagramSettingsController); hiding it again needs no password. No deep link reaches it.
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

    /// The hidden row's title and tip ("Remove all ads"; the switch is ON when `showAds` is false).
    static var toggleTitle: String {
        return NovagramL10n.current.ads_removeAll_title
    }

    static var toggleTip: String {
        return NovagramL10n.current.ads_removeAll_tip
    }

    static func setShowAds(_ value: Bool) {
        memoShowAds = value
        defaults?.set(value, forKey: showAdsKey)
        uiState.set(currentState())
    }

    // 10 quick clicks on the version row (iOS uses the same count/window).
    private static let requiredClicks = 10
    private static let clickWindow: Double = 0.7
    private static var lastClickTimestamp: Double = 0
    private static var clickCount: Int = 0
    private static var isPrompting = false

    /// `onUnlocked` runs after a successful admin login (not when the toggle is hidden again).
    // Returns true when the click belongs to a fast series (2nd click on), so the caller skips its own
    // single-click action (Settings copies the version string).
    @discardableResult
    static func handleVersionClick(window: Window, onUnlocked: (() -> Void)? = nil) -> Bool {
        let timestamp = CACurrentMediaTime()
        if timestamp - lastClickTimestamp > clickWindow {
            clickCount = 0
        }
        lastClickTimestamp = timestamp
        clickCount += 1
        guard clickCount >= requiredClicks, !isPrompting else {
            return clickCount > 1 || isPrompting
        }
        clickCount = 0

        // Hiding the row again is always allowed; revealing it needs the admin login.
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
        alert(for: window, info: revealed ? strings.ads_section_shown : strings.ads_section_hidden)
    }
}
