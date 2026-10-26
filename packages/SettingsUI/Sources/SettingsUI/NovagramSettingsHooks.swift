import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramContext

// Novagram rows in the main Settings list. The screens live in the app target
// (Telegram-Mac/novagram), so the app builds the rows and installs them from
// Telegram-Mac/packages-integration/hooks/NovagramSettingsHooksInstall.swift.
// Defaults keep upstream behaviour: no extra rows, paid rows and inline accounts shown.

public enum NovagramSettingsPlacement {
    // Right above "Add Account" (the "Accounts" page row).
    case accounts
    // Below the account block, above "My Profile" (Novagram Settings, Bots, Analytics, later Ads Analytics).
    case top
}

public struct NovagramSettingsRow: Equatable {
    // Stable id inside AccountInfoEntryId.index; use 900...998 only (upstream uses 0-27+, 999 and 1000+).
    public let id: Int
    public let title: String
    public let icon: CGImage?
    public let titleColor: NSColor?
    public let action: (_ context: any AccountContextProtocol, _ present: @escaping (ViewController) -> Void) -> Void

    public init(id: Int, title: String, icon: CGImage?, titleColor: NSColor? = nil, action: @escaping (_ context: any AccountContextProtocol, _ present: @escaping (ViewController) -> Void) -> Void) {
        self.id = id
        self.title = title
        self.icon = icon
        self.titleColor = titleColor
        self.action = action
    }

    public static func == (lhs: NovagramSettingsRow, rhs: NovagramSettingsRow) -> Bool {
        return lhs.id == rhs.id && lhs.title == rhs.title && lhs.titleColor == rhs.titleColor && (lhs.icon == nil) == (rhs.icon == nil)
    }
}

public struct NovagramSettingsHooks {
    public var rows: (_ context: any AccountContextProtocol, _ placement: NovagramSettingsPlacement) -> [NovagramSettingsRow] = { _, _ in [] }
    // Row id to highlight while the given controller is on screen.
    public var selectedRowId: (_ controller: ViewController) -> Int? = { _ in nil }
    // Emits whenever the rows must be rebuilt (for example a hidden row was revealed).
    public var rowsUpdated: (_ context: any AccountContextProtocol) -> Signal<Void, NoError> = { _ in .single(Void()) }
    // App Store 3.1.1: hide Premium, Stars, TON, Business and Gift rows.
    public var hidePaidRows: Bool = false
    // Other accounts are listed on the "Accounts" page instead of inline.
    public var showInlineAccounts: Bool = true
    // Click on the version row; return true to consume it (reserved for the ads gate, F08).
    public var versionRowClick: (_ context: any AccountContextProtocol) -> Bool = { _ in false }

    public init() {}

    public static var shared = NovagramSettingsHooks()

    public static func install(_ hooks: NovagramSettingsHooks) {
        shared = hooks
    }
}
