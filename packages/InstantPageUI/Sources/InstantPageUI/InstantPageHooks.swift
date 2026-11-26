import Cocoa
import TGUIKit
import TelegramContext
import AudioPlayerCore
import Localization
import TelegramUtils
import TelegramMediaUtils
import TelegramTheme
import Postbox
import TelegramCore
import SwiftSignalKit
import RangeSet
import ChatModeTypes

public struct InstantPageHooks {
    public let highlightCode: (_ code: String, _ language: String, _ isDark: Bool, _ textColor: NSColor, _ textFont: NSFont, _ italicFont: NSFont, _ mediumFont: NSFont, _ themeKeys: [String: NSColor]) -> NSAttributedString?
    public let makeAudioItem: (_ frame: CGRect, _ media: InstantPageMedia) -> InstantPageItem?
    public let openPeer: (_ context: any AccountContextProtocol, _ peerId: PeerId, _ openChat: Bool, _ messageId: MessageId?, _ action: ChatInitialAction?) -> Void
    public let openUrl: (_ context: any AccountContextProtocol, _ url: String, _ webpageId: MediaId?, _ progress: @escaping (CGFloat) -> Void, _ openPeer: @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void, _ setDisposable: @escaping (Disposable?) -> Void) -> Void
    public let audioPlayer: () -> APController?
    public let showGallery: (_ context: any AccountContextProtocol, _ medias: [InstantPageMedia], _ firstIndex: Int, _ interactive: Any?) -> Void
    public let shareLink: (_ context: any AccountContextProtocol, _ link: String, _ window: Window) -> Void

    public init(highlightCode: @escaping (_ code: String, _ language: String, _ isDark: Bool, _ textColor: NSColor, _ textFont: NSFont, _ italicFont: NSFont, _ mediumFont: NSFont, _ themeKeys: [String: NSColor]) -> NSAttributedString?,
                makeAudioItem: @escaping (_ frame: CGRect, _ media: InstantPageMedia) -> InstantPageItem?,
                openPeer: @escaping (_ context: any AccountContextProtocol, _ peerId: PeerId, _ openChat: Bool, _ messageId: MessageId?, _ action: ChatInitialAction?) -> Void,
                openUrl: @escaping (_ context: any AccountContextProtocol, _ url: String, _ webpageId: MediaId?, _ progress: @escaping (CGFloat) -> Void, _ openPeer: @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void, _ setDisposable: @escaping (Disposable?) -> Void) -> Void,
                audioPlayer: @escaping () -> APController?,
                showGallery: @escaping (_ context: any AccountContextProtocol, _ medias: [InstantPageMedia], _ firstIndex: Int, _ interactive: Any?) -> Void,
                shareLink: @escaping (_ context: any AccountContextProtocol, _ link: String, _ window: Window) -> Void) {
        self.highlightCode = highlightCode
        self.makeAudioItem = makeAudioItem
        self.openPeer = openPeer
        self.openUrl = openUrl
        self.audioPlayer = audioPlayer
        self.showGallery = showGallery
        self.shareLink = shareLink
    }

    public static var shared: InstantPageHooks = InstantPageHooks(highlightCode: { _, _, _, _, _, _, _, _ in return nil }, makeAudioItem: { _, _ in return nil }, openPeer: { _, _, _, _, _ in }, openUrl: { _, _, _, _, _, _ in }, audioPlayer: { return nil }, showGallery: { _, _, _, _ in }, shareLink: { _, _, _ in })
}

public func installInstantPageHooks(_ hooks: InstantPageHooks) {
    InstantPageHooks.shared = hooks
}

public func applyHighlightedCode(_ code: NSAttributedString, to: NSMutableAttributedString, offset: Int) {
    code.enumerateAttributes(in: code.range, using: { value, innerRange, _ in
        if let color = value[.foregroundColor] as? NSColor {
            to.addAttribute(.foregroundColor, value: color, range: NSMakeRange(offset + innerRange.location, innerRange.length))
        } else if let font = value[.font] as? NSFont {
            to.addAttribute(.font, value: font, range: NSMakeRange(offset + innerRange.location, innerRange.length))
        }
    })
}
