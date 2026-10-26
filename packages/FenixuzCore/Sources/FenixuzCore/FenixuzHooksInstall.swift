import AppKit
import Localization
@_exported import FenixuzShare

private var menuObserver: NSObjectProtocol?

// Called once from Telegram-Mac/app/main.swift, before NSApplicationMain.
public func installFenixuzHooks() {
    localizedValueTransform = FenixuzBranding.rebrand

    // MainMenu.xib is loaded during launch, so the menu can only be renamed after it.
    menuObserver = NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
        FenixuzBranding.rebrandMenu(NSApp.mainMenu)
        if let appMenu = NSApp.mainMenu?.item(at: 0)?.submenu, let updatesItem = appMenu.item(withTag: FenixuzBranding.checkForUpdatesMenuTag) {
            appMenu.removeItem(updatesItem)
        }
    }
}
