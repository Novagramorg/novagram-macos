import Cocoa
import InAppSettings
import Foundation
import Postbox
import TelegramTheme
import TelegramUtils
import ColorPalette
import TGUIKit

public enum InstantPageFontStyle {
    case sans
    case serif
}

public struct InstantPageFont {
    public enum Weight {
        case regular
        case medium
        case semibold
    }

    public let style: InstantPageFontStyle
    public let size: CGFloat
    public let lineSpacingFactor: CGFloat
    public let weight: Weight

    public init(style: InstantPageFontStyle, size: CGFloat, lineSpacingFactor: CGFloat, weight: Weight = .regular) {
        self.style = style
        self.size = size
        self.lineSpacingFactor = lineSpacingFactor
        self.weight = weight
    }
}

public struct InstantPageTextAttributes {
    public let font: InstantPageFont
    public let color: NSColor
    public let underline: Bool
    
    public init(font: InstantPageFont, color: NSColor, underline: Bool = false) {
        self.font = font
        self.color = color
        self.underline = underline
    }
    
    public func withUnderline(_ underline: Bool) -> InstantPageTextAttributes {
        return InstantPageTextAttributes(font: self.font, color: self.color, underline: underline)
    }
    
    public func withUpdatedFontStyles(sizeMultiplier: CGFloat, forceSerif: Bool) -> InstantPageTextAttributes {
        return InstantPageTextAttributes(font: InstantPageFont(style: forceSerif ? .serif : self.font.style, size: floor(self.font.size * sizeMultiplier), lineSpacingFactor: self.font.lineSpacingFactor, weight: self.font.weight), color: self.color, underline: self.underline)
    }
}

public enum InstantPageTextCategoryType {
    case kicker
    case header
    case subheader
    case paragraph
    case caption
    case credit
    case table
    case article
}

public struct InstantPageTextCategories {
    public let kicker: InstantPageTextAttributes
    public let header: InstantPageTextAttributes
    public let subheader: InstantPageTextAttributes
    public let paragraph: InstantPageTextAttributes
    public let caption: InstantPageTextAttributes
    public let credit: InstantPageTextAttributes
    public let table: InstantPageTextAttributes
    public let article: InstantPageTextAttributes
    
    public func attributes(type: InstantPageTextCategoryType, link: Bool) -> InstantPageTextAttributes {
        switch type {
        case .kicker:
            return self.kicker.withUnderline(link)
        case .header:
            return self.header.withUnderline(link)
        case .subheader:
            return self.subheader.withUnderline(link)
        case .paragraph:
            return self.paragraph.withUnderline(link)
        case .caption:
            return self.caption.withUnderline(link)
        case .credit:
            return self.credit.withUnderline(link)
        case .table:
            return self.table.withUnderline(link)
        case .article:
            return self.article.withUnderline(link)
        }
    }
    
    public func withUpdatedFontStyles(sizeMultiplier: CGFloat, forceSerif: Bool) -> InstantPageTextCategories {
        return InstantPageTextCategories(kicker: self.kicker.withUpdatedFontStyles(sizeMultiplier: sizeMultiplier, forceSerif: forceSerif), header: self.header.withUpdatedFontStyles(sizeMultiplier: sizeMultiplier, forceSerif: forceSerif), subheader: self.subheader.withUpdatedFontStyles(sizeMultiplier: sizeMultiplier, forceSerif: forceSerif), paragraph: self.paragraph.withUpdatedFontStyles(sizeMultiplier: sizeMultiplier, forceSerif: forceSerif), caption: self.caption.withUpdatedFontStyles(sizeMultiplier: sizeMultiplier, forceSerif: forceSerif), credit: self.credit.withUpdatedFontStyles(sizeMultiplier: sizeMultiplier, forceSerif: forceSerif), table: self.table.withUpdatedFontStyles(sizeMultiplier: sizeMultiplier, forceSerif: forceSerif), article: self.article.withUpdatedFontStyles(sizeMultiplier: sizeMultiplier, forceSerif: forceSerif))
    }
    public init(kicker: InstantPageTextAttributes, header: InstantPageTextAttributes, subheader: InstantPageTextAttributes, paragraph: InstantPageTextAttributes, caption: InstantPageTextAttributes, credit: InstantPageTextAttributes, table: InstantPageTextAttributes, article: InstantPageTextAttributes) {
        self.kicker = kicker
        self.header = header
        self.subheader = subheader
        self.paragraph = paragraph
        self.caption = caption
        self.credit = credit
        self.table = table
        self.article = article
    }
}

public final class InstantPageTheme {
    public let type: InstantPageThemeType
    public let pageBackgroundColor: NSColor
    
    public let textCategories: InstantPageTextCategories
    public let serif: Bool
    
    public let codeBlockBackgroundColor: NSColor
    
    public let linkColor: NSColor
    public let textHighlightColor: NSColor
    public let linkHighlightColor: NSColor
    public let markerColor: NSColor
    
    public let panelBackgroundColor: NSColor
    public let panelHighlightedBackgroundColor: NSColor
    public let panelPrimaryColor: NSColor
    public let panelSecondaryColor: NSColor
    public let panelAccentColor: NSColor
    
    public let tableBorderColor: NSColor
    public let tableHeaderColor: NSColor
    public let controlColor: NSColor
    
    public let imageTintColor: NSColor?
    
    public let overlayPanelColor: NSColor

    public let separatorColor: NSColor
    public let quoteAccentColor: NSColor

    public let buttonDangerColor: NSColor
    public let buttonSuccessColor: NSColor
    public let checklistBorderColor: NSColor

    /// `.primary` button fill and label colour. The foreground also colours selected checklist ticks.
    public let checkboxFill: NSColor
    public let checkboxForeground: NSColor

    public init(type: InstantPageThemeType, pageBackgroundColor: NSColor, textCategories: InstantPageTextCategories, serif: Bool, codeBlockBackgroundColor: NSColor, linkColor: NSColor, textHighlightColor: NSColor, linkHighlightColor: NSColor, markerColor: NSColor, panelBackgroundColor: NSColor, panelHighlightedBackgroundColor: NSColor, panelPrimaryColor: NSColor, panelSecondaryColor: NSColor, panelAccentColor: NSColor, tableBorderColor: NSColor, tableHeaderColor: NSColor, controlColor: NSColor, imageTintColor: NSColor?, overlayPanelColor: NSColor, separatorColor: NSColor, quoteAccentColor: NSColor, buttonDangerColor: NSColor = NSColor(rgb: 0xff3b30), buttonSuccessColor: NSColor = NSColor(rgb: 0x34c759), checklistBorderColor: NSColor? = nil, checkboxFill: NSColor = NSColor(rgb: 0x007aff), checkboxForeground: NSColor = NSColor(rgb: 0xffffff)) {
        self.type = type
        self.pageBackgroundColor = pageBackgroundColor
        self.textCategories = textCategories
        self.serif = serif
        self.codeBlockBackgroundColor = codeBlockBackgroundColor
        self.linkColor = linkColor
        self.textHighlightColor = textHighlightColor
        self.linkHighlightColor = linkHighlightColor
        self.markerColor = markerColor
        self.panelBackgroundColor = panelBackgroundColor
        self.panelHighlightedBackgroundColor = panelHighlightedBackgroundColor
        self.panelPrimaryColor = panelPrimaryColor
        self.panelSecondaryColor = panelSecondaryColor
        self.panelAccentColor = panelAccentColor
        self.tableBorderColor = tableBorderColor
        self.tableHeaderColor = tableHeaderColor
        self.controlColor = controlColor
        self.imageTintColor = imageTintColor
        self.overlayPanelColor = overlayPanelColor
        self.separatorColor = separatorColor
        self.quoteAccentColor = quoteAccentColor
        self.buttonDangerColor = buttonDangerColor
        self.buttonSuccessColor = buttonSuccessColor
        self.checklistBorderColor = checklistBorderColor ?? tableBorderColor
        self.checkboxFill = checkboxFill
        self.checkboxForeground = checkboxForeground
    }

    /// Reconstructs field by field: any field omitted here silently reverts to its `init` default the
    /// moment the user changes the Instant View font size.
    public func withUpdatedFontStyles(sizeMultiplier: CGFloat, forceSerif: Bool) -> InstantPageTheme {
        return InstantPageTheme(type: type, pageBackgroundColor: pageBackgroundColor, textCategories: self.textCategories.withUpdatedFontStyles(sizeMultiplier: sizeMultiplier, forceSerif: forceSerif), serif: forceSerif, codeBlockBackgroundColor: codeBlockBackgroundColor, linkColor: linkColor, textHighlightColor: textHighlightColor, linkHighlightColor: linkHighlightColor, markerColor: markerColor, panelBackgroundColor: panelBackgroundColor, panelHighlightedBackgroundColor: panelHighlightedBackgroundColor, panelPrimaryColor: panelPrimaryColor, panelSecondaryColor: panelSecondaryColor, panelAccentColor: panelAccentColor, tableBorderColor: tableBorderColor, tableHeaderColor: tableHeaderColor, controlColor: controlColor, imageTintColor: imageTintColor, overlayPanelColor: overlayPanelColor, separatorColor: separatorColor, quoteAccentColor: quoteAccentColor, buttonDangerColor: buttonDangerColor, buttonSuccessColor: buttonSuccessColor, checklistBorderColor: checklistBorderColor, checkboxFill: checkboxFill, checkboxForeground: checkboxForeground)
    }

    public func headingTextAttributes(level: Int32, link: Bool) -> InstantPageTextAttributes {
        let clampedLevel = max(Int32(1), min(level, Int32(6)))

        switch clampedLevel {
        case 1:
            return self.textCategories.header.withUnderline(link)
        case 2:
            return self.textCategories.subheader.withUnderline(link)
        default:
            break
        }

        let subheaderAttributes = self.textCategories.subheader
        let baseSize: CGFloat
        switch clampedLevel {
        case 3:
            baseSize = 20.0
        case 4:
            baseSize = 19.0
        case 5:
            baseSize = 18.0
        default:
            baseSize = 17.0
        }

        let sizeMultiplier = subheaderAttributes.font.size / 22.0
        let attributes = InstantPageTextAttributes(
            font: InstantPageFont(style: .serif, size: floor(baseSize * sizeMultiplier), lineSpacingFactor: subheaderAttributes.font.lineSpacingFactor, weight: .medium),
            color: subheaderAttributes.color,
            underline: subheaderAttributes.underline
        )
        return attributes.withUnderline(link)
    }
}

private let lightTheme = InstantPageTheme(
    type: .light,
    pageBackgroundColor: NSColor(rgb: 0xffffff),
    textCategories: InstantPageTextCategories(
        kicker: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 15.0, lineSpacingFactor: 0.685), color: NSColor(rgb: 0x000000)),
        header: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 24.0, lineSpacingFactor: 0.685), color: NSColor(rgb: 0x000000)),
        subheader: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 19.0, lineSpacingFactor: 0.685), color: NSColor(rgb: 0x000000)),
        paragraph: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 17.0, lineSpacingFactor: 1.0), color: NSColor(rgb: 0x000000)),
        caption: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 15.0, lineSpacingFactor: 1.0), color: NSColor(rgb: 0x79828b)),
        credit: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 13.0, lineSpacingFactor: 1.0), color: NSColor(rgb: 0x79828b)),
        table: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 15.0, lineSpacingFactor: 1.0), color: NSColor(rgb: 0x000000)),
        article: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 18.0, lineSpacingFactor: 1.0), color: NSColor(rgb: 0x000000))
    ),
    serif: false,
    codeBlockBackgroundColor: NSColor(rgb: 0xf5f8fc),
    linkColor: NSColor(rgb: 0x007ee5),
    textHighlightColor: NSColor(rgb: 0, alpha: 0.12),
    linkHighlightColor: NSColor(rgb: 0x007ee5, alpha: 0.07),
    markerColor: NSColor(rgb: 0xfef3bc),
    panelBackgroundColor: NSColor(rgb: 0xf3f4f5),
    panelHighlightedBackgroundColor: NSColor(rgb: 0xe7e7e7),
    panelPrimaryColor: NSColor(rgb: 0x000000),
    panelSecondaryColor: NSColor(rgb: 0x79828b),
    panelAccentColor: NSColor(rgb: 0x007ee5),
    tableBorderColor: NSColor(rgb: 0xe2e2e2),
    tableHeaderColor: NSColor(rgb: 0xf4f4f4),
    controlColor: NSColor(rgb: 0xc7c7cd),
    imageTintColor: nil,
    overlayPanelColor: NSColor(rgb: 0xffffff),
    separatorColor: NSColor(rgb: 0x79828b),
    quoteAccentColor: NSColor(rgb: 0x000000)
)

private let sepiaTheme = InstantPageTheme(
    type: .sepia,
    pageBackgroundColor: NSColor(rgb: 0xf8f1e2),
    textCategories: InstantPageTextCategories(
        kicker: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 15.0, lineSpacingFactor: 0.685), color: NSColor(rgb: 0x4f321d)),
        header: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 24.0, lineSpacingFactor: 0.685), color: NSColor(rgb: 0x4f321d)),
        subheader: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 19.0, lineSpacingFactor: 0.685), color: NSColor(rgb: 0x4f321d)),
        paragraph: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 17.0, lineSpacingFactor: 1.0), color: NSColor(rgb: 0x4f321d)),
        caption: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 15.0, lineSpacingFactor: 1.0), color: NSColor(rgb: 0x927e6b)),
        credit: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 13.0, lineSpacingFactor: 1.0), color: NSColor(rgb: 0x927e6b)),
        table: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 15.0, lineSpacingFactor: 1.0), color: NSColor(rgb: 0x4f321d)),
        article: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 18.0, lineSpacingFactor: 1.0), color: NSColor(rgb: 0x4f321d))
    ),
    serif: false,
    codeBlockBackgroundColor: NSColor(rgb: 0xefe7d6),
    linkColor: NSColor(rgb: 0xd19600),
    textHighlightColor: NSColor(rgb: 0, alpha: 0.1),
    linkHighlightColor: NSColor(rgb: 0xd19600, alpha: 0.1),
    markerColor: NSColor(rgb: 0xe5ddcd),
    panelBackgroundColor: NSColor(rgb: 0xefe7d6),
    panelHighlightedBackgroundColor: NSColor(rgb: 0xe3dccb),
    panelPrimaryColor: NSColor(rgb: 0x000000),
    panelSecondaryColor: NSColor(rgb: 0x927e6b),
    panelAccentColor: NSColor(rgb: 0xd19601),
    tableBorderColor: NSColor(rgb: 0xddd1b8),
    tableHeaderColor: NSColor(rgb: 0xf0e7d4),
    controlColor: NSColor(rgb: 0xddd1b8),
    imageTintColor: nil,
    overlayPanelColor: NSColor(rgb: 0xf8f1e2),
    separatorColor: NSColor(rgb: 0x927e6b),
    quoteAccentColor: NSColor(rgb: 0x4f321d)
)

private let grayTheme = InstantPageTheme(
    type: .gray,
    pageBackgroundColor: NSColor(rgb: 0x5a5a5c),
    textCategories: InstantPageTextCategories(
        kicker: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 15.0, lineSpacingFactor: 0.685), color: NSColor(rgb: 0xcecece)),
        header: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 24.0, lineSpacingFactor: 0.685), color: NSColor(rgb: 0xcecece)),
        subheader: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 19.0, lineSpacingFactor: 0.685), color: NSColor(rgb: 0xcecece)),
        paragraph: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 17.0, lineSpacingFactor: 1.0), color: NSColor(rgb: 0xcecece)),
        caption: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 15.0, lineSpacingFactor: 1.0), color: NSColor(rgb: 0xa0a0a0)),
        credit: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 13.0, lineSpacingFactor: 1.0), color: NSColor(rgb: 0xa0a0a0)),
        table: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 15.0, lineSpacingFactor: 1.0), color: NSColor(rgb: 0xcecece)),
        article: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 18.0, lineSpacingFactor: 1.0), color: NSColor(rgb: 0xcecece))
    ),
    serif: false,
    codeBlockBackgroundColor: NSColor(rgb: 0x555556),
    linkColor: NSColor(rgb: 0x5ac8fa),
    textHighlightColor: NSColor(rgb: 0, alpha: 0.16),
    linkHighlightColor: NSColor(rgb: 0x5ac8fa, alpha: 0.13),
    markerColor: NSColor(rgb: 0x4b4b4b),
    panelBackgroundColor: NSColor(rgb: 0x555556),
    panelHighlightedBackgroundColor: NSColor(rgb: 0x505051),
    panelPrimaryColor: NSColor(rgb: 0xcecece),
    panelSecondaryColor: NSColor(rgb: 0xa0a0a0),
    panelAccentColor: NSColor(rgb: 0x54b9f8),
    tableBorderColor: NSColor(rgb: 0x484848),
    tableHeaderColor: NSColor(rgb: 0x555556),
    controlColor: NSColor(rgb: 0x484848),
    imageTintColor: NSColor(rgb: 0xcecece),
    overlayPanelColor: NSColor(rgb: 0x5a5a5c),
    separatorColor: NSColor(rgb: 0xa0a0a0),
    quoteAccentColor: NSColor(rgb: 0xcecece)
)

private let darkTheme = InstantPageTheme(
    type: .dark,
    pageBackgroundColor: NSColor(rgb: 0x000000),
    textCategories: InstantPageTextCategories(
        kicker: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 15.0, lineSpacingFactor: 0.685), color: NSColor(rgb: 0xb0b0b0)),
        header: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 24.0, lineSpacingFactor: 0.685), color: NSColor(rgb: 0xb0b0b0)),
        subheader: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 19.0, lineSpacingFactor: 0.685), color: NSColor(rgb: 0xb0b0b0)),
        paragraph: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 17.0, lineSpacingFactor: 1.0), color: NSColor(rgb: 0xb0b0b0)),
        caption: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 15.0, lineSpacingFactor: 1.0), color: NSColor(rgb: 0x6a6a6a)),
        credit: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 13.0, lineSpacingFactor: 1.0), color: NSColor(rgb: 0x6a6a6a)),
        table: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 15.0, lineSpacingFactor: 1.0), color: NSColor(rgb: 0xb0b0b0)),
        article: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 18.0, lineSpacingFactor: 1.0), color: NSColor(rgb: 0xb0b0b0))
    ),
    serif: false,
    codeBlockBackgroundColor: NSColor(rgb: 0x131313),
    linkColor: NSColor(rgb: 0x5ac8fa),
    textHighlightColor: NSColor(rgb: 0xffffff, alpha: 0.1),
    linkHighlightColor: NSColor(rgb: 0x5ac8fa, alpha: 0.2),
    markerColor: NSColor(rgb: 0x313131),
    panelBackgroundColor: NSColor(rgb: 0x131313),
    panelHighlightedBackgroundColor: NSColor(rgb: 0x1f1f1f),
    panelPrimaryColor: NSColor(rgb: 0xb0b0b0),
    panelSecondaryColor: NSColor(rgb: 0x6a6a6a),
    panelAccentColor: NSColor(rgb: 0x50b6f3),
    tableBorderColor: NSColor(rgb: 0x303030),
    tableHeaderColor: NSColor(rgb: 0x131313),
    controlColor: NSColor(rgb: 0x303030),
    imageTintColor: NSColor(rgb: 0xb0b0b0),
    overlayPanelColor: NSColor(rgb: 0x232323),
    separatorColor: NSColor(rgb: 0x6a6a6a),
    quoteAccentColor: NSColor(rgb: 0xb0b0b0)
)

private func fontSizeMultiplierForVariant(_ variant: InstantPagePresentationFontSize) -> CGFloat {
    switch variant {
    case .small:
        return 0.85
    case .standard:
        return 1.0
    case .large:
        return 1.15
    case .xlarge:
        return 1.3
    case .xxlarge:
        return 1.5
    }
}

public func instantPageThemeTypeForSettingsAndTime(settings: InstantViewAppearance, time: Date?) -> InstantPageThemeType {

    return .dark
    
//    switch theme.colors.name {
//
//    }
    
//    if settings.autoNightMode {
//        switch settings.themeType {
//        case .light, .sepia, .gray:
//            var useDarkTheme = false
//            /*switch presentationTheme.name {
//             case let .builtin(name):
//             switch name {
//             case .nightAccent, .nightGrayscale:
//             useDarkTheme = true
//             default:
//             break
//             }
//             default:
//             break
//             }*/
//            if let time = time {
//                let calendar = Calendar.current
//                let hour = calendar.component(.hour, from: time)
//                if hour <= 8 || hour >= 22 {
//                    useDarkTheme = true
//                }
//            }
//            if useDarkTheme {
//                return .dark
//            }
//        case .dark:
//            break
//        }
//    }
//
//    return settings.themeType
}

public func instantPageThemeForType(_ type: InstantPageThemeType, settings: InstantViewAppearance) -> InstantPageTheme {
    switch type {
    case .light:
        return lightTheme.withUpdatedFontStyles(sizeMultiplier: fontSizeMultiplierForVariant(.standard), forceSerif: settings.fontSerif)
    case .sepia:
        return sepiaTheme.withUpdatedFontStyles(sizeMultiplier: fontSizeMultiplierForVariant(.standard), forceSerif: settings.fontSerif)
    case .gray:
        return grayTheme.withUpdatedFontStyles(sizeMultiplier: fontSizeMultiplierForVariant(.standard), forceSerif: settings.fontSerif)
    case .dark:
        return darkTheme.withUpdatedFontStyles(sizeMultiplier: fontSizeMultiplierForVariant(.standard), forceSerif: settings.fontSerif)
    }
}
