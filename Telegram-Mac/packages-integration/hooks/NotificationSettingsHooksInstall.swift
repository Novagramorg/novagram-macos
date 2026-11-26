import Cocoa
import TGUIKit
import SwiftSignalKit
import SettingsUI

func installNotificationSettingsUIHooks() {
    NotificationSettingsHooks.install(NotificationSettingsHooks(
        authorizationStatus: { context in
            UNUserNotifications.recurrentAuthorizationStatus(context as! AccountContext) |> map { NotificationAuthorizationStatus(rawValue: $0.rawValue) ?? .notDetermined } }
    ))
}
