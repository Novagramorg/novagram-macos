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

private let kReminderSuite = "pro_messager"
private let kReminderEnabled = "unread_reminder_enabled"
private let kReminderInterval = "unread_reminder_interval" // in minutes (5, 10, 15, 30, 60)
private let kReminderSound = "unread_reminder_sound"

final class NovagramUnreadReminderManager {
    static let shared = NovagramUnreadReminderManager()

    private let defaults = UserDefaults(suiteName: kReminderSuite)
    private var timer: SwiftSignalKit.Timer?
    private weak var currentContext: AccountContext?

    private init() {}

    var isEnabled: Bool {
        return defaults?.bool(forKey: kReminderEnabled) ?? false
    }

    var intervalMinutes: Int {
        let val = defaults?.integer(forKey: kReminderInterval) ?? 15
        return val > 0 ? val : 15
    }

    func setEnabled(_ enabled: Bool) {
        defaults?.set(enabled, forKey: kReminderEnabled)
        updateTimer()
        NotificationCenter.default.post(name: NSNotification.Name("NovagramSettingsChanged"), object: nil)
    }

    func setIntervalMinutes(_ minutes: Int) {
        defaults?.set(minutes, forKey: kReminderInterval)
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
        let content = UNMutableNotificationContent()
        content.title = "Novagram"
        content.body = "Sizda \(unreadCount) ta o'qilmagan xabar bor"
        content.sound = UNNotificationSound.default

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
