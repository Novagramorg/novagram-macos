import Cocoa
import TGUIKit
import SettingsUI
import FenixuzCore

// Stable ids for the Novagram rows in Settings (900...998, see NovagramSettingsHooks).
private enum NovagramSettingsRowId {
    static let accounts = 910
    static let settings = 911
    static let bots = 912
    static let analytics = 913
    // Reserved for the ads SDK port: 914 = hidden "Ads Analytics" row (F09).
}

private let novagramGold = NSColor(rgb: 0xD4AF37)

private func novagramRow(_ id: Int, _ title: String, _ symbol: String, _ color: FenixuzIconColor, titleColor: NSColor? = nil, make: @escaping (AccountContext) -> ViewController) -> NovagramSettingsRow {
    return NovagramSettingsRow(id: id, title: title, icon: fenixuzSettingsIcon(systemName: symbol, color: color), titleColor: titleColor, action: { context, present in
        guard let context = context as? AccountContext else {
            return
        }
        present(make(context))
    })
}

func installNovagramSettingsHooks() {
    var hooks = NovagramSettingsHooks()
    hooks.hidePaidRows = true
    hooks.showInlineAccounts = false
    hooks.rows = { _, placement in
        switch placement {
        case .accounts:
            return [
                novagramRow(NovagramSettingsRowId.accounts, "Accounts", "person.2.fill", .blue, make: { FenixAccountsController(context: $0) })
            ]
        case .top:
            // The hidden "Ads Analytics" row (F09) goes after Analytics once the ads SDK is ported.
            return [
                novagramRow(NovagramSettingsRowId.settings, "Novagram Settings", "n.square.fill", .gold, titleColor: novagramGold, make: { FenixuzSettingsController($0) }),
                novagramRow(NovagramSettingsRowId.bots, "Novagram Bots", "bolt.fill", .green, make: { NovagramBotsController($0) }),
                novagramRow(NovagramSettingsRowId.analytics, "Analytics", "chart.bar.fill", .green, make: { FenixuzAnalyticsController($0) })
            ]
        }
    }
    hooks.selectedRowId = { controller in
        switch controller {
        case is FenixuzSettingsController:
            return NovagramSettingsRowId.settings
        case is NovagramBotsController:
            return NovagramSettingsRowId.bots
        case is FenixuzAnalyticsController:
            return NovagramSettingsRowId.analytics
        default:
            return nil
        }
    }
    // The 10-click version row (F08) installs hooks.versionRowClick here once the ads SDK is ported.
    NovagramSettingsHooks.install(hooks)
}
