import Cocoa
import TGUIKit
import SwiftSignalKit
import SettingsUI
import NovagramCore

// Stable ids for the Novagram rows in Settings (900...998, see NovagramSettingsHooks).
private enum NovagramSettingsRowId {
    static let accounts = 910
    static let settings = 911
    static let bots = 912
    static let analytics = 913
    static let adsAnalytics = 914
}

private let novagramGold = NSColor(rgb: 0xD4AF37)

private func novagramRow(_ id: Int, _ title: String, _ symbol: String, _ color: NovagramIconColor, titleColor: NSColor? = nil, make: @escaping (AccountContext) -> ViewController) -> NovagramSettingsRow {
    return NovagramSettingsRow(id: id, title: title, icon: novagramSettingsIcon(systemName: symbol, color: color), titleColor: titleColor, action: { context, present in
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
                novagramRow(NovagramSettingsRowId.accounts, "Accounts", "person.2.fill", .blue, make: { NovagramAccountsController(context: $0) })
            ]
        case .top:
            var rows = [
                novagramRow(NovagramSettingsRowId.settings, "Novagram Settings", "n.square.fill", .gold, titleColor: novagramGold, make: { context in
                    NovagramInsightsEntry.registerSettingsRowClick(window: context.window)
                    return NovagramSettingsController(context)
                }),
                novagramRow(NovagramSettingsRowId.bots, "Novagram Bots", "bolt.fill", .green, make: { NovagramBotsController($0) }),
                novagramRow(NovagramSettingsRowId.analytics, "Analytics", "chart.bar.fill", .green, make: { NovagramAnalyticsController($0) })
            ]
            if NovagramInsightsEntry.isVisible {
                rows.append(adsAnalyticsRow())
            }
            return rows
        }
    }
    hooks.selectedRowId = { controller in
        switch controller {
        case is NovagramSettingsController:
            return NovagramSettingsRowId.settings
        case is NovagramBotsController:
            return NovagramSettingsRowId.bots
        case is NovagramAnalyticsController:
            return NovagramSettingsRowId.analytics
        default:
            return nil
        }
    }
    hooks.rowsUpdated = { _ in
        return NovagramInsightsEntry.visibleSignal |> map { _ in Void() }
    }
    hooks.versionRowClick = { context in
        guard let context = context as? AccountContext else {
            return false
        }
        return NovagramAdsGate.handleVersionClick(window: context.window, onUnlocked: {
            context.bindings.rootNavigation().push(NovagramSettingsController(context))
        })
    }
    NovagramSettingsHooks.install(hooks)
}

private func adsAnalyticsRow() -> NovagramSettingsRow {
    return NovagramSettingsRow(id: NovagramSettingsRowId.adsAnalytics, title: NovagramL10n.current.ads_analytics_title, icon: novagramSettingsIcon(systemName: "chart.xyaxis.line", color: .orange), action: { context, _ in
        guard let context = context as? AccountContext else {
            return
        }
        NovagramInsightsEntry.open(context: context)
    })
}
