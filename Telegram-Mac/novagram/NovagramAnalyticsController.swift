//
//  NovagramAnalyticsController.swift
//  Telegram-Mac
//
//  Settings → Analytics, like the iOS screen: the duck sticker over the NovagramServices SDK's
//  StatisticsCard (NovagramServicesUI, hosted by NovagramStatisticsCardView in NovagramCore).
//    • "Novagram users"  — downloads (one per device).
//    • "Active accounts" — devices with at least one account signed in now.
//
//  The duck is gigagroup.tgs, the same file as iOS BroadcastGroup.tgs. The numbers come from
//  GET /v1/stats through NovagramAnalyticsManager, which also does the install and active-presence
//  tracking; this screen only renders them.
//

import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramMedia
import NovagramCore

private let novagramAnalyticsDuckSize = NSMakeSize(140, 140)

final class NovagramAnalyticsView: View {
    let card: NovagramStatisticsCardView
    private let duck: LottiePlayerView

    required init(frame frameRect: NSRect) {
        let duck = LottiePlayerView(frame: NSMakeRect(0, 0, novagramAnalyticsDuckSize.width, novagramAnalyticsDuckSize.height))
        self.duck = duck
        self.card = NovagramStatisticsCardView(header: duck, headerSize: novagramAnalyticsDuckSize)
        super.init(frame: frameRect)
        addSubview(card)
        playDuck()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func playDuck() {
        guard let data = LocalAnimatedSticker.gigagroup.data else {
            return
        }
        let animation = LottieAnimation(compressed: data, key: LottieAnimationEntryKey(key: .bundle("novagram_analytics_duck"), size: novagramAnalyticsDuckSize), type: .lottie, cachePurpose: .none, playPolicy: .loop, maximumFps: 60, colors: [], metalSupport: false)
        duck.set(animation, reset: true, saveContext: false, animated: false)
    }

    override func layout() {
        super.layout()
        let width = min(frame.width - 32, 480)
        let height = card.height(for: width)
        card.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - width) / 2), 24, width, height)
    }
}

private struct NovagramAnalyticsCounts: Equatable {
    var devices: Int?
    var accounts: Int?
}

final class NovagramAnalyticsController: TelegramGenericViewController<NovagramAnalyticsView> {

    private let statsDisposable = MetaDisposable()
    private var counts = NovagramAnalyticsCounts(devices: nil, accounts: nil)

    override var defaultBarTitle: String {
        return NovagramL10n.current.analytics_title
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        genericView.card.onInfo = { [weak self] counter in
            self?.showInfo(counter)
        }
        render()
        readyOnce()
        loadStats()
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        render()
    }

    private func render() {
        guard isLoaded() else {
            return
        }
        let l10n = NovagramL10n.current
        let colors = theme.colors
        genericView.backgroundColor = colors.listBackground
        genericView.card.update(
            downloads: counts.devices,
            active: counts.accounts,
            colors: NovagramServicesCardColors(
                cardBackground: colors.background,
                separator: colors.border,
                primaryText: colors.text,
                secondaryText: colors.grayText,
                accent: colors.accent,
                positive: colors.greenUI,
                negative: colors.redUI,
                isDark: colors.isDark
            ),
            languageCode: appCurrentLanguage.languageCode,
            subtitle: l10n.analytics_subtitle,
            downloadsCaption: l10n.analytics_usersCaption,
            activeCaption: l10n.analytics_accountsCaption
        )
        genericView.needsLayout = true
    }

    private func showInfo(_ counter: NovagramStatisticsCardView.Counter) {
        let l10n = NovagramL10n.current
        switch counter {
        case .downloads:
            showModalText(for: context.window, text: l10n.analytics_usersInfo)
        case .active:
            showModalText(for: context.window, text: l10n.analytics_accountsInfo)
        }
    }

    private func loadStats() {
        statsDisposable.set((NovagramAnalyticsManager.shared.counts()
        |> deliverOnMainQueue).start(next: { [weak self] result in
            guard let self = self else {
                return
            }
            self.counts = NovagramAnalyticsCounts(devices: result.devices, accounts: result.accounts)
            self.render()
        }))
    }

    deinit {
        statsDisposable.dispose()
    }
}
