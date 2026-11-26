import Cocoa
import Localization
import TelegramUtils
import TelegramMediaUtils
import TelegramTheme
import Postbox
import TelegramCore
import SwiftSignalKit
import RangeSet

import TGUIKit
import TelegramContext
import AudioPlayerCore



public struct InstantPageMedia: Equatable, Identifiable {
    public let index: Int
    public let media: Media
    public let webpage:TelegramMediaWebpage
    public let url: InstantPageUrlItem?
    public let caption: RichText?
    public let credit: RichText?

    public init(index: Int, media: Media, webpage: TelegramMediaWebpage, url: InstantPageUrlItem?, caption: RichText?, credit: RichText?) {
        self.index = index
        self.media = media
        self.webpage = webpage
        self.url = url
        self.caption = caption
        self.credit = credit
    }

    public var stableId: Int {
        return index
    }
    
    public func withUpdatedIndex(_ index: Int) -> InstantPageMedia {
        return InstantPageMedia(index: index, media: self.media, webpage: webpage, url: self.url, caption: self.caption, credit: self.credit)
    }
    
    
    public static func ==(lhs: InstantPageMedia, rhs: InstantPageMedia) -> Bool {
        return lhs.index == rhs.index && lhs.media.isEqual(to: rhs.media) && lhs.url == rhs.url && lhs.caption == rhs.caption && lhs.credit == rhs.credit
    }
}
