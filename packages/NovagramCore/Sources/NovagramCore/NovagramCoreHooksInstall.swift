import AppKit
import Localization
@_exported import NovagramShare

private var menuObserver: NSObjectProtocol?

// Called once from Telegram-Mac/app/main.swift, before NSApplicationMain.
public func installNovagramCoreHooks() {
    localizedValueTransform = NovagramBranding.rebrand

    // MainMenu.xib is loaded during launch, so the menu can only be renamed after it.
    menuObserver = NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
        NovagramBranding.rebrandMenu(NSApp.mainMenu)
        if let appMenu = NSApp.mainMenu?.item(at: 0)?.submenu, let updatesItem = appMenu.item(withTag: NovagramBranding.checkForUpdatesMenuTag) {
            appMenu.removeItem(updatesItem)
        }
    }
}
