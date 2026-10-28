//
//  NovagramUnreadReminderManager.swift
//  Telegram-Mac
//
//  iOS parity: submodules/Novagram/UnreadReminder
//  Features #33, #34, #35: O'qilmagan xabar eslatmasi (Unread Message Reminder)
//  Feature #61: O'qilganda push bildirishnomalarni tozalash (Clear Push Notifications on Read)
//

import Foundation
import Cocoa
import UserNotifications
import TelegramCore
import Postbox
import SwiftSignalKit
import InAppSettings
import NovagramCore

private let kReminderSuite = "pro_messager"
private let kReminderEnabled = "unread_reminder_enabled"
private let kReminderMinutes = "unread_reminder_minutes"
// The Mac key before 2026-10; copied into the iOS key once.
private let kReminderLegacyInterval = "unread_reminder_interval"
private let kReminderSound = "unread_reminder_sound"

final class NovagramUnreadReminderManager {
    static let shared = NovagramUnreadReminderManager()

    private let defaults = UserDefaults(suiteName: kReminderSuite)
    private var timer: SwiftSignalKit.Timer?
    private weak var currentContext: AccountContext?

    static let minuteOptions = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60]

    private init() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name("NovagramSettingsChanged"), object: nil, queue: .main, using: { [weak self] _ in
            self?.updateTimer()
        })
    }

    var isEnabled: Bool {
        return defaults?.bool(forKey: kReminderEnabled) ?? false
    }

    var intervalMinutes: Int {
        if defaults?.object(forKey: kReminderMinutes) == nil, let legacy = defaults?.object(forKey: kReminderLegacyInterval) as? Int, legacy > 0 {
            defaults?.set(legacy, forKey: kReminderMinutes)
            defaults?.removeObject(forKey: kReminderLegacyInterval)
        }
        let value = defaults?.integer(forKey: kReminderMinutes) ?? 0
        return value > 0 ? value : 5
    }

    var soundKey: String {
        return defaults?.string(forKey: kReminderSound) ?? "default"
    }

    func setSound(_ key: String) {
        defaults?.set(key, forKey: kReminderSound)
    }

    func setEnabled(_ enabled: Bool) {
        defaults?.set(enabled, forKey: kReminderEnabled)
        updateTimer()
        NotificationCenter.default.post(name: NSNotification.Name("NovagramSettingsChanged"), object: nil)
    }

    func setIntervalMinutes(_ minutes: Int) {
        defaults?.set(minutes, forKey: kReminderMinutes)
        updateTimer()
        NotificationCenter.default.post(name: NSNotification.Name("NovagramSettingsChanged"), object: nil)
    }

    func start(with context: AccountContext) {
        self.currentContext = context
        updateTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func updateTimer() {
        timer?.invalidate()
        timer = nil

        guard isEnabled, let context = currentContext else {
            return
        }

        let seconds = Double(intervalMinutes * 60)
        let timer = SwiftSignalKit.Timer(timeout: seconds, repeat: true, completion: { [weak self, weak context] in
            guard let self = self, let context = context, self.isEnabled else { return }
            self.checkAndFireReminder(context: context)
        }, queue: .mainQueue())
        self.timer = timer
        timer.start()
    }

    private func checkAndFireReminder(context: AccountContext) {
        // Only fire if the app is not the active, focused key application,
        // or if user hasn't interacted recently
        if NSApp.isActive && NSApp.keyWindow != nil {
            return
        }

        _ = (renderedTotalUnreadCount(accountManager: context.sharedContext.accountManager, postbox: context.account.postbox)
             |> take(1)
             |> deliverOnMainQueue).start(next: { [weak self] (totalUnread, _) in
            guard let self = self else { return }
            if totalUnread > 0 {
                self.sendReminderNotification(unreadCount: Int(totalUnread))
            }
        })
    }

    private func sendReminderNotification(unreadCount: Int) {
        let l10n = NovagramL10n.current
        let content = UNMutableNotificationContent()
        content.title = l10n.reminder_notificationTitle
        content.body = l10n.reminder_notificationBody(unreadCount)
        // A custom tone is played by the app itself: notification sounds only come from the app bundle root or ~/Library/Sounds.
        switch soundKey {
        case "default":
            content.sound = UNNotificationSound.default
        case "none":
            content.sound = nil
        default:
            content.sound = nil
            NovagramReminderSounds.play(soundKey)
        }

        let request = UNNotificationRequest(identifier: "fenixuz_unread_reminder", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - Feature #61: Clear push notifications on read

    static func clearDeliveredNotifications(for peerId: PeerId? = nil) {
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            if let peerId = peerId {
                let prefix = "\(peerId.toInt64())"
                let idsToRemove = notifications
                    .filter { $0.request.identifier.contains(prefix) }
                    .map { $0.request.identifier }
                if !idsToRemove.isEmpty {
                    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: idsToRemove)
                }
            } else {
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            }
        }
    }
}
