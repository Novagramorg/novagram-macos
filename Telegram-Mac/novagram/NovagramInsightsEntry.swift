//
//  NovagramInsightsEntry.swift
//  Telegram-Mac
//
//  Entry to the "Ads Analytics" screen (NovagramInsights / NovagramInsightsUI binary frameworks).
//
//  What lives here:
//    - the hidden toggle: 20 quick clicks (each within 1.5 s of the previous) on the "Novagram Settings" row
//      show the row; another 20 hide it again. The choice is kept across launches (UserDefaults).
//    - the visibility rule of the Settings row: macOS 13+ AND the toggle is on
//    - the configuration (same environment as the ads code, per-account
//      keychain key, app language and accent) and the separate "Ads Analytics" window
//
//  Telegram-owned hooks are in AccountViewController.swift (see NOVAGRAM_HOOKS.md).
//

import Cocoa
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramCore
import Localization
import NovagramAds
import NovagramInsights
import NovagramInsightsUI

enum NovagramInsightsEntry {
    private static let windowTitle = "Ads Analytics"
    private static let windowAutosaveName = "FenixInsightsWindow"
    private static let defaultContentSize = NSSize(width: 1100, height: 750)
    private static let minimumContentSize = NSSize(width: 800, height: 560)

    // Kept across launches, so the row stays until it is hidden again with the same 20 clicks.
    private static let revealedDefaultsKey = "fenix_insights_row_revealed"
    private static var revealed: Bool {
        get { UserDefaults.standard.bool(forKey: revealedDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: revealedDefaultsKey) }
    }
    private static let changeCounter = Atomic<Int>(value: 0)
    private static let changes = ValuePromise<Int>(0, ignoreRepeated: true)

    // Click counting for the reveal (main thread only).
    private static var clickCounter = SettingsRowClickCounter()
    private static var window: NSWindow?
    private static var windowUserId: Int64?
    private static let windowDelegate = WindowDelegate()

    // MARK: - Row visibility

    /// Emits the row visibility now and again whenever the toggle changes.
    static var visibleSignal: Signal<Bool, NoError> {
        return changes.get()
        |> map { _ -> Bool in
            return isVisible
        }
        |> distinctUntilChanged
    }

    static var isVisible: Bool {
        guard #available(macOS 13.0, *) else {
            return false
        }
        return revealed
    }

    private static func notifyChanged() {
        changes.set(changeCounter.modify { $0 + 1 })
    }

    // MARK: - Click gesture on the "Novagram Settings" row

    /// Called from the "Novagram Settings" row action, after the page was opened as usual. The 20th quick
    /// click toggles the hidden row. Showing it asks for the admin login first; hiding it never does.
    static func registerSettingsRowClick(window: Window) {
        guard #available(macOS 13.0, *) else {
            return
        }
        guard clickCounter.register(at: Date()), !isPrompting else {
            return
        }
        if revealed {
            setRevealed(false)
            return
        }
        isPrompting = true
        NovagramAdsAdminAuth.presentPrompt(window: window) { role in
            isPrompting = false
            if role != nil {
                setRevealed(true)
            }
        }
    }

    private static var isPrompting = false

    private static func setRevealed(_ value: Bool) {
        revealed = value
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        notifyChanged()
    }

    // MARK: - Opening the screen

    /// Opens the "Ads Analytics" window, or brings the open one to the front.
    static func open(context: AccountContext) {
        guard #available(macOS 13.0, *) else {
            return
        }
        // The SDK's view controller factory is main-actor isolated; this body has no suspension point.
        Task { @MainActor in
            present(context: context)
        }
    }

    @MainActor
    @available(macOS 13.0, *)
    private static func present(context: AccountContext) {
        let userId = NovagramAdsCenter.userId(context)
        if let window, windowUserId == userId {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // The screen belongs to one account (its keychain key); another account gets a fresh window.
        window?.close()

        let controller = InsightsUI.makeViewController(
            configuration: configuration(context: context),
            theme: InsightsTheme(accent: theme.colors.accent)
        )
        let newWindow = NSWindow(contentViewController: controller)
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.title = windowTitle
        newWindow.isReleasedWhenClosed = false
        newWindow.setContentSize(defaultContentSize)
        newWindow.contentMinSize = minimumContentSize
        newWindow.delegate = windowDelegate
        if !newWindow.setFrameUsingName(windowAutosaveName) {
            newWindow.center()
        }
        newWindow.setFrameAutosaveName(windowAutosaveName)

        window = newWindow
        windowUserId = userId
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            let closing = NovagramInsightsEntry.window
            NovagramInsightsEntry.window = nil
            NovagramInsightsEntry.windowUserId = nil
            NovagramInsightsEntry.notifyChanged()
            // The close can come from a button inside the hosted screen; keep it alive until this turn ends.
            Queue.mainQueue().async {
                withExtendedLifetime(closing) {}
            }
        }
    }

    // MARK: - Configuration

    @available(macOS 13.0, *)
    private static func configuration(context: AccountContext) -> InsightsConfiguration {
        return InsightsConfiguration(
            environment: NovagramAdsCenter.environment(),
            keychainKey: keychainKey(context: context),
            language: language(),
            // No in-screen Close on the Mac: the window has its own close button and ⌘W,
            // and windowWillClose refreshes the Settings row.
            onClose: nil
        )
    }

    private static func keychainKey(context: AccountContext) -> InsightsKeychainKey {
        return InsightsKeychainKey(account: String(NovagramAdsCenter.userId(context)))
    }

    private static func language() -> InsightsLanguage {
        switch appCurrentLanguage.baseLanguageCode {
        case "uz":
            return .uzbek
        case "ru":
            return .russian
        default:
            return .english
        }
    }
}

/// Counts consecutive clicks; every click must come within `maxGap` of the previous one.
struct SettingsRowClickCounter {
    static let requiredClicks = 20
    static let maxGap: TimeInterval = 1.5

    private var count = 0
    private var lastClick: Date?

    /// Registers a click. Returns true on the click that completes the series (the counter then starts over).
    mutating func register(at date: Date) -> Bool {
        if let last = lastClick, date.timeIntervalSince(last) > Self.maxGap || date < last {
            count = 0
        }
        lastClick = date
        count += 1
        guard count >= Self.requiredClicks else {
            return false
        }
        reset()
        return true
    }

    mutating func reset() {
        count = 0
        lastClick = nil
    }
}
