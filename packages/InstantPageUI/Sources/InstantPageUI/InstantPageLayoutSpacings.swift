import Cocoa
import TelegramCore
import TelegramTheme
import TelegramUtils
import TelegramContext


// Mirrors telegram-ios's `spacingBetweenBlocks` (InstantPageUI/InstantPageLayoutSpacings.swift). The chat
// renders rich messages with `fitToWidth: true`, so the fitToWidth values are the ones used. Kept in sync
// with iOS — diverging here is what made code blocks / paragraphs / quotes too far apart on macOS.
public func spacingBetweenBlocks(upper: InstantPageBlock?, lower: InstantPageBlock?, fitToWidth: Bool = false) -> CGFloat {
    if let upper, let lower {
        switch (upper, lower) {
        case (_, .cover), (_, .channelBanner), (.details, .details), (.relatedArticles, _), (_, .anchor):
            return 0.0
        case (.divider, _), (_, .divider):
            return fitToWidth ? 16.0 : 25.0
        case (_, .blockQuote), (.blockQuote, _):
            return fitToWidth ? 11.0 : 27.0
        // An unsupported block is a torn band whose own height already carries both torn edges, so it
        // needs only a hair of breathing room — the block-quote gap it used to take detached it from
        // the paragraphs it is supposed to have been torn out of.
        case (_, .unsupported), (.unsupported, _):
            return fitToWidth ? 4.0 : 10.0
        case (_, .pullQuote), (.pullQuote, _):
            return fitToWidth ? 14.0 : 27.0
        case (.kicker, .title), (.cover, .title):
            return 16.0
        case (_, .title):
            return 20.0
        case (.title, .authorDate), (.subtitle, .authorDate):
            return 18.0
        case (_, .authorDate):
            return 20.0
        case (.title, .paragraph), (.authorDate, .paragraph):
            return 34.0
        case (.heading, .heading):
            return fitToWidth ? 8.0 : 32.0
        case (.heading, .paragraph):
            return fitToWidth ? 12.0 : 25.0
        case (.header, .paragraph), (.subheader, .paragraph):
            return fitToWidth ? 14.0 : 25.0
        case (.list, .paragraph):
            return fitToWidth ? 14.0 : 31.0
        case (.paragraph, .list):
            return fitToWidth ? 14.0 : 31.0
        case (.formula, .paragraph):
            return 19.0
        case (.paragraph, .paragraph):
            return fitToWidth ? 2.0 : 25.0
        case (.paragraph, .heading):
            return fitToWidth ? 20.0 : 32.0
        case (.title, .formula), (.authorDate, .formula):
            return 34.0
        case (.header, .formula), (.subheader, .formula), (.heading, .formula):
            return fitToWidth ? 10.0 : 25.0
        case (.list, .formula):
            return 31.0
        case (.paragraph, .formula):
            return 19.0
        case (_, .formula):
            return 20.0
        case (.title, .list), (.authorDate, .list):
            return 34.0
        case (.header, .list), (.subheader, .list), (.heading, .list):
            return 31.0
        case (.preformatted, _), (_, .preformatted):
            return fitToWidth ? 12.0 : 19.0
        case (.formula, .list):
            return fitToWidth ? 10.0 : 25.0
        case (_, .list):
            return fitToWidth ? 10.0 : 25.0
        case (_, .header), (_, .subheader), (_, .heading):
            return 32.0
        // Button rows have no iOS spacing rule (they fall to its 20pt default), but the chat renders
        // with `fitToWidth`, where a paragraph gap is 2pt — 20pt there detaches a row from the text it
        // belongs to. Consecutive rows use the intra-row pill spacing so a wrapped group of buttons
        // reads as one cluster rather than separate blocks.
        case (.buttonRow, .buttonRow):
            return 6.0
        case (_, .buttonRow), (.buttonRow, _):
            return fitToWidth ? 10.0 : 20.0
        default:
            return 20.0
        }
    } else if let lower {
        // Leading spacing before the first block.
        switch lower {
        case .cover, .channelBanner, .details, .anchor:
            return 0.0
        default:
            if fitToWidth {
                switch lower {
                case .heading:
                    return 6.0
                case .table:
                    return 10.0
                case .image, .video, .collage, .slideshow:
                    return 0.0
                default:
                    return 5.0
                }
            } else {
                return 25.0
            }
        }
    } else if let upper {
        // Trailing spacing after the last block.
        if case .relatedArticles = upper {
            return 0.0
        } else if case .thinking = upper {
            return 2.0
        } else if fitToWidth, case .image = upper {
            return 0.0
        } else if fitToWidth, case .video = upper {
            return 0.0
        } else if fitToWidth, case .collage = upper {
            return 0.0
        } else if fitToWidth, case .slideshow = upper {
            return 0.0
        } else {
            return fitToWidth ? 5.0 : 25.0
        }
    } else {
        return 0.0
    }
}
