//
//  NovagramAdMenu.swift
//  Telegram-Mac
//
//  "About this ad" / "Report ad" for OUR ads on every surface (channel bubble, bot panel, search row,
//  video banner). No Premium "Hide ad" item and no "Remove ads" upsell: Novagram ads are shown to every
//  user and the server has no "hide" action. Report offers six reasons, hides the ad locally at once
//  and thanks the user whatever the outcome.
//  Port of iOS submodules/Novagram/NovagramAds/Sources/NovagramAdMenu.swift (AppKit menus here).
//

import Cocoa
import TGUIKit
import NovagramCore
import NovagramAds

enum NovagramAdMenu {
    /// Context-menu items for OUR ad, or nil for Telegram's own ads (the caller keeps its own menu).
    static func items(opaqueId: Data, window: Window) -> [ContextMenuItem]? {
        guard let token = NovagramAdsHooks.token(opaqueId: opaqueId) else {
            return nil
        }
        return self.items(token: token, window: window)
    }

    /// About + Report (with its six reasons as a submenu) for the ad with this random_id.
    static func items(token: String, window: Window) -> [ContextMenuItem] {
        let strings = NovagramL10n.current

        let about = ContextMenuItem(strings.ads_about, handler: {
            self.presentAbout(token: token, window: window)
        }, itemImage: MenuAnimation.menu_show_info.value)

        let report = ContextMenuItem(strings.ads_report, itemImage: MenuAnimation.menu_restrict.value)
        let reasons = ContextMenu()
        let header = ContextMenuItem(strings.ads_reportTitle)
        header.isEnabled = false
        reasons.addItem(header)
        reasons.addItem(ContextSeparatorItem())
        for reason in SDKAdReportReason.allCases {
            reasons.addItem(ContextMenuItem(self.title(reason, strings: strings), handler: {
                NovagramAdsCenter.report(token: token, reason: reason)
                showModalText(for: window, text: strings.ads_reportSent)
            }))
        }
        report.submenu = reasons

        return [about, ContextSeparatorItem(), report]
    }

    /// The same items as a ready menu (search row "Ad" pill).
    static func menu(token: String, window: Window) -> ContextMenu {
        let menu = ContextMenu()
        for item in self.items(token: token, window: window) {
            menu.addItem(item)
        }
        return menu
    }

    /// A ready menu for OUR ad in the given presentation (video player banner), or nil for Telegram's ads.
    static func menu(opaqueId: Data, window: Window, presentation: AppMenu.Presentation) -> ContextMenu? {
        guard let items = self.items(opaqueId: opaqueId, window: window) else {
            return nil
        }
        let menu = ContextMenu(presentation: presentation)
        for item in items {
            menu.addItem(item)
        }
        return menu
    }

    private static func presentAbout(token: String, window: Window) {
        let strings = NovagramL10n.current
        var text = strings.ads_aboutText
        if let otherInfo = NovagramAdsCenter.registry.served(token: token)?.ad.ad.otherInfo.trimmingCharacters(in: .whitespacesAndNewlines), !otherInfo.isEmpty {
            text += "\n\n" + otherInfo
        }
        alert(for: window, header: strings.ads_aboutTitle, info: text)
    }

    private static func title(_ reason: SDKAdReportReason, strings: NovagramL10n) -> String {
        switch reason {
        case .spam:
            return strings.ads_reason_spam
        case .violence:
            return strings.ads_reason_violence
        case .pornography:
            return strings.ads_reason_pornography
        case .illegal:
            return strings.ads_reason_illegal
        case .misleading:
            return strings.ads_reason_misleading
        case .other:
            return strings.ads_reason_other
        @unknown default:
            return strings.ads_reason_other
        }
    }
}
