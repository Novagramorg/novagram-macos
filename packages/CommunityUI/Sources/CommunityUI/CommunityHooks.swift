import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import DateUtils
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import ShortPeerRow
import AvatarUI
import TelegramMediaUtils
import AlertsUI
import LocalAnimations
import MessageTextUtils

public struct CommunityHooks {
    public let selectChatToAdd: (any AccountContextProtocol, String, [PeerId]) -> Signal<[PeerId], NoError>
    public let selectAdmin: (any AccountContextProtocol, String, [PeerId]) -> Signal<[PeerId], NoError>
    public let openChat: (any AccountContextProtocol, PeerId) -> Void
    public let openMainApp: (any AccountContextProtocol, EnginePeer) -> Void
    public let openCommunityEdit: (any AccountContextProtocol, PeerId) -> Void
    public let cropImage: (any AccountContextProtocol, URL, @escaping (URL) -> Void, @escaping () -> Void) -> Void
    public let openBlacklist: (any AccountContextProtocol, PeerId) -> Void

    public init(selectChatToAdd: @escaping (any AccountContextProtocol, String, [PeerId]) -> Signal<[PeerId], NoError>,
                selectAdmin: @escaping (any AccountContextProtocol, String, [PeerId]) -> Signal<[PeerId], NoError>,
                openChat: @escaping (any AccountContextProtocol, PeerId) -> Void,
                openMainApp: @escaping (any AccountContextProtocol, EnginePeer) -> Void,
                openCommunityEdit: @escaping (any AccountContextProtocol, PeerId) -> Void,
                cropImage: @escaping (any AccountContextProtocol, URL, @escaping (URL) -> Void, @escaping () -> Void) -> Void,
                openBlacklist: @escaping (any AccountContextProtocol, PeerId) -> Void) {
        self.selectChatToAdd = selectChatToAdd
        self.selectAdmin = selectAdmin
        self.openChat = openChat
        self.openMainApp = openMainApp
        self.openCommunityEdit = openCommunityEdit
        self.cropImage = cropImage
        self.openBlacklist = openBlacklist
    }

    private static var value: CommunityHooks?

    public static var shared: CommunityHooks {
        guard let value = value else {
            preconditionFailure("CommunityHooks not installed")
        }
        return value
    }

    public static func install(_ hooks: CommunityHooks) {
        self.value = hooks
    }
}

public func installCommunityHooks(_ hooks: CommunityHooks) {
    CommunityHooks.install(hooks)
}

public func generateCommunityHiddenIcon(backgroundColor: NSColor, iconColor: NSColor) -> CGImage {
    let icon = TelegramThemeHooks.shared.image(.iconCommunityHidden).precomposed(iconColor)
    let diameter: CGFloat = 20
    return generateImage(NSMakeSize(diameter, diameter), contextGenerator: { size, ctx in
        ctx.interpolationQuality = .high
        ctx.clear(CGRect(origin: CGPoint(), size: size))
        ctx.setFillColor(backgroundColor.cgColor)
        ctx.fillEllipse(in: NSMakeRect(0, 0, size.width, size.height))
        let iconSize = NSMakeSize(12, 15)
        ctx.draw(icon, in: NSMakeRect(round((size.width - iconSize.width) / 2), round((size.height - iconSize.height) / 2), iconSize.width, iconSize.height))
    })!
}
