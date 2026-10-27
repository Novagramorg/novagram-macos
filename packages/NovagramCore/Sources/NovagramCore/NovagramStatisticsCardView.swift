//
//  NovagramStatisticsCardView.swift
//  NovagramCore
//
//  Settings → Analytics: the NovagramServices SDK's `StatisticsCard` (NovagramServicesUI, SwiftUI)
//  in an AppKit view. The SDK UI is imported only here; the app passes its colors, texts and an
//  AppKit header view (the duck sticker), which goes into the card's header slot.
//

import Cocoa
import SwiftUI
import NovagramServices
import NovagramServicesUI

/// The app's palette mapped to the SDK card tokens (docs/UI.md, "Telegram-Mac" column).
public struct NovagramServicesCardColors: Equatable {
    public let cardBackground: NSColor
    public let separator: NSColor
    public let primaryText: NSColor
    public let secondaryText: NSColor
    public let accent: NSColor
    public let positive: NSColor
    public let negative: NSColor
    public let isDark: Bool

    public init(cardBackground: NSColor, separator: NSColor, primaryText: NSColor, secondaryText: NSColor, accent: NSColor, positive: NSColor, negative: NSColor, isDark: Bool) {
        self.cardBackground = cardBackground
        self.separator = separator
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.accent = accent
        self.positive = positive
        self.negative = negative
        self.isDark = isDark
    }

    var theme: ServicesUITheme {
        return ServicesUITheme(
            cardBackground: Color(nsColor: self.cardBackground),
            separator: Color(nsColor: self.separator),
            primaryText: Color(nsColor: self.primaryText),
            secondaryText: Color(nsColor: self.secondaryText),
            accent: Color(nsColor: self.accent),
            positive: Color(nsColor: self.positive),
            negative: Color(nsColor: self.negative),
            isDark: self.isDark
        )
    }
}

public final class NovagramStatisticsCardView: NSView {
    public enum Counter {
        case downloads
        case active
    }

    /// A tap on a tile's info icon.
    public var onInfo: ((Counter) -> Void)?

    private let header: NSView?
    private let headerSize: NSSize
    private let host = NSHostingController(rootView: AnyView(EmptyView()))

    public init(header: NSView?, headerSize: NSSize) {
        self.header = header
        self.headerSize = headerSize
        super.init(frame: .zero)
        self.host.view.autoresizingMask = []
        self.addSubview(self.host.view)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `downloads` / `active` nil (loading or a failed call) shows "—" in both tiles.
    public func update(downloads: Int?, active: Int?, colors: NovagramServicesCardColors, languageCode: String, subtitle: String?, downloadsCaption: String, activeCaption: String) {
        var counts: StatisticsCounts?
        if let downloads, let active {
            counts = StatisticsCounts(downloads: downloads, active: active)
        }
        let strings = StatisticsStrings(subtitle: subtitle, downloadsCaption: downloadsCaption, activeCaption: activeCaption)
        let header = self.header
        let headerSize = self.headerSize
        let card = StatisticsCard(
            counts: counts,
            strings: strings,
            theme: colors.theme,
            locale: Locale(identifier: languageCode),
            onInfo: { [weak self] counter in
                switch counter {
                case .downloads:
                    self?.onInfo?(.downloads)
                case .active:
                    self?.onInfo?(.active)
                @unknown default:
                    break
                }
            },
            header: {
                if let header {
                    NovagramHostedNSView(view: header)
                        .frame(width: headerSize.width, height: headerSize.height)
                }
            }
        )
        self.host.rootView = AnyView(card)
        self.needsLayout = true
    }

    /// The height the card needs for `width` (the card has no outer padding and no maximum width).
    public func height(for width: CGFloat) -> CGFloat {
        return ceil(self.host.sizeThatFits(in: NSSize(width: width, height: .greatestFiniteMagnitude)).height)
    }

    public override func layout() {
        super.layout()
        self.host.view.frame = self.bounds
    }
}

/// An AppKit view inside a SwiftUI hierarchy; the app keeps updating it (e.g. a playing sticker).
private struct NovagramHostedNSView: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView {
        return self.view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
    }
}
