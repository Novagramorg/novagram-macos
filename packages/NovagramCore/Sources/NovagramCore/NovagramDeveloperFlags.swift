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
