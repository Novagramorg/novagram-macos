//
//  FenixuzAppStoreIAP.swift
//  Telegram-Mac
//
//  iOS portasi: submodules/Fenixuz/AppStoreIAP/Sources/FenixuzAppStoreIAP.swift
//
//  Apple Review 3.1.1 — Fenixuz raqamli obuna sotmaydi. Telegram serveri
//  rasmiy bo'lmagan client uchun StoreKit receipt'larini qabul qilmaydi,
//  shuning uchun har qanday Premium / Stars / Gift / Bot Premium-subscription
//  yo'li pulga yetib bormay UI'da bloklanadi va foydalanuvchi rasmiy
//  Telegram for macOS'ga yo'naltiriladi.
//
//  Mac uchun farqi:
//    - UIAlertController o'rniga TGUIKit `verifyAlert(for: Window, ...)`
//      ishlatamiz (project'da kanonik wrapper).
//    - URL ochish uchun `NSWorkspace.shared.open(url)` (iOS'dagi
//      UIApplication.shared.open o'rniga).
//    - 3 chokepoint:
//        InAppLinks.swift          — t.me/$slug → invoice
//        WebpageModalController    — Web App "web_app_open_invoice"
//        ChatInterfaceInteraction  — keyboard button "payment" / @PremiumBot
//      barchasi `shouldBlock(currency:hasSubscriptionPeriod:)` orqali
//      filtrlanadi va bloklanadigan invoice uchun `presentBlockedAlert` chaqiriladi.
//
//  Detection rule (bot invoice):
//    - currency.uppercased() != "XTR"   (Stars allowed — Apple-da IAP sifatida tasdiqlangan)
//    - subscriptionPeriod != nil        (one-off non-subscription invoice'lar — fizik tovar
//                                        uchun — qoladi)

import Foundation
import AppKit
import TGUIKit
import TelegramCore
import AlertsUI

public enum FenixuzAppStoreIAP {
    /// Tashqi observabilityyo'q (Mac uchun App Store flag yo'q hozircha) — placeholder bo'lib
    /// turadi, kelajakda agar FBuildConfig kabi flag qo'shilsa, AppDelegate'dan to'ldiriladi.
    public static var isAppStoreBuild: Bool = false


    // MARK: - Bot-invoice gate

    /// `true` qaytarsa, ushbu invoice uchun `PaymentsCheckoutController` ko'rsatish
    /// taqiqlanadi va o'rniga blok alert ko'rsatiladi.
    public static func shouldBlock(currency: String, hasSubscriptionPeriod: Bool) -> Bool {
        if currency.uppercased() == "XTR" {
            return false
        }
        return hasSubscriptionPeriod
    }

    /// Convenience overload: `TelegramMediaInvoice` qabul qiladi.
    public static func shouldBlock(invoice: TelegramMediaInvoice) -> Bool {
        return shouldBlock(currency: invoice.currency, hasSubscriptionPeriod: invoice.subscriptionPeriod != nil)
    }

    /// Wider rule (13.x): every non-Stars invoice for a digital good (Premium, gift codes,
    /// giveaways, Stars top-up, gifts and their upgrades) is blocked. Bot invoices opened by
    /// slug or from a message stay open for physical goods unless they are subscriptions.
    /// Gift resale paid with TON uses the account's TON balance and stays open.
    public static func shouldBlock(invoice: TelegramMediaInvoice, source: BotPaymentInvoiceSource) -> Bool {
        if invoice.currency.uppercased() == "XTR" {
            return false
        }
        switch source {
        case .message, .slug:
            return invoice.subscriptionPeriod != nil
        case let .starGiftResale(_, _, ton, _, _, _):
            return !ton
        default:
            return true
        }
    }

    // MARK: - External purchase links

    /// Fragment TON top-up (fragment.com/ads/topup) is a card purchase of a digital currency,
    /// opened from Stars and "Add TON" screens. Blocked like the other purchases.
    public static func shouldBlockExternalPurchase(link: String) -> Bool {
        guard let url = URL(string: link), let host = url.host?.lowercased() else {
            return false
        }
        let isFragment = host == "fragment.com" || host.hasSuffix(".fragment.com")
        return isFragment && url.path.lowercased().hasPrefix("/ads/topup")
    }

    // MARK: - StoreKit IAP gate

    /// Mac builds — Fenixuz fork StoreKit ishlatmaydi, har qanday IAP funnel bu yerga keladi.
    /// Hozircha Mac tomonda StoreKit chokepoint mavjud emas (iOS'dagi `InAppPurchaseManager`
    /// kabi yagona joy yo'q), shuning uchun bu flag mavjud kelgusi waves uchun
    /// (Mac Premium UI ulanganda).
    public static var shouldBlockIAP: Bool {
        return true
    }

    // MARK: - Alert presentation

    /// Localized alert ko'rsatish — Mac uchun TGUIKit'ning standart wrapper'i.
    /// Main thread'dan chaqiring.
    public static func presentBlockedAlert(on window: Window) {
        let l10n = FenixuzL10n.current
        verifyAlert(
            for: window,
            header: l10n.iap_blockPurchases_title,
            information: l10n.iap_blockPurchases_message,
            ok: l10n.iap_block_open_app_store,
            cancel: l10n.iap_block_cancel,
            successHandler: { _ in
                // Fenixuz: official Telegram'ga deep-link olib tashlandi (4.1/4.2.2 redirect xavfi).
                // IAP gate saqlanadi (3.1.1) — alert faqat xabar beradi, hech qayerga yo'naltirmaydi.
            }
        )
    }
}

extension FenixuzL10n {
    // Generic text: the gate now also covers Stars top-up, gifts and giveaways, not only Premium.
    public var iap_blockPurchases_title: String {
        pick(
            en: "Purchases unavailable",
            uz: "Xaridlar mavjud emas",
            ru: "Покупки недоступны"
        )
    }

    public var iap_blockPurchases_message: String {
        pick(
            en: "Premium, Stars, TON and gifts can't be bought in this app.",
            uz: "Premium, Stars, TON va sovg'alarni bu ilovada sotib olib bo'lmaydi.",
            ru: "Premium, Stars, TON и подарки нельзя купить в этом приложении."
        )
    }
}
