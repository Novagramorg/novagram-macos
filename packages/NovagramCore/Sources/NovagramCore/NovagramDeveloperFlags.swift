//
//  NovagramDeveloperFlags.swift
//  NovagramCore
//
//  The hidden Developer section of Novagram Settings, like iOS (NovagramMessenger/NovagramDeveloperSection.swift):
//  per-device switches for features in testing, off by default, in the "pro_messager" suite with the
//  iOS keys. "Remove all ads" is the third switch there; the app reads it through NovagramAdsGate.
//

import Cocoa
import SwiftSignalKit

public extension NSNotification.Name {
    // Posted when a Developer switch flips, so the screens that read a flag update live.
    static let novagramDeveloperFlagsChanged = NSNotification.Name("NovagramDeveloperFlagsChanged")
}

public enum NovagramDeveloperFlags {
    private static let udSuite = "pro_messager"
    private static let currencyRatesViewKey = "novagram_currency_rates_view"
    private static let adsPanelKey = "novagram_ads_panel"
    private static let stickerPackSaveKey = "novagram_sticker_pack_save"
    // Read by TelegramCore too (fork-patches/telegramcore/NovagramAdEvents.swift): keep the name in sync.
    private static let adEventsOffKey = "novagram_ads_events_off"
    private static let searchFeaturesKey = "novagram_dev_search_features"
    private static let callRecordingKey = "novagram_dev_call_recording"
    private static let callDataSavingKey = "novagram_dev_call_data_saving"

    public static var isCallDataSavingEnabled: Bool {
        get { return self.value(forKey: self.callDataSavingKey) }
        set { self.setValue(newValue, forKey: self.callDataSavingKey) }
    }

    public static var callDataSavingSignal: Signal<Bool, NoError> {
        return self.signal { self.isCallDataSavingEnabled }
    }

    public static var isSearchFeaturesEnabled: Bool {
        get { return self.value(forKey: self.searchFeaturesKey) }
        set { self.setValue(newValue, forKey: self.searchFeaturesKey) }
    }

    public static var isCallRecordingEnabled: Bool {
        get { return self.value(forKey: self.callRecordingKey) }
        set { self.setValue(newValue, forKey: self.callRecordingKey) }
    }

    public static var searchFeaturesSignal: Signal<Bool, NoError> {
        return self.signal { self.isSearchFeaturesEnabled }
    }

    public static var callRecordingSignal: Signal<Bool, NoError> {
        return self.signal { self.isCallRecordingEnabled }
    }

    /// Show the currency rates row (Settings, under Analytics).
    public static var isCurrencyRatesViewEnabled: Bool {
        get { return self.value(forKey: self.currencyRatesViewKey) }
        set { self.setValue(newValue, forKey: self.currencyRatesViewKey) }
    }

    /// Show the Novagram ads panel row ("Ads Analytics" in Settings).
    public static var isAdsPanelEnabled: Bool {
        get { return self.value(forKey: self.adsPanelKey) }
        set { self.setValue(newValue, forKey: self.adsPanelKey) }
    }

    /// Show "Save All" in the sticker and emoji pack menu (macOS only).
    public static var isStickerPackSaveEnabled: Bool {
        get { return self.value(forKey: self.stickerPackSaveKey) }
        set { self.setValue(newValue, forKey: self.stickerPackSaveKey) }
    }

    /// "Don't send ad events": views, clicks and actions of Novagram and Telegram ads are not reported, so a
    /// developer can test an ad that the backend shows once per user. Nothing to do with Ghost mode.
    public static var isAdEventsOff: Bool {
        get { return self.value(forKey: self.adEventsOffKey) }
        set { self.setValue(newValue, forKey: self.adEventsOffKey) }
    }

    public static var adEventsOffSignal: Signal<Bool, NoError> {
        return self.signal { self.isAdEventsOff }
    }

    /// Emits the current value, then again whenever a Developer switch flips. Main queue.
    public static var currencyRatesViewSignal: Signal<Bool, NoError> {
        return self.signal { self.isCurrencyRatesViewEnabled }
    }

    public static var adsPanelSignal: Signal<Bool, NoError> {
        return self.signal { self.isAdsPanelEnabled }
    }

    public static var stickerPackSaveSignal: Signal<Bool, NoError> {
        return self.signal { self.isStickerPackSaveEnabled }
    }

    private static func value(forKey key: String) -> Bool {
        return UserDefaults(suiteName: self.udSuite)?.object(forKey: key) as? Bool ?? false
    }

    private static func setValue(_ value: Bool, forKey key: String) {
        UserDefaults(suiteName: self.udSuite)?.set(value, forKey: key)
        NotificationCenter.default.post(name: .novagramDeveloperFlagsChanged, object: nil)
    }

    private static func signal(_ read: @escaping () -> Bool) -> Signal<Bool, NoError> {
        return Signal { subscriber in
            subscriber.putNext(read())
            let observer = NotificationCenter.default.addObserver(forName: .novagramDeveloperFlagsChanged, object: nil, queue: .main) { _ in
                subscriber.putNext(read())
            }
            return ActionDisposable {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        |> distinctUntilChanged
    }
}

/// Who passed the developer login on this device, like iOS (NovagramDeveloperSection.swift). The login
/// decides the role, and the role decides which Developer switches show. A switch a role cannot see is
/// turned off when that role logs in, so it never stays on unseen.
public enum NovagramDeveloperRole: String {
    case developer
    case director

    /// The switches in the Developer section.
    public enum Switch {
        case removeAllAds
        case adEventsOff
        case currencyRatesView
        case adsPanel
        case stickerPackSave
        case searchFeatures
        case callRecording
        case callDataSaving
    }

    private static let udSuite = "pro_messager"
    private static let roleKey = "novagram_developer_role"

    /// The developer sees every switch; the director only the ones they use.
    public func canUse(_ item: Switch) -> Bool {
        switch self {
        case .developer:
            return true
        case .director:
            switch item {
            case .adEventsOff, .adsPanel:
                return true
            case .removeAllAds, .currencyRatesView, .stickerPackSave, .searchFeatures, .callRecording, .callDataSaving:
                return false
            }
        }
    }

    /// The role of the last login. A device opened before roles existed was opened by the developer.
    public static var current: NovagramDeveloperRole {
        let stored = UserDefaults(suiteName: self.udSuite)?.string(forKey: self.roleKey)
        return stored.flatMap(NovagramDeveloperRole.init(rawValue:)) ?? .developer
    }

    /// Emits the current role, then again whenever a Developer switch flips or a role logs in. Main queue.
    public static var currentSignal: Signal<NovagramDeveloperRole, NoError> {
        return Signal { subscriber in
            subscriber.putNext(self.current)
            let observer = NotificationCenter.default.addObserver(forName: .novagramDeveloperFlagsChanged, object: nil, queue: .main) { _ in
                subscriber.putNext(self.current)
            }
            return ActionDisposable {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        |> distinctUntilChanged
    }

    /// Stores the role that just logged in and turns off the switches it cannot see. "Remove all ads"
    /// lives in the app (NovagramAdsGate), which turns it off right after this call.
    public static func didLogIn(_ role: NovagramDeveloperRole) {
        UserDefaults(suiteName: self.udSuite)?.set(role.rawValue, forKey: self.roleKey)
        if !role.canUse(.adEventsOff) && NovagramDeveloperFlags.isAdEventsOff {
            NovagramDeveloperFlags.isAdEventsOff = false
        }
        if !role.canUse(.currencyRatesView) && NovagramDeveloperFlags.isCurrencyRatesViewEnabled {
            NovagramDeveloperFlags.isCurrencyRatesViewEnabled = false
        }
        if !role.canUse(.adsPanel) && NovagramDeveloperFlags.isAdsPanelEnabled {
            NovagramDeveloperFlags.isAdsPanelEnabled = false
        }
        if !role.canUse(.stickerPackSave) && NovagramDeveloperFlags.isStickerPackSaveEnabled {
            NovagramDeveloperFlags.isStickerPackSaveEnabled = false
        }
        if !role.canUse(.searchFeatures) && NovagramDeveloperFlags.isSearchFeaturesEnabled {
            NovagramDeveloperFlags.isSearchFeaturesEnabled = false
        }
        if !role.canUse(.callRecording) && NovagramDeveloperFlags.isCallRecordingEnabled {
            NovagramDeveloperFlags.isCallRecordingEnabled = false
        }
        if !role.canUse(.callDataSaving) && NovagramDeveloperFlags.isCallDataSavingEnabled {
            NovagramDeveloperFlags.isCallDataSavingEnabled = false
        }
        NotificationCenter.default.post(name: .novagramDeveloperFlagsChanged, object: nil)
    }
}

/// Holding the app version line at the bottom of Settings for `revealDuration` seconds toggles the
/// Developer section (iOS: a 20 s long press). Settings rows act on mouse up, so the hold is measured
/// from the last left mouse down to the mouse up that runs the row's action.
public enum NovagramDeveloperSection {
    public static let revealDuration: TimeInterval = 20.0

    private static var lastLeftMouseDown: TimeInterval = 0
    private static var monitor: Any?

    /// Starts recording left mouse downs in this app. Call once at launch.
    public static func installPressClock() {
        guard self.monitor == nil else {
            return
        }
        self.monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            NovagramDeveloperSection.lastLeftMouseDown = event.timestamp
            return event
        }
    }

    /// How long the left button was held for the mouse up being handled now; 0 outside a mouse up.
    public static var currentPressDuration: TimeInterval {
        guard let event = NSApp.currentEvent, event.type == .leftMouseUp, self.lastLeftMouseDown > 0 else {
            return 0
        }
        return max(0, event.timestamp - self.lastLeftMouseDown)
    }
}
